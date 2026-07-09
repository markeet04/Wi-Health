import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Smooth animated breathing waveform — the live monitor's centerpiece.
/// When [active] is false (low signal / no breathing) the wave flattens
/// and grays out.
class BreathingWave extends StatefulWidget {
  const BreathingWave({
    super.key,
    required this.bpm,
    this.active = true,
    this.height = 110,
    this.color = WiColors.primary,
  });

  final int bpm;
  final bool active;
  final double height;
  final Color color;

  @override
  State<BreathingWave> createState() => _BreathingWaveState();
}

class _BreathingWaveState extends State<BreathingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
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
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _WavePainter(
            phase: _c.value * 2 * math.pi,
            color: widget.active ? widget.color : WiColors.inkFaint,
            amplitude: widget.active ? 1.0 : 0.08,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.phase,
    required this.color,
    required this.amplitude,
  });

  final double phase;
  final Color color;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final path = Path()..moveTo(0, midY);

    // Breathing-like waveform: primary sinusoid with a soft harmonic,
    // gently modulated so it looks organic rather than mathematical.
    for (double x = 0; x <= size.width; x += 2) {
      final t = x / size.width * 4 * math.pi;
      final y = midY -
          amplitude *
              (math.sin(t - phase) * 0.72 + math.sin(2 * t - phase * 1.5) * 0.18) *
              (size.height * 0.34) *
              (0.85 + 0.15 * math.sin(t / 3 + phase / 2));
      path.lineTo(x, y);
    }

    // Gradient fill under the curve.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase || old.color != color || old.amplitude != amplitude;
}

/// Static mini waveform snapshot (alert detail, patient cards).
class WaveSnapshot extends StatelessWidget {
  const WaveSnapshot({
    super.key,
    this.height = 70,
    this.color = WiColors.primary,
    this.flatSegment = false,
  });

  final double height;
  final Color color;

  /// Draws a flat "apnea pause" in the middle of the wave.
  final bool flatSegment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SnapshotPainter(color: color, flatSegment: flatSegment),
      ),
    );
  }
}

class _SnapshotPainter extends CustomPainter {
  _SnapshotPainter({required this.color, required this.flatSegment});

  final Color color;
  final bool flatSegment;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final path = Path()..moveTo(0, midY);
    for (double x = 0; x <= size.width; x += 2) {
      final frac = x / size.width;
      double amp = 1.0;
      if (flatSegment && frac > 0.38 && frac < 0.66) amp = 0.05;
      final t = frac * 6 * math.pi;
      final y = midY - amp * math.sin(t) * (size.height * 0.32);
      path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SnapshotPainter old) =>
      old.color != color || old.flatSegment != flatSegment;
}
