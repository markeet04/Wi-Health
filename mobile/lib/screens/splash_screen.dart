import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import 'auth/login_screen.dart';
import 'onboarding_screen.dart';
import 'shell.dart';

/// Animated splash: the logo "breathes" inside expanding rings while a
/// dots loader warms up, then fades into onboarding (first launch) or login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// In-memory first-run flag; swaps for shared_preferences/Firebase later.
  static bool seenOnboarding = false;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 2600), _next);
  }

  Future<void> _next() async {
    // Restore a persisted session (RBAC-gated: stale admin sessions are
    // signed out) — skip login entirely when one is valid.
    final restored = await authController.restoreSession();
    if (!mounted) return;
    final Widget target = restored
        ? const ShellScreen()
        : SplashScreen.seenOnboarding
            ? const LoginScreen()
            : const OnboardingScreen();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, _, _) => target,
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: wiSkyGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              BreathingRings(
                size: 230,
                child: ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.06).animate(
                      CurvedAnimation(
                          parent: _pulse, curve: Curves.easeInOut)),
                  child: const WiLogoMark(size: 92),
                ),
              ),
              const SizedBox(height: 34),
              const Text('Wi-Health',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: WiColors.ink,
                      letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Text('Every breath, gently watched.',
                  style: WiText.body.copyWith(
                      fontSize: 14, color: WiColors.inkFaint)),
              const Spacer(flex: 3),
              const DotsLoader(),
              const SizedBox(height: 14),
              Text('warming up the sensors…', style: WiText.caption),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
