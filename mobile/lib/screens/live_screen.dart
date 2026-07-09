import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/breathing_wave.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.current;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Live Monitor', style: WiText.h1),
                    const Spacer(),
                    StatusPill(
                      text: p.online ? 'DEVICE ONLINE' : 'OFFLINE',
                      color: p.online ? WiColors.green : WiColors.inkFaint,
                      background:
                          p.online ? WiColors.greenSoft : WiColors.field,
                      dot: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PatientChips(
                  names: app.patients
                      .map((x) => x.name.split(' ').first)
                      .toList(),
                  selected: app.selectedPatient,
                  onSelect: app.selectPatient,
                ),
                const SizedBox(height: 16),
                _readoutCard(p),
                const SizedBox(height: 14),
                _signalCard(p),
                const SizedBox(height: 14),
                _tonightCard(p),
                const SizedBox(height: 14),
                _deviceCard(p),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _readoutCard(Patient p) {
    final valid = p.hasValidBreathing;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              Text('${p.name} · ${p.room}',
                  style: WiText.title.copyWith(fontSize: 13.5)),
              const Spacer(),
              const LiveDot(),
              const SizedBox(width: 6),
              Text('10 Hz CSI', style: WiText.caption),
            ],
          ),
          const SizedBox(height: 18),
          if (valid) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${p.bpm}',
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    color: WiColors.ink,
                    height: 0.95,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10, left: 8),
                  child: Text('breaths / min',
                      style: TextStyle(
                          fontSize: 13,
                          color: WiColors.inkFaint,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            StatusPill(
              text: 'WITHIN NORMAL ${p.normalLow}–${p.normalHigh} BPM',
              color: WiColors.green,
              background: WiColors.greenSoft,
              icon: Icons.check_circle_rounded,
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '——',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: WiColors.inkFaint,
                  height: 0.95),
            ),
            const SizedBox(height: 10),
            const StatusPill(
              text: 'NO VALID BREATHING — SIGNAL LOW',
              color: WiColors.amber,
              background: WiColors.amberSoft,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: 6),
            Text(
              'Rate withheld rather than guessed. Check device placement.',
              style: WiText.caption,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 10),
          BreathingWave(bpm: p.bpm, active: valid),
        ],
      ),
    );
  }

  Widget _signalCard(Patient p) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIGNAL & CONFIDENCE', style: WiText.label),
          const SizedBox(height: 14),
          _meterRow(
            'Estimator confidence',
            p.confidence,
            p.confidence >= 0.6 ? WiColors.primary : WiColors.amber,
          ),
          const SizedBox(height: 12),
          _meterRow(
            'CSI signal quality',
            p.signalQuality,
            p.signalQuality >= 0.6 ? WiColors.blue : WiColors.amber,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: WiColors.green, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Privacy guaranteed — raw WiFi signal is processed on-device and discarded. Only the rate leaves the sensor.',
                  style: WiText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meterRow(String label, double value, Color color) {
    return Row(
      children: [
        Expanded(
            flex: 5,
            child:
                Text(label, style: WiText.body.copyWith(fontSize: 12.5))),
        Expanded(flex: 5, child: SoftMeter(value: value, color: color)),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: WiText.title.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _tonightCard(Patient p) {
    final valid = p.hasValidBreathing;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAST SESSION', style: WiText.label),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('Min',
                  valid ? '${p.trend.reduce((a, b) => a < b ? a : b).round()}' : '—'),
              _vDivider(),
              _stat(
                  'Avg',
                  valid
                      ? (p.trend.reduce((a, b) => a + b) / p.trend.length)
                          .toStringAsFixed(1)
                      : '—'),
              _vDivider(),
              _stat('Max',
                  valid ? '${p.trend.reduce((a, b) => a > b ? a : b).round()}' : '—'),
              _vDivider(),
              _stat('Band', '${p.normalLow}–${p.normalHigh}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WiColors.ink)),
          const SizedBox(height: 2),
          Text(label, style: WiText.caption),
        ],
      ),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 26, color: WiColors.line);

  Widget _deviceCard(Patient p) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleBadge(
            icon: Icons.sensors_rounded,
            color: WiColors.primary,
            background: WiColors.primarySoft,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.deviceName, style: WiText.title.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text('ESP32-S3 · ${p.deviceId} · fw ${p.firmware}',
                    style: WiText.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(
                text: p.online ? 'Online' : 'Offline',
                color: p.online ? WiColors.green : WiColors.inkFaint,
                background: p.online ? WiColors.greenSoft : WiColors.field,
                dot: true,
              ),
              const SizedBox(height: 4),
              Text('sync ${p.lastSync}', style: WiText.caption),
            ],
          ),
        ],
      ),
    );
  }
}
