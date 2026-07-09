import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'alert_detail_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  int _filter = 0; // 0 all · 1 urgent · 2 warning · 3 info

  bool _matches(AnomalyAlert a) => switch (_filter) {
        1 => a.severity == AlertSeverity.urgent,
        2 => a.severity == AlertSeverity.warning,
        3 => a.severity == AlertSeverity.info,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final alerts = widget.app.alerts.where(_matches).toList();
        final days = <String, List<AnomalyAlert>>{};
        for (final a in alerts) {
          days.putIfAbsent(a.day, () => []).add(a);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Alert Feed', style: WiText.h1),
                    const Spacer(),
                    Text(
                      '${alerts.where((a) => !a.acknowledged).length} open',
                      style: WiText.body,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _filters(),
                const SizedBox(height: 8),
                for (final day in days.keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
                    child: Text(day.toUpperCase(), style: WiText.label),
                  ),
                  for (final a in days[day]!) ...[
                    _alertCard(context, a),
                    const SizedBox(height: 12),
                  ],
                ],
                if (alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(
                      children: [
                        const CircleBadge(
                          icon: Icons.check_circle_outline_rounded,
                          color: WiColors.green,
                          background: WiColors.greenSoft,
                          size: 64,
                        ),
                        const SizedBox(height: 14),
                        Text('No alerts here', style: WiText.title),
                        const SizedBox(height: 4),
                        Text('Everything is breathing easy.',
                            style: WiText.body),
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

  Widget _filters() {
    const labels = ['All', 'Urgent', 'Warning', 'Info'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = _filter == i;
          return GestureDetector(
            onTap: () => setState(() => _filter = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? WiColors.primary : WiColors.card,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: active ? WiColors.primary : WiColors.line),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: active ? Colors.white : WiColors.inkSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _alertCard(BuildContext context, AnomalyAlert a) {
    final p = widget.app.patientById(a.patientId);
    final (icon, color, bg, sevLabel) = switch (a.severity) {
      AlertSeverity.urgent => (
          Icons.emergency_outlined,
          WiColors.red,
          WiColors.redSoft,
          'URGENT'
        ),
      AlertSeverity.warning => (
          Icons.warning_amber_rounded,
          WiColors.amber,
          WiColors.amberSoft,
          'WARNING'
        ),
      AlertSeverity.info => (
          Icons.info_outline_rounded,
          WiColors.blue,
          WiColors.blueSoft,
          'INFO'
        ),
    };

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AlertDetailScreen(app: widget.app, alert: a))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleBadge(icon: icon, color: color, background: bg, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: WiText.title.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('${p.name} · ${p.room}', style: WiText.caption),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill(text: sevLabel, color: color, background: bg),
                  const SizedBox(height: 4),
                  Text(a.time, style: WiText.caption),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(a.summary, style: WiText.body.copyWith(fontSize: 12.8)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (a.acknowledged)
                const StatusPill(
                  text: 'Acknowledged',
                  color: WiColors.inkSoft,
                  background: WiColors.field,
                  icon: Icons.check_rounded,
                )
              else
                GestureDetector(
                  onTap: () => widget.app.acknowledgeAlert(a.id),
                  child: const StatusPill(
                    text: 'Acknowledge',
                    color: WiColors.primary,
                    background: WiColors.primarySoft,
                    icon: Icons.done_all_rounded,
                  ),
                ),
              const Spacer(),
              const Text('Details',
                  style: TextStyle(
                      color: WiColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded,
                  color: WiColors.primary, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
