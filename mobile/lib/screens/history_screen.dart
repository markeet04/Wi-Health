import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.app});

  final AppState app;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _patient = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.patients[_patient];
        final sessions =
            app.sessions.where((s) => s.patientId == p.id).toList();
        final alerts = app.alerts.where((a) => a.patientId == p.id).toList();

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('History', style: WiText.h1),
                const SizedBox(height: 16),
                PatientChips(
                  names:
                      app.patients.map((x) => x.name.split(' ').first).toList(),
                  selected: _patient,
                  onSelect: (i) => setState(() => _patient = i),
                ),
                const SizedBox(height: 18),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('NIGHTLY AVERAGE · LAST 7 DAYS',
                              style: WiText.label),
                          const Spacer(),
                          Text('bpm', style: WiText.caption),
                        ],
                      ),
                      const SizedBox(height: 16),
                      WeekBars(values: p.nightlyAvg),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RATE DISTRIBUTION · SHARE OF TIME',
                          style: WiText.label),
                      const SizedBox(height: 16),
                      DistributionBars(
                        values: p.distribution,
                        bucketLabels: _buckets(p),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionHeader(title: 'Sessions'),
                for (final s in sessions) ...[
                  _sessionCard(s),
                  const SizedBox(height: 12),
                ],
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No sessions recorded yet.',
                        style: WiText.body),
                  ),
                const SizedBox(height: 10),
                SectionHeader(title: 'Anomaly Timeline'),
                SoftCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: alerts.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text('No anomalies for ${p.name.split(' ').first} — steady breathing.',
                              style: WiText.body),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < alerts.length; i++) ...[
                              if (i > 0) const Divider(height: 1, indent: 48),
                              _timelineRow(alerts[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _buckets(Patient p) {
    final span = (p.normalHigh + 8) - (p.normalLow - 6);
    final step = (span / p.distribution.length).ceil();
    final start = p.normalLow - 6;
    return [
      for (var i = 0; i < p.distribution.length; i++)
        '${start + i * step}–${start + (i + 1) * step}',
    ];
  }

  Widget _sessionCard(SessionLog s) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleBadge(
                icon: Icons.nightlight_round,
                color: WiColors.nightIndigo,
                background: WiColors.nightSoft,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: WiText.title.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('${s.day} · ended ${s.time}', style: WiText.caption),
                  ],
                ),
              ),
              StatusPill(
                text: '${s.quality}% valid',
                color: s.quality >= 90 ? WiColors.green : WiColors.amber,
                background:
                    s.quality >= 90 ? WiColors.greenSoft : WiColors.amberSoft,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _mini('Duration', s.duration),
              _miniDivider(),
              _mini('Avg', '${s.avgBpm.toStringAsFixed(1)} bpm'),
              _miniDivider(),
              _mini('Range', '${s.minBpm}–${s.maxBpm} bpm'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: WiText.caption),
          const SizedBox(height: 2),
          Text(value, style: WiText.title.copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _miniDivider() => Container(
      width: 1,
      height: 26,
      color: WiColors.line,
      margin: const EdgeInsets.only(right: 14));

  Widget _timelineRow(AnomalyAlert a) {
    final (icon, color, bg) = switch (a.severity) {
      AlertSeverity.urgent => (
          Icons.emergency_outlined,
          WiColors.red,
          WiColors.redSoft
        ),
      AlertSeverity.warning => (
          Icons.warning_amber_rounded,
          WiColors.amber,
          WiColors.amberSoft
        ),
      AlertSeverity.info => (
          Icons.info_outline_rounded,
          WiColors.blue,
          WiColors.blueSoft
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          CircleBadge(icon: icon, color: color, background: bg, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: WiText.title.copyWith(fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${a.day} · ${a.time}', style: WiText.caption),
              ],
            ),
          ),
          if (a.acknowledged)
            const Icon(Icons.check_rounded, color: WiColors.green, size: 17),
        ],
      ),
    );
  }
}
