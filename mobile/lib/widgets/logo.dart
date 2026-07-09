import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// The Wi-Health brand mark: a gradient squircle carrying a soft breathing
/// wave with a pulse dot — air and rhythm in one shape.
class WiLogoMark extends StatelessWidget {
  const WiLogoMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: wiBrandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: WiColors.primary.withValues(alpha: 0.35),
            blurRadius: size * 0.32,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(painter: _LogoWavePainter()),
    );
  }
}

class _LogoWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.52;
    final start = size.width * 0.17;
    final end = size.width * 0.71;
    final amp = size.height * 0.14;

    final path = Path()..moveTo(start, midY);
    for (double x = start; x <= end; x += 1) {
      final t = (x - start) / (end - start) * 2 * math.pi;
      path.lineTo(x, midY - math.sin(t) * amp);
    }

    // Echo wave behind, translucent.
    final echo = Path()..moveTo(start, midY);
    for (double x = start; x <= end + size.width * 0.06; x += 1) {
      final t = (x - start) / (end - start) * 2 * math.pi;
      echo.lineTo(x, midY - math.sin(t - 0.9) * amp * 0.62);
    }
    canvas.drawPath(
      echo,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.055
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.085
        ..strokeCap = StrokeCap.round,
    );

    // Pulse dot at the wave's end.
    canvas.drawCircle(
      Offset(size.width * 0.80, midY - math.sin(2 * math.pi) * amp),
      size.width * 0.062,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_LogoWavePainter oldDelegate) => false;
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
