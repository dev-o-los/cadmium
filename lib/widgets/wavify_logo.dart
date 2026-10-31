import 'package:flutter/material.dart';

/// The signature 3-wave sound logo seen in Wavify's top header
/// and on the top-right corner of each Mood card.
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
    return CustomPaint(
      size: Size(size, size * 0.75),
      painter: _WavifyLogoPainter(color: color),
    );
  }
}

class _WavifyLogoPainter extends CustomPainter {
  final Color color;

  const _WavifyLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.height * 0.18;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // 3 vertically stacked wave curves
    final yOffsets = [h * 0.20, h * 0.52, h * 0.84];
    final arcWidths = [w * 0.82, w * 0.94, w * 1.0];

    for (int i = 0; i < 3; i++) {
      final path = Path();
      final currentW = arcWidths[i];
      final startX = (w - currentW) / 2;
      final endX = startX + currentW;
      final y = yOffsets[i];

      path.moveTo(startX, y);
      path.quadraticBezierTo(
        w * 0.5,
        y - (h * 0.18),
        endX,
        y,
      );

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavifyLogoPainter oldDelegate) =>
      oldDelegate.color != color;
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

