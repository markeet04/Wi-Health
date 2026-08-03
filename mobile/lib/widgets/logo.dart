import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// The Wi-Health brand mark: the heart-pulse logo image, clipped to a
/// squircle with the brand drop shadow.
class WiLogoMark extends StatelessWidget {
  const WiLogoMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: WiColors.primary.withValues(alpha: 0.35),
            blurRadius: size * 0.32,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}

/// Calm expanding "breath" rings — used behind the logo on splash, login,
/// and onboarding. Purely decorative, endlessly gentle.
class BreathingRings extends StatefulWidget {
  const BreathingRings({
    super.key,
    this.size = 200,
    this.color = WiColors.primary,
    this.child,
  });

  final double size;
  final Color color;
  final Widget? child;

  @override
  State<BreathingRings> createState() => _BreathingRingsState();
}

class _BreathingRingsState extends State<BreathingRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _RingsPainter(progress: _c.value, color: widget.color),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    const rings = 3;
    for (var i = 0; i < rings; i++) {
      final t = (progress + i / rings) % 1.0;
      final radius = maxR * (0.35 + 0.65 * t);
      final opacity = (1 - t) * 0.22;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.progress != progress || old.color != color;
}

/// Bouncing three-dot loader for the splash screen.
class DotsLoader extends StatefulWidget {
  const DotsLoader({super.key, this.color = WiColors.primary});

  final Color color;

  @override
  State<DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<DotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Opacity(
              opacity: 0.25 +
                  0.75 *
                      (0.5 +
                          0.5 *
                              math.sin(
                                  (_c.value * 2 * math.pi) - i * 0.9)),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
