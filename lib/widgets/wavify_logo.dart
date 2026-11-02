import 'package:flutter/material.dart';

/// The signature Apple-style musical frequency 'M' monogram logo for Melomaniac.
/// Features twin harmonic audio wave peaks forming the letter 'M' with resonance.
class MelomaniacLogo extends StatelessWidget {
  final double size;
  final Color color;

  const MelomaniacLogo({
    super.key,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.85),
      painter: _MelomaniacLogoPainter(color: color),
    );
  }
}

class _MelomaniacLogoPainter extends CustomPainter {
  final Color color;

  const _MelomaniacLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = w * 0.11;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Harmonic 'M' wave path with smooth musical curvature
    final path = Path();
    path.moveTo(w * 0.12, h * 0.88);
    path.cubicTo(
      w * 0.12, h * 0.40,
      w * 0.26, h * 0.10,
      w * 0.38, h * 0.10,
    );
    path.cubicTo(
      w * 0.46, h * 0.10,
      w * 0.47, h * 0.58,
      w * 0.50, h * 0.65,
    );
    path.cubicTo(
      w * 0.53, h * 0.58,
      w * 0.54, h * 0.10,
      w * 0.62, h * 0.10,
    );
    path.cubicTo(
      w * 0.74, h * 0.10,
      w * 0.88, h * 0.40,
      w * 0.88, h * 0.88,
    );

    canvas.drawPath(path, linePaint);

    // Subtle resonant frequency pulse bar at center bottom
    final pulsePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.9
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.50, h * 0.86),
      Offset(w * 0.50, h * 0.62),
      pulsePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MelomaniacLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Backwards-compatible alias for [MelomaniacLogo].
class WavifyLogo extends StatelessWidget {
  final double size;
  final Color color;

  const WavifyLogo({
    super.key,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return MelomaniacLogo(size: size, color: color);
  }
}

/// Zen balancing stones line-art icon seen in the "Relax" mood card.
class ZenStonesIcon extends StatelessWidget {
  final double size;
  final Color color;

  const ZenStonesIcon({
    super.key,
    this.size = 64,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ZenStonesPainter(color: color),
    );
  }
}

class _ZenStonesPainter extends CustomPainter {
  final Color color;

  const _ZenStonesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;

    // Top small stone
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.32),
        width: size.width * 0.42,
        height: size.height * 0.22,
      ),
      paint,
    );

    // Middle medium stone
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.54),
        width: size.width * 0.65,
        height: size.height * 0.26,
      ),
      paint,
    );

    // Bottom large stone
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.78),
        width: size.width * 0.88,
        height: size.height * 0.30,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ZenStonesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Vortex / spiral concentric rings icon for "Feeling Blue" mood card.
class VortexRingsIcon extends StatelessWidget {
  final double size;
  final Color color;

  const VortexRingsIcon({
    super.key,
    this.size = 64,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _VortexRingsPainter(color: color),
    );
  }
}

class _VortexRingsPainter extends CustomPainter {
  final Color color;

  const _VortexRingsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    for (int i = 0; i < 5; i++) {
      final factor = 1.0 - (i * 0.18);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + (i * 4)),
          width: size.width * 0.9 * factor,
          height: size.height * 0.36 * factor,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VortexRingsPainter oldDelegate) =>
      oldDelegate.color != color;
}

