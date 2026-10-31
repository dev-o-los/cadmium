import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'animated_cupertino_icon.dart';

/// Floating Liquid Glass Bottom Navigation Dock inspired by Apple design
/// matching the exact layout in the reference images:
/// - Main Capsule: [Home] (with illuminated glass pill indicator), [Explore], [Library]
/// - Standalone Circular Button: [Search]
/// - Animated Cupertino Icons with fluid spring feedback
class LiquidGlassBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool isCrawled;

  const LiquidGlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.isCrawled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main Liquid Glass Navigation Dock (Home, Explore, Library)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: isCrawled ? 52 : 60,
              child: GlassContainer(
                useOwnLayer: true,
                shape: const LiquidRoundedSuperellipse(borderRadius: 32),
                color: const Color(0x331E1E22),
                settings: const LiquidGlassSettings(
                  thickness: 24,
                  blur: 24,
                  refractiveIndex: 1.15,
                  lightIntensity: 0.45,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(
                      index: 0,
                      selectedIcon: CupertinoIcons.house_fill,
                      unselectedIcon: CupertinoIcons.house,
                      label: 'Home',
                    ),
                    _buildNavItem(
                      index: 1,
                      selectedIcon: CupertinoIcons.compass_fill,
                      unselectedIcon: CupertinoIcons.compass,
                      label: 'Explore',
                    ),
                    _buildNavItem(
                      index: 2,
                      selectedIcon: CupertinoIcons.square_stack_3d_up_fill,
                      unselectedIcon: CupertinoIcons.square_stack_3d_up,
                      label: 'Library',
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Standalone Circular Liquid Glass Search Button
          GestureDetector(
            onTap: () => onTabSelected(3),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: isCrawled ? 52 : 60,
              height: isCrawled ? 52 : 60,
              child: GlassContainer(
                useOwnLayer: true,
                shape: const LiquidOval(),
                color: currentIndex == 3
                    ? const Color(0x55FFFFFF)
                    : const Color(0x331E1E22),
                settings: const LiquidGlassSettings(
                  thickness: 24,
                  blur: 24,
                  refractiveIndex: 1.15,
                  lightIntensity: 0.5,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
                child: Center(
                  child: AnimatedCupertinoIcon(
                    icon: CupertinoIcons.search,
                    color: currentIndex == 3 ? Colors.white : const Color(0xFF8E8E93),
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData selectedIcon,
    required IconData unselectedIcon,
    required String label,
  }) {
    final isSelected = currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabSelected(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: isCrawled ? 2 : 4),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: isSelected
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                    width: 0.7,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCupertinoIcon(
                icon: isSelected ? selectedIcon : unselectedIcon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
              ),
              if (!isCrawled) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8E8E93),
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
