import 'package:flutter/material.dart';

/// The signature Apple-style musical frequency 'A' monogram logo for Aurum.
/// Features an acoustic harmonic arch forming the letter 'A' with a resonant wave bar.
class AurumLogo extends StatelessWidget {
  final double size;
  final Color color;

  const AurumLogo({
    super.key,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.90),
      painter: _AurumLogoPainter(color: color),
    );
  }
}

class _AurumLogoPainter extends CustomPainter {
  final Color color;

  const _AurumLogoPainter({required this.color});

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

    // Harmonic 'A' arch path with smooth musical curvature
    final path = Path();
    path.moveTo(w * 0.15, h * 0.88);
    path.cubicTo(
      w * 0.22, h * 0.50,
      w * 0.38, h * 0.10,
      w * 0.50, h * 0.10,
    );
    path.cubicTo(
      w * 0.62, h * 0.10,
      w * 0.78, h * 0.50,
      w * 0.85, h * 0.88,
    );

    canvas.drawPath(path, linePaint);

    // Resonant frequency pulse bar across the letter 'A'
    final pulsePaint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.95
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.28, h * 0.60),
      Offset(w * 0.72, h * 0.60),
      pulsePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AurumLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Backwards-compatible aliases for [AurumLogo].
typedef MelomaniacLogo = AurumLogo;

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
    return AurumLogo(size: size, color: color);
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

