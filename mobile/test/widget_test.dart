// Wi-Health frontend smoke tests.
//
// Note: the app has forever-repeating animations (live dot, breathing wave),
// so tests use fixed pump durations instead of pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wi_health/main.dart';
import 'package:wi_health/mock_data.dart';
import 'package:wi_health/models.dart';
import 'package:wi_health/screens/splash_screen.dart';
import 'package:wi_health/screens/support_screen.dart';

Future<void> pumpTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Boots through splash (and onboarding unless already seen) to login.
Future<void> bootToLogin(WidgetTester tester,
    {bool skipOnboarding = true}) async {
  SplashScreen.seenOnboarding = skipOnboarding;
  await tester.pumpWidget(const WiHealthApp());
  // Let the splash timer fire, then the fade route complete.
  await tester.pump(const Duration(milliseconds: 2700));
  await pumpTransition(tester);
}

Future<void> login(WidgetTester tester) async {
  await bootToLogin(tester);
  await tester.tap(find.text('Login'));
  await pumpTransition(tester);
}

void main() {
  testWidgets('splash shows brand then onboarding on first run',
      (tester) async {
    SplashScreen.seenOnboarding = false;
    await tester.pumpWidget(const WiHealthApp());

    expect(find.text('Wi-Health'), findsOneWidget);
    expect(find.text('warming up the sensors…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2700));
    await pumpTransition(tester);

    // First run → onboarding walkthrough.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.textContaining('Breathe easy'), findsOneWidget);

    // Skip lands on login.
    await tester.tap(find.text('Skip'));
    await pumpTransition(tester);
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('onboarding pages advance with Next until Get Started',
      (tester) async {
    SplashScreen.seenOnboarding = false;
    await tester.pumpWidget(const WiHealthApp());
    await tester.pump(const Duration(milliseconds: 2700));
    await pumpTransition(tester);

    await tester.tap(find.text('Next'));
    await pumpTransition(tester);
    expect(find.textContaining('Every loved one'), findsWidgets);

    await tester.tap(find.text('Next'));
    await pumpTransition(tester);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await pumpTransition(tester);
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('login screen renders core elements', (tester) async {
    await bootToLogin(tester);

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Wi-Health'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('login navigates to the home dashboard', (tester) async {
    await login(tester);

    expect(find.text('Monitored Patients'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);
    // All three hardcoded patients are listed.
    expect(find.text('Ayesha Khan'), findsWidgets);
    expect(find.text('Abdul Rahman'), findsWidgets);
    expect(find.text('Zara'), findsWidgets);
  });

  testWidgets('bottom nav reaches every tab', (tester) async {
    await login(tester);

    await tester.tap(find.byKey(const ValueKey('nav_Alerts')));
    await pumpTransition(tester);
    expect(find.text('Alert Feed').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_Live')));
    await pumpTransition(tester);
    expect(find.text('breaths / min').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_History')));
    await pumpTransition(tester);
    expect(find.text('NIGHTLY AVERAGE · LAST 7 DAYS').hitTestable(),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_Profile')));
    await pumpTransition(tester);
    expect(find.text('Personal Information').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_Home')));
    await pumpTransition(tester);
    expect(find.text('Monitored Patients').hitTestable(), findsOneWidget);
  });

  testWidgets('alert can be acknowledged from the feed', (tester) async {
    await login(tester);

    await tester.tap(find.byKey(const ValueKey('nav_Alerts')));
    await pumpTransition(tester);

    final ackButtons = find.text('Acknowledge');
    expect(ackButtons, findsWidgets);
    final before = tester.widgetList(find.text('Acknowledged')).length;

    await tester.tap(ackButtons.first);
    await tester.pump();

    expect(tester.widgetList(find.text('Acknowledged')).length, before + 1);
  });

  testWidgets('complaint can be submitted from support screen',
      (tester) async {
    await login(tester);

    await tester.tap(find.byKey(const ValueKey('nav_Profile')));
    await pumpTransition(tester);

    final profileScrollable = find
        .descendant(
            of: find.byType(IndexedStack).first,
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Complaints & Support'), 120,
        scrollable: profileScrollable);
    await tester.tap(find.text('Complaints & Support'));
    await pumpTransition(tester);

    expect(find.text('SUBMIT A COMPLAINT'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Brief summary of the issue'),
        'Sensor LED stays red');
    await tester.enterText(
        find.widgetWithText(
            TextField, 'What happened, when, and on which device?'),
        'The bedroom sensor LED has been red since this morning.');

    final supportScrollable = find
        .descendant(
            of: find.byType(SupportScreen), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Submit Complaint'), 120,
        scrollable: supportScrollable);
    await tester.tap(find.text('Submit Complaint'));
    await tester.pump();

    expect(find.text('Sensor LED stays red'), findsOneWidget);
    // Let the confirmation snackbar timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a new patient can be added from home', (tester) async {
    await login(tester);

    await tester.tap(find.text('＋ Add Patient'));
    await pumpTransition(tester);
    expect(find.text('Add Patient'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Ayesha Khan'), 'Bilal Ahmed');
    await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Bedroom, Nursery'), 'Study');

    final scrollable = find
        .descendant(
            of: find.byType(Scaffold).last, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Add & Calibrate'), 120,
        scrollable: scrollable);
    await tester.tap(find.text('Add & Calibrate'));
    await pumpTransition(tester);

    // Back on home — the new patient card is in the list.
    expect(find.text('Bilal Ahmed'), findsWidgets);
    // Let the confirmation snackbar timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  group('AppState', () {
    test('addPatient links a new stable patient', () {
      final app = buildMockAppState();
      final before = app.patients.length;
      app.addPatient(
        name: 'Bilal Ahmed',
        relation: 'Brother',
        room: 'Study',
        deviceId: 'WH-S3-D4E1',
        normalLow: 12,
        normalHigh: 20,
      );
      expect(app.patients.length, before + 1);
      final p = app.patients.last;
      expect(p.name, 'Bilal Ahmed');
      expect(p.status, BreathStatus.normal);
      expect(p.nightlyAvg.length, 7);
      expect(p.bpm, inInclusiveRange(12, 20));
    });

    test('mock data wires three patients with valid contracts', () {
      final app = buildMockAppState();
      expect(app.patients.length, 3);
      for (final p in app.patients) {
        expect(p.trend, isNotEmpty);
        expect(p.nightlyAvg.length, 7);
        expect(p.normalLow, lessThan(p.normalHigh));
      }
      // The low-signal patient must not report a BPM (no guessed values).
      final lowSignal =
          app.patients.where((p) => p.status == BreathStatus.lowSignal);
      expect(lowSignal.every((p) => p.bpm == 0), isTrue);
    });

    test('acknowledgeAlert clears urgent counter', () {
      final app = buildMockAppState();
      final urgentOpen = app.alerts
          .where((a) => a.severity == AlertSeverity.urgent && !a.acknowledged);
      expect(app.unacknowledgedUrgent, urgentOpen.length);
      for (final a in urgentOpen.toList()) {
        app.acknowledgeAlert(a.id);
      }
      expect(app.unacknowledgedUrgent, 0);
    });

    test('submitComplaint prepends an open complaint', () {
      final app = buildMockAppState();
      final before = app.complaints.length;
      app.submitComplaint(
        category: 'App issue',
        subject: 'Chart not loading',
        description: 'History chart spins forever.',
      );
      expect(app.complaints.length, before + 1);
      expect(app.complaints.first.subject, 'Chart not loading');
      expect(app.complaints.first.status, ComplaintStatus.open);
    });
  });
}
