import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'animated_cupertino_icon.dart';

/// Standard Apple iOS Liquid Glass preset matching the bottom navigation dock.
const kLiquidBottomDockGlassSettings = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 0.75 * math.pi,
  glassColor: Color(0x3DFFFFFF),
);

/// Floating Liquid Glass Bottom Navigation Dock using official [GlassTabBar.minimizable]
/// matching the exact Apple layout from the liquid_glass_widgets package:
/// - Expanded state: Full 3 tabs (Home, Explore, Library) + circular Search button
///   with floating mini-player accessory resting above.
/// - Minimized state (when scrolling): 3-part inline dock:
///   1. Left: Collapsed glass circular button representing active tab
///   2. Center: Compact inline music player capsule
///   3. Right: Circular glass search button
class LiquidGlassBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool isCrawled;
  final VoidCallback? onExpand;
  final Widget? bottomAccessory;

  const LiquidGlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.isCrawled = false,
    this.onExpand,
    this.bottomAccessory,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIndex = currentIndex > 2 ? 0 : currentIndex;

    return GlassTabBar.minimizable(
      settings: kLiquidBottomDockGlassSettings,
      tabs: const [
        GlassTab(
          icon: Icon(CupertinoIcons.house_fill),
          activeIcon: Icon(CupertinoIcons.house_fill),
          label: 'Home',
        ),
        GlassTab(
          icon: Icon(CupertinoIcons.square_grid_2x2_fill),
          activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
          label: 'Explore',
        ),
        GlassTab(
          icon: Icon(CupertinoIcons.rectangle_stack_fill),
          activeIcon: Icon(CupertinoIcons.rectangle_stack_fill),
          label: 'Library',
        ),
      ],
      selectedIndex: effectiveIndex,
      onTabSelected: onTabSelected,
      minimized: isCrawled,
      onMinimizedTabTap: onExpand,
      showIndicator: currentIndex < 3,
      whitenAtBottom: false,
      trailingButton: GlassTabBarTrailingButton(
        icon: AnimatedCupertinoIcon(
          icon: CupertinoIcons.search,
          color: currentIndex == 3 ? Colors.white : const Color(0xB3FFFFFF),
          size: 24,
        ),
        onTap: () => onTabSelected(3),
      ),
      bottomAccessory: bottomAccessory,
      bottomAccessoryEnabled: bottomAccessory != null,
      bottomAccessoryHeight: 52.0,
      bottomAccessorySpacing: 5.0,
      barHeight: 58.0,
      minimizedBarHeight: 52.0,
      horizontalPadding: 14.0,
      verticalPadding: 8.0,
      spacing: 8.0,
      barBorderRadius: 29.0,
      selectedIconColor: Colors.white,
      unselectedIconColor: const Color(0xB3FFFFFF),
      selectedLabelColor: Colors.white,
      unselectedLabelColor: const Color(0xB3FFFFFF),
      selectedLabelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      unselectedLabelStyle: const TextStyle(
        color: Color(0xB3FFFFFF),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
      indicatorColor: Colors.white.withValues(alpha: 0.22),
    );
  }
}
