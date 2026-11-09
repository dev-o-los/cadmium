import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Refined Apple Music circular buffering ring loader.
/// Renders a fluid rotating sweep-gradient arc with rounded stroke caps,
/// completely replacing harsh spinners or blurry shadow blobs.
class SmoothPlayerLoader extends StatefulWidget {
  final double radius;
  final Color color;
  final double strokeWidth;

  const SmoothPlayerLoader({
    super.key,
    this.radius = 12,
    this.color = Colors.white,
    this.strokeWidth = 2.5,
  });

  @override
  State<SmoothPlayerLoader> createState() => _SmoothPlayerLoaderState();
}

class _SmoothPlayerLoaderState extends State<SmoothPlayerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _controller,
              child: CustomPaint(
                painter: _AppleRingPainter(
                  color: widget.color,
                  strokeWidth: widget.strokeWidth,
                ),
              ),
            ),
            // High-fidelity iOS activity indicator embedded cleanly
            CupertinoActivityIndicator(
              radius: widget.radius * 0.6,
              color: widget.color.withValues(alpha: 0.65),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _AppleRingPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track circle (very faint backdrop)
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Active sweep arc (270 degrees)
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.45),
          color,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.0,
      math.pi * 1.5,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AppleRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
