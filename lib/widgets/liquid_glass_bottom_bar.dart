import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Floating Liquid Glass Bottom Navigation Dock inspired by Apple design
/// matching the exact layout in the reference images:
/// - Main Capsule: [Home] (with illuminated glass pill indicator), [Explore], [Library]
/// - Standalone Circular Button: [Search]
class LiquidGlassBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const LiquidGlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
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
            child: GlassContainer(
              useOwnLayer: true,
              height: 60,
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
                    icon: Icons.home_rounded,
                    label: 'Home',
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.grid_view_rounded,
                    label: 'Explore',
                  ),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.folder_copy_rounded,
                    label: 'Library',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Standalone Circular Liquid Glass Search Button
          GestureDetector(
            onTap: () => onTabSelected(3),
            behavior: HitTestBehavior.opaque,
            child: GlassContainer(
              useOwnLayer: true,
              width: 60,
              height: 60,
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
                child: Icon(
                  Icons.search_rounded,
                  color: currentIndex == 3 ? Colors.white : const Color(0xFF8E8E93),
                  size: 26,
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
    required IconData icon,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              Icon(
                icon,
                size: 22,
                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
              ),
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
          ),
        ),
      ),
    );
  }
}
