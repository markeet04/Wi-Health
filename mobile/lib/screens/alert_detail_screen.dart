import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/breathing_wave.dart';
import '../widgets/common.dart';

/// Anomaly event details — the Wi-Health analog of the intrusion app's
/// "Video Event Details": waveform snapshot instead of a video clip.
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.app, required this.alert});

  final AppState app;
  final AnomalyAlert alert;

  @override
  Widget build(BuildContext context) {
    final p = app.patientById(alert.patientId);
    final (color, bg) = switch (alert.severity) {
      AlertSeverity.urgent => (WiColors.red, WiColors.redSoft),
      AlertSeverity.warning => (WiColors.amber, WiColors.amberSoft),
      AlertSeverity.info => (WiColors.blue, WiColors.blueSoft),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Anomaly Event Details'),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SoftCard(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusPill(
                          text: alert.severity.name.toUpperCase(),
                          color: color,
                          background: bg,
                        ),
                        const Spacer(),
                        Text('${alert.day} · ${alert.time}',
                            style: WiText.caption),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(alert.title, style: WiText.h2),
                    const SizedBox(height: 4),
                    Text('${p.name} · ${p.room}', style: WiText.body),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: WiColors.bg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BREATHING WAVEFORM · EVENT WINDOW',
                              style: WiText.label.copyWith(fontSize: 9.5)),
                          const SizedBox(height: 8),
                          WaveSnapshot(
                            color: color,
                            flatSegment:
                                alert.severity == AlertSeverity.urgent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SoftCard(
                color: WiColors.greenSoft,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        color: WiColors.green, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Privacy Guaranteed',
                              style: WiText.title.copyWith(
                                  fontSize: 13.5, color: WiColors.green)),
                          const SizedBox(height: 2),
                          Text(
                            'Detected via WiFi signal patterns on-device. No camera, no microphone, no raw data uploaded.',
                            style: WiText.caption
                                .copyWith(color: WiColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DETECTION DATA', style: WiText.label),
                    const SizedBox(height: 6),
                    for (final entry in alert.detail.entries) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(entry.key, style: WiText.body),
                            ),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: WiText.title.copyWith(fontSize: 13),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (entry.key != alert.detail.keys.last)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!alert.acknowledged)
                PrimaryButton(
                  text: 'Acknowledge Alert',
                  trailingArrow: false,
                  onPressed: () {
                    app.acknowledgeAlert(alert.id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Alert acknowledged.')));
                    Navigator.of(context).pop();
                  },
                )
              else
                Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: WiColors.field,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded,
                          color: WiColors.inkSoft, size: 18),
                      SizedBox(width: 8),
                      Text('Acknowledged',
                          style: TextStyle(
                              color: WiColors.inkSoft,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
