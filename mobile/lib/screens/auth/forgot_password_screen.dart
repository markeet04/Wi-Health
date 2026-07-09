import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
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
              const SizedBox(height: 34),
              const SoftTextField(
                label: 'Email',
                hint: 'Enter your account email',
                suffixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                text: 'Send Reset Link',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Reset link sent — check your inbox.')));
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
