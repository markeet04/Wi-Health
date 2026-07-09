import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'add_patient_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.app,
    required this.onOpenLive,
    required this.onOpenTab,
  });

  final AppState app;
  final ValueChanged<int> onOpenLive;
  final ValueChanged<int> onOpenTab;

  void _addPatient(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddPatientScreen(app: app)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final allStable = app.patients.every((p) => p.hasValidBreathing);
        final lowSignal =
            app.patients.where((p) => !p.hasValidBreathing).toList();

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _statusCard(allStable, lowSignal),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Monitored Patients',
                  actionText: '＋ Add Patient',
                  onAction: () => _addPatient(context),
                ),
                for (var i = 0; i < app.patients.length; i++) ...[
                  _patientCard(app.patients[i], i),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 12),
                SectionHeader(
                  title: 'Recent Activity',
                  actionText: 'See all →',
                  onAction: () => onOpenTab(3),
                ),
                SoftCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < app.activity.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 52),
                        _activityRow(app.activity[i]),
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

  Widget _topBar() {
    return Row(
      children: [
        const WiLogoMark(size: 30),
        const SizedBox(width: 10),
        const Text('Wi-Health',
            style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: WiColors.ink)),
        const Spacer(),
        const StatusPill(
          text: 'LIVE',
          color: WiColors.green,
          background: WiColors.greenSoft,
          dot: true,
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded,
                color: WiColors.inkSoft, size: 23),
            if (app.unacknowledgedUrgent > 0)
              Positioned(
                right: 1,
                top: 1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: WiColors.red, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statusCard(bool allStable, List<Patient> lowSignal) {
    final title = allStable
        ? 'All Stable — ${app.patients.length} Patients'
        : 'Signal Low — ${lowSignal.map((p) => p.room).join(', ')}';
    final subtitle = allStable
        ? 'Monitoring active · All devices online'
        : 'Breathing readout paused for ${lowSignal.map((p) => p.name.split(' ').first).join(', ')} · check placement';
    final color = allStable ? WiColors.green : WiColors.amber;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 82,
                height: 82,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: WiColors.primarySoft, shape: BoxShape.circle),
                child: const WiLogoMark(size: 54),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Icon(
                    allStable ? Icons.check_rounded : Icons.priority_high_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: WiText.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: WiText.body.copyWith(color: WiColors.inkFaint),
              textAlign: TextAlign.center),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _quickStat('${app.patients.length}', 'Patients'),
              _statDivider(),
              _quickStat(
                  '${app.patients.where((p) => p.online).length}', 'Online'),
              _statDivider(),
              ListenableBuilder(
                listenable: app,
                builder: (context, _) => _quickStat(
                    '${app.alerts.where((a) => !a.acknowledged).length}',
                    'Open alerts'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: WiColors.ink)),
        const SizedBox(height: 2),
        Text(label, style: WiText.caption),
      ],
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 26,
        color: WiColors.line,
        margin: const EdgeInsets.symmetric(horizontal: 22),
      );

  Widget _patientCard(Patient p, int index) {
    final (statusText, statusColor, statusBg) = switch (p.status) {
      BreathStatus.normal => ('Stable', WiColors.green, WiColors.greenSoft),
      BreathStatus.lowSignal => (
          'Signal Low',
          WiColors.amber,
          WiColors.amberSoft
        ),
      BreathStatus.noBreathing => ('Check now', WiColors.red, WiColors.redSoft),
    };

    return SoftCard(
      onTap: () => onOpenLive(index),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: WiColors.primarySoft, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  p.initials,
                  style: const TextStyle(
                      color: WiColors.primaryDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: p.online ? WiColors.green : WiColors.inkFaint,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: WiText.title.copyWith(fontSize: 14.5)),
                const SizedBox(height: 3),
                Text('${p.room} · ${p.deviceName}', style: WiText.caption),
                const SizedBox(height: 8),
                SizedBox(
                  width: 120,
                  child: Sparkline(
                    values: p.trend,
                    height: 26,
                    color: p.hasValidBreathing
                        ? WiColors.primary
                        : WiColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (p.hasValidBreathing)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p.bpm}',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: WiColors.ink,
                            height: 1)),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3, left: 3),
                      child: Text('bpm', style: WiText.caption),
                    ),
                  ],
                )
              else
                const Text('——',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: WiColors.inkFaint,
                        height: 1)),
              const SizedBox(height: 8),
              StatusPill(
                  text: statusText, color: statusColor, background: statusBg),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityRow(ActivityEvent e) {
    final (icon, color, bg) = switch (e.kind) {
      'alert' => (
          Icons.warning_amber_rounded,
          WiColors.amber,
          WiColors.amberSoft
        ),
      'signal' => (Icons.wifi_tethering_rounded, WiColors.blue, WiColors.blueSoft),
      'session' => (
          Icons.nightlight_round,
          WiColors.nightIndigo,
          WiColors.nightSoft
        ),
      _ => (Icons.settings_suggest_outlined, WiColors.primary, WiColors.primarySoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          CircleBadge(icon: icon, color: color, background: bg, size: 38),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: WiText.title.copyWith(fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(e.subtitle, style: WiText.caption),
              ],
            ),
          ),
          Text(e.time, style: WiText.caption),
        ],
      ),
    );
  }
}
