import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'link_device_screen.dart';
import 'pairing_wizard_screen.dart';

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

  void _linkDevice(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LinkDeviceScreen(app: app)));
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
                if (app.pairingCode != null && !app.pairingCode!.isExpired) ...[
                  _pairingCard(context, app.pairingCode!),
                  const SizedBox(height: 16),
                ],
                // First-run welcome for a brand-new account with no device yet:
                // a short intro + what each tab does + a clear way forward.
                if (app.patients.isEmpty &&
                    !app.welcomeDismissed &&
                    (app.pairingCode == null || app.pairingCode!.isExpired)) ...[
                  _welcomeCard(context),
                  const SizedBox(height: 16),
                ],
                _statusCard(allStable, lowSignal),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Monitored Patients',
                  actionText: '＋ Request Device',
                  onAction: () => _linkDevice(context),
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
        // Reflects real liveness: LIVE only when at least one device is online,
        // otherwise OFFLINE — not a static badge.
        Builder(builder: (_) {
          final anyOnline = app.patients.any((p) => p.online);
          return StatusPill(
            text: anyOnline ? 'LIVE' : 'OFFLINE',
            color: anyOnline ? WiColors.green : WiColors.inkFaint,
            background: anyOnline ? WiColors.greenSoft : WiColors.field,
            dot: true,
          );
        }),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => onOpenTab(1),
          behavior: HitTestBehavior.opaque,
          child: Stack(
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
        ),
      ],
    );
  }

  Widget _welcomeCard(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleBadge(
                icon: Icons.waving_hand_rounded,
                color: WiColors.primary,
                background: WiColors.primarySoft,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Welcome to Wi-Health',
                    style: WiText.title.copyWith(fontSize: 15.5)),
              ),
              GestureDetector(
                onTap: () => app.dismissWelcome(),
                child: const Icon(Icons.close_rounded,
                    color: WiColors.inkFaint, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Contactless breathing monitoring for the people you care about. '
            'Here\'s what you\'ll find:',
            style: WiText.caption.copyWith(color: WiColors.inkSoft),
          ),
          const SizedBox(height: 14),
          _tabHint(Icons.home_rounded, 'Home',
              'Your patients at a glance and recent activity.'),
          _tabHint(Icons.notifications_none_rounded, 'Alerts',
              'Apnea, fast or slow breathing — as they happen.'),
          _tabHint(Icons.monitor_heart_outlined, 'Live',
              'A real-time breathing readout for the selected patient.'),
          _tabHint(Icons.history_rounded, 'History',
              'Daily trends, sessions and the anomaly timeline.'),
          _tabHint(Icons.person_outline_rounded, 'Profile',
              'Your account, devices and support.'),
          const SizedBox(height: 16),
          Text(
            'To start monitoring, request a device — your administrator will '
            'assign one and send you a pairing code.',
            style: WiText.caption.copyWith(color: WiColors.inkSoft),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            text: 'Request a device',
            trailingArrow: true,
            onPressed: () => _linkDevice(context),
          ),
        ],
      ),
    );
  }

  Widget _tabHint(IconData icon, String label, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: WiColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: WiText.caption.copyWith(color: WiColors.inkSoft),
                children: [
                  TextSpan(
                      text: '$label — ',
                      style: WiText.title.copyWith(fontSize: 12.5)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairingCard(BuildContext context, PairingCode pc) {
    return SoftCard(
      color: WiColors.primarySoft,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleBadge(
                icon: Icons.router_outlined,
                color: WiColors.primary,
                background: Colors.white,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Your device is ready to set up',
                    style: WiText.title.copyWith(fontSize: 14.5)),
              ),
              GestureDetector(
                onTap: () => app.dismissPairingCode(),
                child: const Icon(Icons.close_rounded,
                    color: WiColors.inkFaint, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Connect your phone to the "Wi-Health-Setup" WiFi, then enter this '
            'pairing code to link the device to your account:',
            style: WiText.caption.copyWith(color: WiColors.inkSoft),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WiColors.line),
            ),
            alignment: Alignment.center,
            child: Text(
              pc.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: WiColors.primaryDeep,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: pc.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pairing code copied.')));
                },
                child: const StatusPill(
                  text: 'Copy code',
                  color: WiColors.primary,
                  background: Colors.white,
                  icon: Icons.copy_rounded,
                ),
              ),
              const Spacer(),
              Text('Expires ${_shortTime(pc.expiresAt)}',
                  style: WiText.caption),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: 'Show set-up guide',
            trailingArrow: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PairingWizardScreen(code: pc.code))),
          ),
        ],
      ),
    );
  }

  String _shortTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
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
          Icons.monitor_heart_outlined,
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
