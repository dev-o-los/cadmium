import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'animated_cupertino_icon.dart';

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
      settings: const LiquidGlassSettings(
        glassColor: Color(0x66121212),
        thickness: 24,
        blur: 16,
        refractiveIndex: 1.25,
        lightIntensity: 0.70,
        specularSharpness: GlassSpecularSharpness.sharp,
        fresnelStrength: 1.25,
        rimLight: 0.40,
        ambientStrength: 0.10,
        chromaticAberration: 0.012,
      ),
      indicatorSettings: const LiquidGlassSettings(
        glassColor: Color(0x24FFFFFF),
        thickness: 20,
        blur: 14,
        refractiveIndex: 1.20,
        lightIntensity: 0.70,
        specularSharpness: GlassSpecularSharpness.sharp,
      ),
      trailingButton: GlassTabBarTrailingButton(
        icon: AnimatedCupertinoIcon(
          icon: CupertinoIcons.search,
          color: currentIndex == 3 ? Colors.white : const Color(0xA6FFFFFF),
          size: 28,
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
      iconSize: 28.0,
      iconLabelSpacing: 1.0,
      indicatorPinchStrength: 0.4,
      selectedIconColor: Colors.white,
      unselectedIconColor: const Color(0xA6FFFFFF),
      selectedLabelColor: Colors.white,
      unselectedLabelColor: const Color(0xA6FFFFFF),
      selectedLabelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      unselectedLabelStyle: const TextStyle(
        color: Color(0xA6FFFFFF),
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      indicatorColor: const Color(0x24FFFFFF),
    );
  }
}
