import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Apple Music-styled precision scrubber slider.
/// Features:
/// - Sleek 5.5px rounded capsule track at rest with flush seamless finish (matching Apple Music screenshots)
/// - Fluid spring expansion to 10px track with smooth 8px white thumb when scrubbing
/// - Edge-to-edge alignment with timestamps (no 24dp Material padding)
/// - Pure OLED white active progress, translucent frosted inactive track
/// - Precision timestamps (elapsed and -remaining) aligned with track edges
class AppleMusicSlider extends StatefulWidget {
  final double value;
  final double max;
  final double min;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final String? elapsedText;
  final String? remainingText;
  final bool showTimestamps;
  final Color activeColor;
  final Color inactiveColor;

  const AppleMusicSlider({
    super.key,
    required this.value,
    required this.max,
    this.min = 0.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.elapsedText,
    this.remainingText,
    this.showTimestamps = true,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x3DFFFFFF),
  });

  @override
  State<AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<AppleMusicSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _trackHeightAnimation;
  late Animation<double> _thumbRadiusAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _trackHeightAnimation = Tween<double>(begin: 6.5, end: 11.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _thumbRadiusAnimation = Tween<double>(begin: 3.5, end: 8.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDragStart(double val) {
    setState(() => _isDragging = true);
    _animController.forward();
    widget.onChangeStart?.call(val);
  }

  void _handleDragEnd(double val) {
    setState(() => _isDragging = false);
    _animController.reverse();
    widget.onChangeEnd?.call(val);
  }

  @override
  Widget build(BuildContext context) {
    final double safeMax = widget.max > widget.min ? widget.max : widget.min + 1.0;
    final double safeValue = widget.value.clamp(widget.min, safeMax);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final double currentHeight = _trackHeightAnimation.value;
            final double currentThumbRadius = _thumbRadiusAnimation.value;

            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: currentHeight,
                trackShape: AppleSliderTrackShape(trackHeight: currentHeight),
                thumbShape: AppleSliderThumbShape(
                  thumbRadius: currentThumbRadius,
                  isDragging: _isDragging,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.activeColor,
                inactiveTrackColor: widget.inactiveColor,
                thumbColor: Colors.white,
              ),
              child: SizedBox(
                height: 36,
                child: Slider(
                  min: widget.min,
                  max: safeMax,
                  value: safeValue,
                  onChangeStart: _handleDragStart,
                  onChanged: widget.onChanged,
                  onChangeEnd: _handleDragEnd,
                ),
              ),
            );
          },
        ),
        if (widget.showTimestamps) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.elapsedText ?? '',
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  widget.remainingText ?? '',
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Custom zero-margin rounded capsule track matching Apple Music.
class AppleSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final double trackHeight;

  const AppleSliderTrackShape({
    this.trackHeight = 6.5,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final double radius = trackRect.height / 2;

    // Full Inactive Track (Right/Background)
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? const Color(0x38FFFFFF);
    final RRect inactiveRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(radius),
    );
    canvas.drawRRect(inactiveRRect, inactivePaint);

    // Active Track (Left/Progress)
    final double activeRight = math.max(trackRect.left, math.min(thumbCenter.dx, trackRect.right));
    if (activeRight > trackRect.left) {
      final Paint activePaint = Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.white;
      final Rect activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        activeRight,
        trackRect.bottom,
      );
      final RRect activeRRect = RRect.fromRectAndRadius(
        activeRect,
        Radius.circular(radius),
      );
      canvas.drawRRect(activeRRect, activePaint);
    }
  }
}

/// Custom expanding thumb matching Apple Music.
/// When resting, thumb is a subtle capsule (radius 3.5px) visible on the active progress bar.
/// When scrubbing, thumb expands into a smooth circle with soft shadow.
class AppleSliderThumbShape extends SliderComponentShape {
  final double thumbRadius;
  final bool isDragging;

  const AppleSliderThumbShape({
    this.thumbRadius = 3.5,
    this.isDragging = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (thumbRadius <= 0.5) return;

    final Canvas canvas = context.canvas;

    if (isDragging) {
      final Path shadowPath = Path()
        ..addOval(Rect.fromCircle(center: center.translate(0, 1.2), radius: thumbRadius));
      canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.45), 4.0, true);
    } else {
      final Path shadowPath = Path()
        ..addOval(Rect.fromCircle(center: center.translate(0, 0.6), radius: thumbRadius));
      canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.30), 2.0, true);
    }

    final Paint thumbPaint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, thumbRadius, thumbPaint);
  }
}

