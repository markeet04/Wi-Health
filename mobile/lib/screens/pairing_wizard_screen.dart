import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../theme.dart';
import '../widgets/common.dart';

/// Step-by-step guide for setting up a newly-issued device using a pairing code.
/// Opened from the pairing-code card on Home. Walks the caretaker through the
/// captive-portal flow (connect to the device hotspot -> enter WiFi + code).
class PairingWizardScreen extends StatefulWidget {
  const PairingWizardScreen({super.key, required this.code});

  final String code;

  @override
  State<PairingWizardScreen> createState() => _PairingWizardScreenState();
}

class _PairingWizardScreenState extends State<PairingWizardScreen> {
  final _controller = PageController();
  int _page = 0;

  late final List<_Step> _steps = [
    const _Step(
      icon: Icons.power_settings_new_rounded,
      title: 'Power on your device',
      body:
          'Plug in your Wi-Health uploader box. Give it a few seconds to start '
          'up — it will create its own temporary WiFi network for setup.',
    ),
    const _Step(
      icon: Icons.wifi_rounded,
      title: 'Connect to "Wi-Health-Setup"',
      body:
          'Open your phone\'s WiFi settings and connect to the network called '
          '"Wi-Health-Setup". A setup page should open automatically — if it '
          'doesn\'t, open your browser and it will appear.',
    ),
    _Step(
      icon: Icons.key_rounded,
      title: 'Enter your WiFi and this code',
      body:
          'On the setup page, choose your home WiFi, type its password, and '
          'enter the pairing code below. Then tap Connect.',
      showCode: true,
    ),
    const _Step(
      icon: Icons.check_circle_outline_rounded,
      title: 'You\'re all set',
      body:
          'Your device will join your WiFi and link to your account. It should '
          'appear on your dashboard within about a minute — no need to keep this '
          'page open.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _steps.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Device Setup'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (context, i) => _stepView(_steps[i], i),
              ),
            ),
            _dots(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  if (_page > 0)
                    Expanded(
                      child: TextButton(
                        onPressed: () => _controller.previousPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      text: isLast ? 'Done' : 'Next',
                      trailingArrow: !isLast,
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepView(_Step step, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: CircleBadge(
              icon: step.icon,
              color: WiColors.primary,
              background: WiColors.primarySoft,
              size: 76,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Step ${index + 1} of ${_steps.length}',
                style: WiText.label),
          ),
          const SizedBox(height: 12),
          Text(step.title, style: WiText.h1, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(step.body,
              style: WiText.body.copyWith(height: 1.55),
              textAlign: TextAlign.center),
          if (step.showCode) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: WiColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: WiColors.primary.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: WiColors.primaryDeep,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pairing code copied.')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _steps.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _page ? WiColors.primary : WiColors.line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.showCode = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showCode;
}
