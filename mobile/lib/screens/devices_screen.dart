import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Devices'),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in app.patients) ...[
                _deviceCard(p),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceCard(Patient p) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleBadge(
                icon: Icons.sensors_rounded,
                color: p.online ? WiColors.primary : WiColors.inkFaint,
                background: p.online ? WiColors.primarySoft : WiColors.field,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.deviceName,
                        style: WiText.title.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('ESP32-S3 · ${p.deviceId}', style: WiText.caption),
                  ],
                ),
              ),
              StatusPill(
                text: p.online ? 'Online' : 'Offline',
                color: p.online ? WiColors.green : WiColors.inkFaint,
                background: p.online ? WiColors.greenSoft : WiColors.field,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _row('Monitoring', '${p.name} · ${p.relation}'),
          _row('Room', p.room),
          _row('Firmware', p.firmware),
          _row('Last sync', p.lastSync),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text('Signal quality',
                      style: WiText.body.copyWith(fontSize: 12.5))),
              Expanded(
                child: SoftMeter(
                  value: p.signalQuality,
                  color: p.signalQuality >= 0.6
                      ? WiColors.primary
                      : WiColors.amber,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${(p.signalQuality * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: WiText.title.copyWith(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: WiText.body)),
          Expanded(
            child: Text(value,
                style: WiText.title.copyWith(fontSize: 13),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
