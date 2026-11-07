import 'package:flutter/material.dart';

/// The signature liquid glass audio capsule brand logo for Aurum.
/// Features three ascending metallic liquid-glass frequency droplets with luminous chrome reflections.
class AurumLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final BoxFit fit;

  const AurumLogo({
    super.key,
    this.size = 28,
    this.color,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final width = size;
    final height = size;

    return Image.asset(
      'assets/images/app_logo_cropped.png',
      width: width,
      height: height,
      fit: fit,
      color: color,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/images/app_logo.png',
          width: width,
          height: height,
          fit: fit,
        );
      },
    );
  }
}

/// Backwards-compatible aliases for [AurumLogo].
typedef CadmiumLogo = AurumLogo;
typedef MelomaniacLogo = AurumLogo;
typedef WavifyLogo = AurumLogo;

/// Zen balancing stones line-art icon seen in the "Relax" mood card.
class ZenStonesIcon extends StatelessWidget {
  final double size;
  final Color color;

  const ZenStonesIcon({super.key, this.size = 64, this.color = Colors.white});

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

  const VortexRingsIcon({super.key, this.size = 64, this.color = Colors.white});

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
