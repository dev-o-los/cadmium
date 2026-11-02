import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// An Apple Music-inspired unified sliding pill segmented bar:
/// - A single continuous grey pill container with stadium border radius fixed on screen.
/// - Contains all category tabs (All, Songs, Videos, Albums, Artists, Playlists).
/// - An animated white highlight pill that smoothly glides and resizes between tabs.
/// - High-contrast crisp jet-black text on the active tab and crisp light-grey text on inactive tabs.
/// - Mathematical symmetry: identical horizontal padding on both left and right sides of the white pill.
/// - Automatic centering scroll behavior with iOS bouncing physics.
class SlidingPillSegmentedBar extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final EdgeInsetsGeometry padding;

  const SlidingPillSegmentedBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  State<SlidingPillSegmentedBar> createState() => _SlidingPillSegmentedBarState();
}

class _SlidingPillSegmentedBarState extends State<SlidingPillSegmentedBar> {
  final ScrollController _scrollController = ScrollController();

  // Metrics for each tab relative to the track
  List<double> _tabOffsets = [];
  List<double> _tabWidths = [];

  static const double _tabHorizontalPadding = 20.0;
  static const double _pillHeight = 40.0;
  static const double _innerPadding = 3.0;

  static const TextStyle _tabTextStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveTab(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant SlidingPillSegmentedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveTab(animate: true);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Synchronously computes the exact offsets and widths using the active context
  /// (ensuring true device font metrics and textScaler are matched with 100% precision).
  void _calculateMetrics(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final directionality = Directionality.of(context);

    final offsets = <double>[];
    final widths = <double>[];
    double currentOffset = 0.0;

    for (final category in widget.categories) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: category,
          style: _tabTextStyle,
        ),
        textDirection: directionality,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();

      // Ensure exact symmetric padding: text is centered in a container of width textWidth + 2 * padding
      final width = textPainter.width + (_tabHorizontalPadding * 2);
      offsets.add(currentOffset);
      widths.add(width);
      currentOffset += width;
    }

    _tabOffsets = offsets;
    _tabWidths = widths;
  }

  void _scrollToActiveTab({bool animate = true}) {
    if (!mounted || !_scrollController.hasClients) return;

    final activeIndex = widget.categories.indexOf(widget.selectedCategory);
    if (activeIndex < 0 || activeIndex >= _tabOffsets.length) return;

    final targetOffset = _tabOffsets[activeIndex];
    final targetWidth = _tabWidths[activeIndex];
    final viewportWidth = _scrollController.position.viewportDimension;

    // Center the active tab in the fixed pill viewport
    final targetCenter = targetOffset + (targetWidth / 2);
    final desiredScroll = targetCenter - (viewportWidth / 2);
    final clampedScroll = desiredScroll.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate) {
      _scrollController.animateTo(
        clampedScroll,
        duration: const Duration(milliseconds: 320),
        curve: Curves.fastOutSlowIn,
      );
    } else {
      _scrollController.jumpTo(clampedScroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    _calculateMetrics(context);

    final activeIndex = widget.categories.indexOf(widget.selectedCategory);
    final validIndex = activeIndex >= 0 ? activeIndex : 0;

    final activeLeft = _tabOffsets.isNotEmpty ? _tabOffsets[validIndex] : 0.0;
    final activeWidth = _tabWidths.isNotEmpty ? _tabWidths[validIndex] : 60.0;

    const innerHeight = _pillHeight - (_innerPadding * 2); // 34.0
    const innerRadius = innerHeight / 2; // 17.0 (exact stadium capsule)

    return Padding(
      padding: widget.padding,
      child: Container(
        height: _pillHeight,
        decoration: BoxDecoration(
          // Sleek, authentic Apple Dark Mode segmented track
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(_pillHeight / 2),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular((_pillHeight / 2) - 0.5),
          child: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
              final maxScroll = _scrollController.hasClients
                  ? _scrollController.position.maxScrollExtent
                  : 1.0;

              // Only show dissolve on the left when scrolled away from the left (offset > 0)
              final leftFadeProgress = (offset / 16.0).clamp(0.0, 1.0);
              final leftEdgeColor = Color.lerp(
                Colors.black,
                Colors.transparent,
                leftFadeProgress,
              )!;

              // Only show dissolve on the right when there is more content to the right
              final rightRemaining = maxScroll > 0 ? (maxScroll - offset) : 0.0;
              final rightFadeProgress = (rightRemaining / 16.0).clamp(0.0, 1.0);
              final rightEdgeColor = Color.lerp(
                Colors.black,
                Colors.transparent,
                rightFadeProgress,
              )!;

              return ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      leftEdgeColor,
                      Colors.black,
                      Colors.black,
                      rightEdgeColor,
                    ],
                    stops: const [0.0, 0.025, 0.975, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: child,
              );
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: _innerPadding,
                vertical: _innerPadding,
              ),
              child: Stack(
                children: [
                  // Smooth White Highlight Pill with Natural Physical Elevation
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    left: activeLeft,
                    width: activeWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(innerRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 1,
                            offset: const Offset(0, 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab Items Row with explicitly matching widths and true Center alignment
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < widget.categories.length; i++)
                        _buildTabItem(
                          index: i,
                          category: widget.categories[i],
                          isSelected: i == activeIndex,
                          tabWidth: _tabWidths.isNotEmpty ? _tabWidths[i] : 60.0,
                          tabHeight: innerHeight,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms, curve: Curves.easeOutCubic)
        .slideY(begin: -0.06, end: 0, duration: 200.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildTabItem({
    required int index,
    required String category,
    required bool isSelected,
    required double tabWidth,
    required double tabHeight,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.selectedCategory != category) {
          HapticFeedback.lightImpact();
          widget.onCategorySelected(category);
        }
      },
      child: SizedBox(
        width: tabWidth,
        height: tabHeight,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            style: TextStyle(
              // Crisp jet-black text on white highlight; crisp secondary-grey on dark track
              color: isSelected ? Colors.black : const Color(0xFF8E8E93),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            child: Text(
              category,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ),
    );
  }
}
