// Wi-Health frontend smoke tests.
//
// Note: the app has forever-repeating animations (live dot, breathing wave),
// so tests use fixed pump durations instead of pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wi_health/auth/auth_controller.dart';
import 'package:wi_health/auth/mock_auth_service.dart';
import 'package:wi_health/auth/roles.dart';
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
/// Resets the auth session so tests stay independent.
Future<void> bootToLogin(WidgetTester tester,
    {bool skipOnboarding = true}) async {
  SplashScreen.seenOnboarding = skipOnboarding;
  authController.logout(); // fire-and-forget; timer fires in the pumps below
  await tester.pumpWidget(const WiHealthApp());
  // Splash timer (2600 ms) → session restore (mock latency) → fade route.
  await tester.pump(const Duration(milliseconds: 2700));
  await tester.pump(const Duration(milliseconds: 500));
  await pumpTransition(tester);
}

Future<void> enterCredentials(WidgetTester tester,
    {String email = 'qasim@wihealth.app', String password = 'demo123'}) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'Enter your email'), email);
  await tester.enterText(
      find.widgetWithText(TextField, 'Enter your password'), password);
}

Future<void> login(WidgetTester tester) async {
  await bootToLogin(tester);
  await enterCredentials(tester);
  await tester.tap(find.text('Login'));
  // Mock auth latency, then the route transition.
  await tester.pump(const Duration(milliseconds: 500));
  await pumpTransition(tester);
}

void main() {
  testWidgets('splash shows brand then onboarding on first run',
      (tester) async {
    SplashScreen.seenOnboarding = false;
    authController.logout();
    await tester.pumpWidget(const WiHealthApp());

    expect(find.text('Wi-Health'), findsOneWidget);
    expect(find.text('warming up the sensors…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 500));
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
    authController.logout();
    await tester.pumpWidget(const WiHealthApp());
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 500));
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

  testWidgets('login rejects wrong credentials with an error banner',
      (tester) async {
    await bootToLogin(tester);
    await enterCredentials(tester,
        email: 'qasim@wihealth.app', password: 'wrong-pass');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget); // still on login
  });

  testWidgets('RBAC blocks admin accounts from the mobile app',
      (tester) async {
    await bootToLogin(tester);
    await enterCredentials(tester,
        email: 'admin@wihealth.app', password: 'admin123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
        find.text(
            'Admin accounts sign in on the web admin panel, not the mobile app.'),
        findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget); // bounced
    expect(authController.isAuthenticated, isFalse);
  });

  testWidgets('a valid session is restored past login on next launch',
      (tester) async {
    await login(tester); // establishes a session in the mock service

    // Relaunch: splash should restore the session and go straight home.
    SplashScreen.seenOnboarding = true;
    await tester.pumpWidget(const WiHealthApp());
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpTransition(tester);

    expect(find.text('Monitored Patients'), findsOneWidget);
  });

  group('RBAC', () {
    test('permission matrix separates the two roles', () {
      expect(UserRole.appUser.can(Permission.viewOwnPatients), isTrue);
      expect(UserRole.appUser.can(Permission.submitComplaint), isTrue);
      expect(UserRole.appUser.can(Permission.manageUsers), isFalse);
      expect(UserRole.appUser.can(Permission.resolveComplaints), isFalse);

      expect(UserRole.admin.can(Permission.manageUsers), isTrue);
      expect(UserRole.admin.can(Permission.resolveComplaints), isTrue);
      expect(UserRole.admin.can(Permission.viewOwnPatients), isFalse);

      expect(UserRole.appUser.mayUseMobileApp, isTrue);
      expect(UserRole.admin.mayUseMobileApp, isFalse);
    });

    test('roles map onto Firebase custom claims', () {
      expect(UserRole.fromClaim('admin'), UserRole.admin);
      expect(UserRole.fromClaim('app_user'), UserRole.appUser);
      expect(UserRole.fromClaim(null), UserRole.appUser); // safe default
      expect(UserRole.admin.claim, 'admin');
      expect(UserRole.appUser.claim, 'app_user');
    });

    test('mock service seeds demo accounts and auto-provisions new ones',
        () async {
      final service = MockAuthService(latency: Duration.zero);

      final qasim = await service.signIn(
          email: 'qasim@wihealth.app', password: 'demo123');
      expect(qasim.role, UserRole.appUser);
      expect(qasim.linkedDeviceIds, hasLength(3));

      final admin = await service.signIn(
          email: 'admin@wihealth.app', password: 'admin123');
      expect(admin.role, UserRole.admin);

      final fresh = await service.signIn(
          email: 'new.user@example.com', password: 'secret1');
      expect(fresh.role, UserRole.appUser);
      expect(fresh.name, 'New User');

      expect(
        () => service.signUp(
            name: 'Dup',
            email: 'qasim@wihealth.app',
            password: 'whatever1'),
        throwsA(isA<Object>()),
      );
    });
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
