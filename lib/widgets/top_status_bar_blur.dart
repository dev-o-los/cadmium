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

  const TopStatusBarBlur({
    super.key,
    this.scrollController,
    this.fixedProgress,
    this.extraHeight = 4.0,
    this.maxSigma = 8.0,
    this.triggerOffset = 32.0,
    this.falloff = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final topBlurHeight = topPadding + extraHeight;

    if (fixedProgress != null) {
      return _buildBlur(context, fixedProgress!, topBlurHeight);
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
        final progress = (offset / triggerOffset).clamp(0.0, 1.0);
        if (progress <= 0.001) {
          return const SizedBox.shrink();
        }

        return _buildBlur(context, progress, topBlurHeight);
      },
    );
  }

  Widget _buildBlur(BuildContext context, double progress, double height) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Progressive blur along status bar
            ProgressiveBlur(
              maxSigma: maxSigma * progress,
              direction: ProgressiveBlurDirection.topToBottom,
              falloff: falloff,
            ),
            // Soft darkening gradient dissolve
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85 * progress),
                    Colors.black.withValues(alpha: 0.35 * progress),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
