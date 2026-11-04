import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Apple Music-styled precision scrubber slider.
/// Features:
/// - Sleek 4.5px rounded capsule track at rest with flush seamless finish (matching Apple Music)
/// - Expands gently to 7px track when scrubbing
/// - Clean knob-free bar design: no rounded knob thumb, fills smoothly from left to right
/// - Pure OLED white active progress, frosted translucent inactive track
/// - Compact touch box to keep lyrics and controls properly aligned
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
    this.inactiveColor = const Color(0x33FFFFFF),
  });

  @override
  State<AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<AppleMusicSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _trackHeightAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );

    _trackHeightAnimation = Tween<double>(begin: 4.5, end: 7.5).animate(
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
    final double safeMax = widget.max > widget.min
        ? widget.max
        : widget.min + 1.0;
    final double safeValue = widget.value.clamp(widget.min, safeMax);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final double currentHeight = _trackHeightAnimation.value;

            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: currentHeight,
                trackShape: AppleSliderTrackShape(trackHeight: currentHeight),
                thumbShape: const AppleSliderThumbShape(
                  thumbRadius: 0.0,
                  isDragging: false,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.activeColor,
                inactiveTrackColor: widget.inactiveColor,
                thumbColor: Colors.transparent,
              ),
              child: SizedBox(
                height: 22,
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
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
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

  const AppleSliderTrackShape({this.trackHeight = 4.5});

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
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

    // Full Inactive Track (Right/Background capsule)
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? const Color(0x33FFFFFF);
    final RRect inactiveRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(radius),
    );
    canvas.drawRRect(inactiveRRect, inactivePaint);

    // Active Track (Left/Progress) - fills cleanly from left to right inside the capsule
    final double activeRight = math.max(
      trackRect.left,
      math.min(thumbCenter.dx, trackRect.right),
    );
    if (activeRight > trackRect.left) {
      final Paint activePaint = Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.white;

      canvas.save();
      canvas.clipRRect(inactiveRRect);
      canvas.drawRect(
        Rect.fromLTRB(
          trackRect.left,
          trackRect.top,
          activeRight,
          trackRect.bottom,
        ),
        activePaint,
      );
      canvas.restore();
    }
  }
}

/// Knob-free thumb component for Apple Music style slider.
class AppleSliderThumbShape extends SliderComponentShape {
  final double thumbRadius;
  final bool isDragging;

  const AppleSliderThumbShape({
    this.thumbRadius = 0.0,
    this.isDragging = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.zero;
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
    // Knob-free: no knob drawn so the track simply fills smoothly from left to right.
  }
}
