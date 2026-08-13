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
                _deviceCard(context, p),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceCard(BuildContext context, Patient p) {
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
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _confirmRemove(context, p),
              icon: const Icon(Icons.link_off_rounded,
                  color: WiColors.red, size: 18),
              label: const Text('Remove device',
                  style: TextStyle(
                      color: WiColors.red, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, Patient p) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WiColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove this device?'),
        content: Text(
          '${p.deviceName} will be removed from your account and stop showing '
          'here. You can have it re-assigned later by your administrator.',
          style: WiText.body.copyWith(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final error = await app.removeDevice(p.deviceId);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(error ?? 'Device removed.'),
              ));
            },
            child: const Text('Remove',
                style: TextStyle(color: WiColors.red)),
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
