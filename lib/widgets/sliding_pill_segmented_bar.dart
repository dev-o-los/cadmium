import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'apple_pressable.dart';

/// An Apple Music-inspired unified sliding pill segmented bar:
/// - A single continuous grey pill container with stadium border radius.
/// - Contains all category tabs (All, Songs, Videos, Albums, Artists, Playlists).
/// - An animated white highlight pill that smoothly glides and resizes between tabs.
/// - High-contrast crisp jet-black text on the active tab and crisp light-grey text on inactive tabs.
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
  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _itemKeys;

  // Offsets and widths for each tab relative to the track
  late List<double> _tabOffsets;
  late List<double> _tabWidths;

  static const double _tabHorizontalPadding = 16.0;
  static const double _tabVerticalPadding = 7.0;
  static const double _pillHeight = 42.0;
  static const double _innerPadding = 3.5;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    _precomputeMetrics();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureExactMetrics();
      _scrollToActiveTab(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant SlidingPillSegmentedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) {
      _itemKeys = List.generate(widget.categories.length, (_) => GlobalKey());
      _precomputeMetrics();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureExactMetrics();
      });
    }

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

  /// Instant synchronous measurement using TextPainter for zero-delay frame 0 rendering.
  void _precomputeMetrics() {
    _tabOffsets = [];
    _tabWidths = [];
    double currentOffset = 0.0;

    for (final category in widget.categories) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: category,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final width = textPainter.width + (_tabHorizontalPadding * 2);
      _tabOffsets.add(currentOffset);
      _tabWidths.add(width);
      currentOffset += width;
    }
  }

  /// Post-frame precision measurement using rendered RenderBoxes.
  void _measureExactMetrics() {
    if (!mounted) return;
    final stackRenderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackRenderBox == null) return;

    final newOffsets = <double>[];
    final newWidths = <double>[];

    for (int i = 0; i < _itemKeys.length; i++) {
      final itemRenderBox = _itemKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (itemRenderBox == null) return;

      final localOffset = stackRenderBox.globalToLocal(
        itemRenderBox.localToGlobal(Offset.zero),
      );
      newOffsets.add(localOffset.dx);
      newWidths.add(itemRenderBox.size.width);
    }

    if (newOffsets.length == widget.categories.length && mounted) {
      setState(() {
        _tabOffsets = newOffsets;
        _tabWidths = newWidths;
      });
    }
  }

  void _scrollToActiveTab({bool animate = true}) {
    if (!mounted || !_scrollController.hasClients) return;

    final activeIndex = widget.categories.indexOf(widget.selectedCategory);
    if (activeIndex < 0 || activeIndex >= _tabOffsets.length) return;

    final targetOffset = _tabOffsets[activeIndex];
    final targetWidth = _tabWidths[activeIndex];
    final viewportWidth = _scrollController.position.viewportDimension;

    // Center the active tab in the viewport
    final desiredScroll = targetOffset + (targetWidth / 2) - (viewportWidth / 2) + 16.0;
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
    final activeIndex = widget.categories.indexOf(widget.selectedCategory);
    final validIndex = activeIndex >= 0 ? activeIndex : 0;

    final activeLeft = _tabOffsets.isNotEmpty ? _tabOffsets[validIndex] : 0.0;
    final activeWidth = _tabWidths.isNotEmpty ? _tabWidths[validIndex] : 60.0;

    return SizedBox(
      height: _pillHeight + 4.0,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: widget.padding,
        child: Center(
          child: Container(
            height: _pillHeight,
            padding: const EdgeInsets.all(_innerPadding),
            decoration: BoxDecoration(
              // Sleek Apple Dark Mode Grey track
              color: const Color(0xFF222224),
              borderRadius: BorderRadius.circular(_pillHeight / 2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.09),
                width: 0.75,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              key: _stackKey,
              children: [
                // 1. Sliding White Highlight Pill (animates smoothly between tabs)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  left: activeLeft,
                  width: activeWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular((_pillHeight - (_innerPadding * 2)) / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 1.5),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 2,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Tab Items Row with Crisp Text
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.categories.length; i++)
                      _buildTabItem(
                        index: i,
                        category: widget.categories[i],
                        isSelected: i == activeIndex,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, curve: Curves.easeOutCubic)
        .slideY(begin: -0.08, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildTabItem({
    required int index,
    required String category,
    required bool isSelected,
  }) {
    return ApplePressable(
      key: _itemKeys[index],
      onTap: () {
        if (widget.selectedCategory != category) {
          widget.onCategorySelected(category);
        }
      },
      borderRadius: BorderRadius.circular((_pillHeight - (_innerPadding * 2)) / 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: _tabHorizontalPadding,
          vertical: _tabVerticalPadding,
        ),
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            // Crisp jet-black text on white highlight; crisp light-grey on dark track
            color: isSelected ? Colors.black : const Color(0xFF9E9EA2),
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: -0.2,
          ),
          child: Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}
