import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/lottie_box.dart';
import '../shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _login(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ShellScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              const Center(
                child: Text('Wi-Health',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: WiColors.ink,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(height: 16),
              const Center(
                child: LottieBox(
                  asset: 'assets/lottie/auth.json',
                  size: 168,
                  fallback:
                      BreathingRings(size: 160, child: WiLogoMark(size: 76)),
                ),
              ),
              const SizedBox(height: 18),
              const Center(child: Text('Welcome Back', style: WiText.h1)),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Sign in to monitor your loved ones’ breathing.',
                  style: WiText.body.copyWith(color: WiColors.inkFaint),
                ),
              ),
              const SizedBox(height: 36),
              const SoftTextField(
                label: 'Email',
                hint: 'Enter your email',
                suffixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 18),
              const SoftTextField(
                label: 'Password',
                hint: 'Enter your password',
                obscure: true,
                suffixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen())),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                        color: WiColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              PrimaryButton(text: 'Login', onPressed: () => _login(context)),
              const SizedBox(height: 24),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Don’t have an account? ',
                        style: WiText.body.copyWith(fontSize: 13)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SignupScreen())),
                      child: const Text('Sign Up',
                          style: TextStyle(
                              color: WiColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 42),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: WiColors.amber, size: 15),
                    const SizedBox(width: 5),
                    Text('Powered by Firebase',
                        style: WiText.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
