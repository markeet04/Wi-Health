import 'package:flutter_test/flutter_test.dart';
import 'package:wi_health/models.dart';

void main() {
  test('acknowledgeAlert persists to the handler and updates state', () async {
    final alert = AnomalyAlert(
      id: 'alert-1',
      patientId: 'device-1',
      title: 'Apnea event',
      severity: AlertSeverity.urgent,
      time: '9:12 AM',
      day: 'Today',
      summary: 'Apnea detected',
      detail: {'BPM': '8'},
    );
    final app = AppState.empty();
    app.setAlerts([alert]);

    var handled = false;
    String? handledId;
    app.acknowledgeAlertHandler = (String id, {required String uid}) async {
      handled = true;
      handledId = id;
    };

    await app.acknowledgeAlert(alert.id, uid: 'user-1');

    expect(handled, isTrue);
    expect(handledId, alert.id);
    expect(app.alerts.first.acknowledged, isTrue);
  });

  test('dismissAlert removes the alert from the local feed', () async {
    final alert = AnomalyAlert(
      id: 'alert-2',
      patientId: 'device-2',
      title: 'Low signal',
      severity: AlertSeverity.warning,
      time: '8:40 PM',
      day: 'Yesterday',
      summary: 'Signal dropped',
      detail: {'Signal': 'poor'},
    );
    final app = AppState.empty();
    app.setAlerts([alert]);

    var handled = false;
    app.dismissAlertHandler = (String id, {required String uid}) async {
      handled = true;
    };

    await app.dismissAlert(alert.id, uid: 'user-2');

    expect(handled, isTrue);
    expect(app.alerts, isEmpty);
  });
}
