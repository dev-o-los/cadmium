import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated equalizer waveform bars resembling Apple Music's now-playing indicator.
class AnimatedEqualizerBars extends StatefulWidget {
  final Color color;
  final double size;
  final bool isPlaying;

  const AnimatedEqualizerBars({
    super.key,
    this.color = Colors.white,
    this.size = 18,
    this.isPlaying = true,
  });

  @override
  State<AnimatedEqualizerBars> createState() => _AnimatedEqualizerBarsState();
}

class _AnimatedEqualizerBarsState extends State<AnimatedEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = (widget.size / 5).clamp(2.0, 3.5);
    final maxHeight = widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;

        // 3 staggered sine wave heights
        final h1 = widget.isPlaying
            ? (0.35 + 0.55 * (0.5 + 0.5 * math.sin(t))).clamp(0.2, 1.0)
            : 0.3;
        final h2 = widget.isPlaying
            ? (0.25 + 0.70 * (0.5 + 0.5 * math.sin(t + 1.8))).clamp(0.2, 1.0)
            : 0.65;
        final h3 = widget.isPlaying
            ? (0.30 + 0.60 * (0.5 + 0.5 * math.sin(t + 3.6))).clamp(0.2, 1.0)
            : 0.4;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(barWidth, maxHeight * h1),
              SizedBox(width: barWidth * 0.7),
              _buildBar(barWidth, maxHeight * h2),
              SizedBox(width: barWidth * 0.7),
              _buildBar(barWidth, maxHeight * h3),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}

