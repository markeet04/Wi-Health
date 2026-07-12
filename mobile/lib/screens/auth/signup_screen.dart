import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    authController.clearError();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    FocusScope.of(context).unfocus();
    final ok = await authController.signup(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      confirmPassword: _confirm.text,
    );
    if (ok && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ShellScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Wi-Health'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: ListenableBuilder(
            listenable: authController,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                        color: WiColors.primarySoft, shape: BoxShape.circle),
                    child: const Icon(Icons.person_add_alt_1_outlined,
                        color: WiColors.primary, size: 32),
                  ),
                ),
                const SizedBox(height: 22),
                const Center(child: Text('Create Account', style: WiText.h1)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'One account for patients and caregivers alike.',
                    style: WiText.body.copyWith(color: WiColors.inkFaint),
                  ),
                ),
                const SizedBox(height: 26),
                if (authController.error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                            authController.error!,
                            style: WiText.body.copyWith(
                                color: WiColors.red,
                                fontSize: 12.8,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SoftTextField(
                  label: 'Full name',
                  hint: 'Enter your full name',
                  controller: _name,
                  suffixIcon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 18),
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
                  hint: 'Create a password (6+ characters)',
                  controller: _password,
                  obscure: true,
                  suffixIcon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 18),
                SoftTextField(
                  label: 'Confirm password',
                  hint: 'Repeat your password',
                  controller: _confirm,
                  obscure: true,
                  suffixIcon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  text: 'Sign Up',
                  loading: authController.busy,
                  onPressed: _signup,
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'We’ll send a verification link to your email.',
                    style: WiText.caption,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
