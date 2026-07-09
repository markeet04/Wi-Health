import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shell.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

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
          child: Column(
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
              const SizedBox(height: 32),
              const SoftTextField(
                label: 'Full name',
                hint: 'Enter your full name',
                suffixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 18),
              const SoftTextField(
                label: 'Email',
                hint: 'Enter your email',
                suffixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 18),
              const SoftTextField(
                label: 'Password',
                hint: 'Create a password',
                obscure: true,
                suffixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 18),
              const SoftTextField(
                label: 'Confirm password',
                hint: 'Repeat your password',
                obscure: true,
                suffixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 30),
              PrimaryButton(
                text: 'Sign Up',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ShellScreen()),
                ),
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
    );
  }
}
