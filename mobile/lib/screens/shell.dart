import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import '../mock_data.dart';
import '../models.dart';
import '../theme.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'profile_screen.dart';

/// Root scaffold after login: five tabs with the live monitor as the
/// raised center action — mirroring the Wi-Netra bottom bar.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final AppState app = buildMockAppState();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Identity comes from the auth session; patient/device data stays
    // mocked until the Realtime Database is wired.
    final user = authController.user;
    if (user != null) {
      app.userName = user.name;
      app.userEmail = user.email;
    }
  }

  void _openTab(int i) => setState(() => _tab = i);

  void _openLive(int patientIndex) {
    app.selectPatient(patientIndex);
    setState(() => _tab = 2);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(app: app, onOpenLive: _openLive, onOpenTab: _openTab),
      AlertsScreen(app: app),
      LiveScreen(app: app),
      HistoryScreen(app: app),
      ProfileScreen(app: app),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: _BottomBar(
        app: app,
        current: _tab,
        onSelect: _openTab,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.app,
    required this.current,
    required this.onSelect,
  });

  final AppState app;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WiColors.card,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20304A).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _item(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
              ListenableBuilder(
                listenable: app,
                builder: (context, _) => _item(
                  1,
                  Icons.notifications_rounded,
                  Icons.notifications_none_rounded,
                  'Alerts',
                  badge: app.unacknowledgedUrgent,
                ),
              ),
              _centerButton(),
              _item(3, Icons.history_rounded, Icons.history_rounded, 'History'),
              _item(4, Icons.person_rounded, Icons.person_outline_rounded,
                  'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData active, IconData idle, String label,
      {int badge = 0}) {
    final selected = current == index;
    return Expanded(
      child: InkWell(
        key: ValueKey('nav_$label'),
        onTap: () => onSelect(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? active : idle,
                    size: 23,
                    color: selected ? WiColors.primary : WiColors.inkFaint),
                if (badge > 0)
                  Positioned(
                    right: -5,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: const BoxDecoration(
                          color: WiColors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 15, minHeight: 15),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? WiColors.primary : WiColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerButton() {
    final selected = current == 2;
    return Expanded(
      child: Center(
        child: GestureDetector(
          key: const ValueKey('nav_Live'),
          onTap: () => onSelect(2),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: wiBrandGradient,
              shape: BoxShape.circle,
              boxShadow: wiButtonShadow,
              border: selected
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
            ),
            child: const Icon(Icons.monitor_heart_outlined,
                color: Colors.white, size: 25),
          ),
        ),
      ),
    );
  }
}
