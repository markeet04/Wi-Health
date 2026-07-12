import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    authController.clearError();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final ok = await authController.sendPasswordReset(_email.text);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reset link sent — check your inbox.')));
      Navigator.of(context).pop();
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
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                        color: WiColors.primarySoft, shape: BoxShape.circle),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: WiColors.primary, size: 34),
                  ),
                ),
                const SizedBox(height: 22),
                const Center(child: Text('Reset Password', style: WiText.h1)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'We’ll email you a link to set a new password.',
                    style: WiText.body.copyWith(color: WiColors.inkFaint),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),
                if (authController.error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: WiColors.redSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      authController.error!,
                      style: WiText.body.copyWith(
                          color: WiColors.red,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SoftTextField(
                  label: 'Email',
                  hint: 'Enter your account email',
                  controller: _email,
                  suffixIcon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  text: 'Send Reset Link',
                  loading: authController.busy,
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
