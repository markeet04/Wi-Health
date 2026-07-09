import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('App Settings'),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('NOTIFICATIONS'),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    _toggleRow(
                      'Push notifications',
                      'Alerts delivered even away from home',
                      app.pushEnabled,
                      app.setPush,
                    ),
                    const Divider(height: 1),
                    _toggleRow(
                      'Urgent alerts only',
                      'Mute informational and warning alerts',
                      app.urgentOnly,
                      app.setUrgentOnly,
                    ),
                    const Divider(height: 1),
                    _toggleRow(
                      'Alert sound',
                      'Play a distinct tone for urgent alerts',
                      app.soundEnabled,
                      app.setSound,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _label('ALERT THRESHOLDS'),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rule-based detection bounds, applied on-device. Per-patient bands are set by your care team.',
                      style: WiText.caption,
                    ),
                    const SizedBox(height: 14),
                    _thresholdRow(Icons.pause_circle_outline_rounded,
                        WiColors.red, WiColors.redSoft, 'Apnea', 'No valid breathing > 20 s'),
                    const Divider(height: 18),
                    _thresholdRow(Icons.trending_up_rounded, WiColors.amber,
                        WiColors.amberSoft, 'Tachypnea', 'Above the upper band bound'),
                    const Divider(height: 18),
                    _thresholdRow(Icons.trending_down_rounded, WiColors.blue,
                        WiColors.blueSoft, 'Bradypnea', 'Below the lower band bound'),
                    const Divider(height: 18),
                    _thresholdRow(Icons.how_to_vote_outlined, WiColors.primary,
                        WiColors.primarySoft, 'Temporal voting', '3 consecutive windows to alert'),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _label('ABOUT'),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    _aboutRow('Version', 'v0.1.0 (prototype)'),
                    const Divider(height: 1),
                    _aboutRow('Sensing', 'WiFi CSI · ESP32-S3 · 10 Hz'),
                    const Divider(height: 1),
                    _aboutRow('Scope',
                        'Research prototype — not a medical device'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 10),
        child: Text(text, style: WiText.label),
      );

  Widget _toggleRow(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WiText.title.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: WiText.caption),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: WiColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _thresholdRow(
      IconData icon, Color color, Color bg, String title, String value) {
    return Row(
      children: [
        CircleBadge(icon: icon, color: color, background: bg, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: WiText.title.copyWith(fontSize: 13.5)),
        ),
        Text(value, style: WiText.caption),
      ],
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label, style: WiText.body),
          const Spacer(),
          Expanded(
            child: Text(value,
                style: WiText.title.copyWith(fontSize: 12.5),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
