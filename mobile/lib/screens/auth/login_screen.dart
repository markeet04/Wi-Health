import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/lottie_box.dart';
import '../shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    authController.clearError();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final ok = await authController.login(_email.text, _password.text);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ShellScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: ListenableBuilder(
            listenable: authController,
            builder: (context, _) => Column(
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
                const SizedBox(height: 30),
                if (authController.error != null) ...[
                  _ErrorBanner(message: authController.error!),
                  const SizedBox(height: 16),
                ],
                SoftTextField(
                  label: 'Email',
                  hint: 'Enter your email',
                  controller: _email,
                  suffixIcon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 18),
                SoftTextField(
                  label: 'Password',
                  hint: 'Enter your password',
                  controller: _password,
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
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'Login',
                  loading: authController.busy,
                  onPressed: _login,
                ),
                const SizedBox(height: 22),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Don’t have an account? ',
                          style: WiText.body.copyWith(fontSize: 13)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
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
                const SizedBox(height: 26),
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
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WiColors.redSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: WiColors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: WiText.body.copyWith(
                  color: WiColors.red,
                  fontSize: 12.8,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
