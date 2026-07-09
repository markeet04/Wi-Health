import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/lottie_box.dart';
import 'auth/login_screen.dart';
import 'splash_screen.dart';

/// First-time walkthrough — three gentle pages, then login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      lottie: 'assets/lottie/onboard_breathe.json',
      icon: Icons.air_rounded,
      title: 'Breathe easy,\nwirelessly',
      body:
          'Wi-Health reads the tiny ripples your breathing leaves in WiFi signals. No wearables, no cameras, no microphones — just calm, contactless monitoring.',
    ),
    (
      lottie: 'assets/lottie/onboard_family.json',
      icon: Icons.family_restroom_rounded,
      title: 'Every loved one,\none glance',
      body:
          'Link a sensor to each patient — a parent, a grandparent, a child — and switch between their live breathing feeds like a bedside monitor in your pocket.',
    ),
    (
      lottie: 'assets/lottie/onboard_alerts.json',
      icon: Icons.notifications_active_rounded,
      title: 'Alerts that\nactually matter',
      body:
          'Apnea pauses, unusually fast or slow breathing — confirmed across multiple windows before you’re notified, so every alert is worth waking up for.',
    ),
  ];

  void _finish() {
    SplashScreen.seenOnboarding = true;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: wiSkyGradient),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 22, 0),
                  child: GestureDetector(
                    onTap: _finish,
                    child: Text('Skip',
                        style: WiText.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: WiColors.inkFaint)),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: LottieBox(
                              asset: p.lottie,
                              size: 240,
                              fallback: BreathingRings(
                                size: 220,
                                child: Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    color: WiColors.card,
                                    shape: BoxShape.circle,
                                    boxShadow: wiCardShadow,
                                  ),
                                  child: Icon(p.icon,
                                      color: WiColors.primary, size: 44),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 44),
                          Text(p.title,
                              style: WiText.h1.copyWith(fontSize: 30)),
                          const SizedBox(height: 14),
                          Text(p.body,
                              style: WiText.body.copyWith(
                                  fontSize: 14.5, height: 1.5)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 0, 34, 30),
                child: Row(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _page ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? WiColors.primary
                              : WiColors.primary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    const Spacer(),
                    SizedBox(
                      width: 150,
                      child: PrimaryButton(
                        text: last ? 'Get Started' : 'Next',
                        trailingArrow: !last,
                        onPressed: () {
                          if (last) {
                            _finish();
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
