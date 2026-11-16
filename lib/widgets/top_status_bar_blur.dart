import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Universal Apple-style status bar blur & fading dissolve effect.
/// Mounts directly at the top status bar edge (behind battery, clock, and Wi-Fi icons).
/// As content scrolls underneath, it dynamically animates progressive backdrop blur
/// and a delicate OLED black gradient dissolve so content fades smoothly away.
class TopStatusBarBlur extends StatefulWidget {
  final ScrollController? scrollController;
  final double? fixedProgress;
  final double extraHeight;
  final double maxSigma;
  final double triggerOffset;
  final double falloff;
  final Color tintColor;

  const TopStatusBarBlur({
    super.key,
    this.scrollController,
    this.fixedProgress,
    this.extraHeight = 4.0,
    this.maxSigma = 8.0,
    this.triggerOffset = 32.0,
    this.falloff = 2.0,
    this.tintColor = Colors.black,
  });

  @override
  State<TopStatusBarBlur> createState() => _TopStatusBarBlurState();
}

class _TopStatusBarBlurState extends State<TopStatusBarBlur> {
  double _lastProgress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    _updateProgress();
  }

  @override
  void didUpdateWidget(covariant TopStatusBarBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
      _updateProgress();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _updateProgress();
  }

  void _updateProgress() {
    if (widget.fixedProgress != null ||
        widget.scrollController == null ||
        !widget.scrollController!.hasClients) {
      return;
    }

    final offset = widget.scrollController!.offset;
    final rawProgress = (offset / widget.triggerOffset).clamp(0.0, 1.0);
    final eased = rawProgress <= 0.001
        ? 0.0
        : (rawProgress >= 0.999 ? 1.0 : Curves.easeOutCubic.transform(rawProgress));

    // Throttles rebuilds during scrolling once clamped (0 or 1) or when change is minor
    if ((eased - _lastProgress).abs() >= 0.02 ||
        (eased == 1.0 && _lastProgress != 1.0) ||
        (eased == 0.0 && _lastProgress != 0.0)) {
      if (mounted) {
        setState(() {
          _lastProgress = eased;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final topBlurHeight = topPadding + widget.extraHeight;

    if (widget.fixedProgress != null) {
      return _buildBlur(context, widget.fixedProgress!.clamp(0.0, 1.0), topBlurHeight);
    }

    if (widget.scrollController == null) {
      // Default to subtle ambient status bar dissolve
      return _buildBlur(context, 1.0, topBlurHeight);
    }

    if (_lastProgress <= 0.001) {
      return const SizedBox.shrink();
    }

    return _buildBlur(context, _lastProgress, topBlurHeight);
  }

  Widget _buildBlur(BuildContext context, double progress, double height) {
    final deepTint = Color.lerp(widget.tintColor, Colors.black, 0.55) ?? Colors.black;
    final softTint = Color.lerp(widget.tintColor, Colors.black, 0.30) ?? Colors.black;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Progressive blur along status bar without redundant Opacity saveLayer
              if (progress > 0.01)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: height * 0.14,
                  child: ProgressiveBlur(
                    maxSigma: widget.maxSigma * progress,
                    direction: ProgressiveBlurDirection.topToBottom,
                    falloff: widget.falloff,
                  ),
                ),
              // Smooth multi-stop gradient dissolve extending past the blur edge to
              // eliminate any visible horizontal cut-off line.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      deepTint.withValues(alpha: 0.78 * progress),
                      deepTint.withValues(alpha: 0.52 * progress),
                      softTint.withValues(alpha: 0.24 * progress),
                      softTint.withValues(alpha: 0.06 * progress),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.30, 0.58, 0.84, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
