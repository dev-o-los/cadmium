import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Universal Apple-style status bar blur & fading dissolve effect.
/// Mounts directly at the top status bar edge (behind battery, clock, and Wi-Fi icons).
/// As content scrolls underneath, it dynamically animates progressive backdrop blur
/// and a delicate OLED black gradient dissolve so content fades smoothly away.
class TopStatusBarBlur extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final topBlurHeight = topPadding + extraHeight;

    if (fixedProgress != null) {
      return _buildBlur(context, fixedProgress!.clamp(0.0, 1.0), topBlurHeight);
    }

    if (scrollController == null) {
      // Default to subtle ambient status bar dissolve
      return _buildBlur(context, 1.0, topBlurHeight);
    }

    return AnimatedBuilder(
      animation: scrollController!,
      builder: (context, _) {
        final offset = scrollController!.hasClients
            ? scrollController!.offset
            : 0.0;
        final rawProgress = (offset / triggerOffset).clamp(0.0, 1.0);
        if (rawProgress <= 0.001) {
          return const SizedBox.shrink();
        }
        final easedProgress = Curves.easeOutCubic.transform(rawProgress);

        return _buildBlur(context, easedProgress, topBlurHeight);
      },
    );
  }

  Widget _buildBlur(BuildContext context, double progress, double height) {
    final deepTint = Color.lerp(tintColor, Colors.black, 0.55) ?? Colors.black;
    final softTint = Color.lerp(tintColor, Colors.black, 0.30) ?? Colors.black;

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
              // Progressive blur along status bar, padded slightly shorter than the
              // outer gradient veil so the blur terminates smoothly inside the scrim.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: height * 0.14,
                child: Opacity(
                  opacity: progress,
                  child: ProgressiveBlur(
                    maxSigma: maxSigma * progress,
                    direction: ProgressiveBlurDirection.topToBottom,
                    falloff: falloff,
                  ),
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
