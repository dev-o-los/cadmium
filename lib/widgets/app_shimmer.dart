import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Central Apple-style Shimmer wrapper for Aurum.
/// Defaults to Apple Dark surface colors with smooth metallic shimmer sweeping.
class AppShimmer extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;
  final ShimmerDirection direction;
  final bool? enabled;

  const AppShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 1500),
    this.direction = ShimmerDirection.ltr,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');

    return Shimmer.fromColors(
      baseColor: baseColor ?? const Color(0xFF1C1C1E),
      highlightColor: highlightColor ?? const Color(0xFF2C2C2E),
      period: period,
      direction: direction,
      enabled: enabled ?? !isTest,
      child: child,
    );
  }
}

/// A basic atomic placeholder element used inside [AppShimmer].
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  const ShimmerBox.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = null,
        shape = BoxShape.circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? (borderRadius ?? BorderRadius.circular(8))
            : null,
      ),
    );
  }
}

/// Proper Skeleton for the Home Feed Screen matching the live UI layout.
class HomeScreenSkeleton extends StatelessWidget {
  const HomeScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final heroCardWidth = (screenWidth * 0.58).clamp(215.0, 245.0);

    return AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, topPadding + 6, 0, 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Logo placeholder
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: ShimmerBox(
                width: 56,
                height: 56,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),

            // 1. Top Picks for You Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ShimmerBox(width: 140, height: 16),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 305,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 3,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => Container(
                  width: heroCardWidth,
                  height: 305,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Recents Section (4 vertical items column)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ShimmerBox(width: 90, height: 16),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: List.generate(
                  4,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        ShimmerBox(width: 48, height: 48),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerBox(width: 160, height: 14),
                              SizedBox(height: 6),
                              ShimmerBox(width: 100, height: 11),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        ShimmerBox(width: 16, height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 3. Albums & Singles Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ShimmerBox(width: 130, height: 16),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 195,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) => const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 145, height: 145),
                    SizedBox(height: 8),
                    ShimmerBox(width: 110, height: 13),
                    SizedBox(height: 4),
                    ShimmerBox(width: 70, height: 11),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Proper Skeleton for Search Results.
class SearchScreenSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const SearchScreenSkeleton({
    super.key,
    this.itemCount = 8,
    this.padding = const EdgeInsets.fromLTRB(7, 10, 7, 160),
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => Row(
          children: [
            ShimmerBox(
              width: 48,
              height: 48,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(
                    width: index % 2 == 0 ? 165 : 135,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  ShimmerBox(
                    width: index % 2 == 0 ? 110 : 85,
                    height: 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShimmerBox(
              width: 28,
              height: 11,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(width: 8),
            const ShimmerBox(
              width: 18,
              height: 18,
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer loader displayed at the bottom of the search results during infinite-scroll loading.
class SearchLoadingMoreShimmer extends StatelessWidget {
  final int itemCount;

  const SearchLoadingMoreShimmer({
    super.key,
    this.itemCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: List.generate(
          itemCount,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                ShimmerBox(
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(
                        width: index == 0 ? 150 : 175,
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      ShimmerBox(
                        width: index == 0 ? 100 : 80,
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ShimmerBox(
                  width: 28,
                  height: 11,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(width: 8),
                const ShimmerBox(
                  width: 18,
                  height: 18,
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Proper Skeleton for Album metadata and description while tracks load.
class AlbumMetadataSkeleton extends StatelessWidget {
  final bool showArtwork;
  final bool isLoadingArtwork;

  const AlbumMetadataSkeleton({
    super.key,
    this.showArtwork = false,
    this.isLoadingArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: [
          if (showArtwork) ...[
            ShimmerBox(
              width: 240,
              height: 240,
              borderRadius: BorderRadius.circular(18),
            ),
            const SizedBox(height: 18),
          ],
          const ShimmerBox(width: 190, height: 13),
          const SizedBox(height: 8),
          const ShimmerBox(width: 145, height: 12),
        ],
      ),
    );
  }
}

/// Proper Skeleton for Tracklists (Album Screen, Playlist, Library).
class TrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showIndex;
  final bool showArtwork;
  final EdgeInsetsGeometry padding;

  const TrackListSkeleton({
    super.key,
    this.itemCount = 8,
    this.showIndex = true,
    this.showArtwork = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: padding,
        child: Column(
          children: List.generate(
            itemCount,
            (index) {
              // Subtle deterministic width variation so skeleton rows feel organic
              final titleWidth = 148.0 + ((index * 23) % 52);
              final subtitleWidth = 88.0 + ((index * 17) % 38);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    if (showArtwork) ...[
                      const ShimmerBox(
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      const SizedBox(width: 12),
                    ] else if (showIndex) ...[
                      const SizedBox(
                        width: 24,
                        child: Center(child: ShimmerBox(width: 14, height: 12)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerBox(width: titleWidth, height: 14),
                          const SizedBox(height: 6),
                          ShimmerBox(width: subtitleWidth, height: 11),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const ShimmerBox(width: 34, height: 12),
                    const SizedBox(width: 12),
                    const ShimmerBox.circle(size: 18),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Proper Skeleton for Artist Screen.
class ArtistScreenSkeleton extends StatelessWidget {
  const ArtistScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spotlight card placeholder
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: ShimmerBox(
              width: double.infinity,
              height: 160,
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          const SizedBox(height: 24),

          // Top Songs Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: ShimmerBox(width: 110, height: 16),
          ),
          const SizedBox(height: 12),

          // Top Songs Rows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: List.generate(
                4,
                (index) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ShimmerBox(width: 48, height: 48),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(width: 160, height: 14),
                            SizedBox(height: 6),
                            ShimmerBox(width: 90, height: 12),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      ShimmerBox.circle(size: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

