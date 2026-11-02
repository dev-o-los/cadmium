import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/lyric_line.dart';
import '../services/lyrics_service.dart';
import 'apple_pressable.dart';

/// Apple Music-style Karaoke Lyrics View with lrc.red / YouTube provider switching.
/// Features:
/// - Fast segmented glass capsule toggle for lrc.red & YouTube lyrics
/// - Live active lyric correctly positioned below header
/// - Word-by-word / Syllable progressive gradient wipe synchronization
/// - Distance-based Gaussian blur and scale falloff for inactive lines
/// - Dynamic Apple duet alignment (right-aligned for opposing singer, left-aligned for lead)
/// - Background vocal italicization and subtle indentation
/// - Fluid auto-scrolling with user-drag pause detection
/// - ApplePressable haptic tap-to-seek interaction on any lyric line
/// - Multi-provider attribution footer with one-tap switcher
class AppleLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int activeLyricIndex;
  final int currentPositionMs;
  final bool isLoading;
  final String? lyricsSource;
  final String? lyricsSongwriters;
  final LyricsProviderType selectedProvider;
  final ValueChanged<LyricsProviderType>? onProviderChanged;
  final ValueChanged<LyricLine> onSeekToLyric;
  final VoidCallback? onTapBackground;

  const AppleLyricsView({
    super.key,
    required this.lyrics,
    required this.activeLyricIndex,
    required this.currentPositionMs,
    this.isLoading = false,
    this.lyricsSource,
    this.lyricsSongwriters,
    this.selectedProvider = LyricsProviderType.lrcRed,
    this.onProviderChanged,
    required this.onSeekToLyric,
    this.onTapBackground,
  });

  @override
  State<AppleLyricsView> createState() => _AppleLyricsViewState();
}

class _AppleLyricsViewState extends State<AppleLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _isUserScrolling = false;
  Timer? _userScrollDebounce;

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.activeLyricIndex >= 0) {
        _scrollToActiveLine(immediate: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AppleLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeLyricIndex != oldWidget.activeLyricIndex && !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToActiveLine();
        }
      });
    }
  }

  /// Centers the active line just below the album art header,
  /// smoothly shifting the previous verse upside as each verse finishes.
  void _scrollToActiveLine({bool immediate = false}) {
    if (!_scrollController.hasClients || widget.activeLyricIndex < 0) return;
    if (widget.activeLyricIndex >= widget.lyrics.length) return;

    final key = _lineKeys[widget.activeLyricIndex];
    final targetContext = key?.currentContext;

    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.0, // Positions live lyric directly below top header
        duration: immediate ? Duration.zero : const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      final targetOffset = widget.activeLyricIndex * 68.0;

      if (immediate) {
        _scrollController.jumpTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      } else {
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _handleUserScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _isUserScrolling = true;
      _userScrollDebounce?.cancel();
    } else if (notification is ScrollEndNotification) {
      _userScrollDebounce?.cancel();
      _userScrollDebounce = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
          });
          _scrollToActiveLine();
        }
      });
    }
  }

  @override
  void dispose() {
    _userScrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTapBackground,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          // Sleek Apple-style segmented glass capsule for provider selection
          _buildProviderSelector(),

          // Center Content: Loading, Empty State, or Synced Lyrics
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProviderSegment(
                type: LyricsProviderType.lrcRed,
                label: 'lrc.red',
                icon: CupertinoIcons.sparkles,
              ),
              const SizedBox(width: 2),
              _buildProviderSegment(
                type: LyricsProviderType.youTube,
                label: 'YouTube',
                icon: CupertinoIcons.play_rectangle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderSegment({
    required LyricsProviderType type,
    required String label,
    required IconData icon,
  }) {
    final isSelected = widget.selectedProvider == type;
    return ApplePressable(
      onTap: () {
        if (!isSelected) {
          widget.onProviderChanged?.call(type);
        }
      },
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            if (isSelected && widget.isLoading) ...[
              const SizedBox(width: 6),
              const CupertinoActivityIndicator(
                radius: 6,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading && widget.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 14, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'Connecting ${widget.selectedProvider.displayName} lyrics...',
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (widget.lyrics.isEmpty) {
      final otherProvider = widget.selectedProvider == LyricsProviderType.lrcRed
          ? LyricsProviderType.youTube
          : LyricsProviderType.lrcRed;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Icon(
                  widget.selectedProvider == LyricsProviderType.lrcRed
                      ? CupertinoIcons.music_mic
                      : CupertinoIcons.quote_bubble,
                  color: const Color(0xFF8E8E93),
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No lyrics available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.selectedProvider == LyricsProviderType.lrcRed
                    ? 'Synced syllables for this track are not yet available on lrc.red.'
                    : 'YouTube lyrics for this track haven\'t been published.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 20),
              ApplePressable(
                onTap: () => widget.onProviderChanged?.call(otherProvider),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        otherProvider == LyricsProviderType.lrcRed
                            ? CupertinoIcons.sparkles
                            : CupertinoIcons.play_rectangle,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Switch to ${otherProvider.displayName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, 0.03, 0.90, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _handleUserScroll(notification);
                return false;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 10, bottom: 220),
                  itemCount: widget.lyrics.length + 1,
                  itemBuilder: (context, index) {
                    if (index == widget.lyrics.length) {
                      return _buildAttributionFooter();
                    }
                    return _buildLyricLineItem(index);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricLineItem(int index) {
    final line = widget.lyrics[index];
    final isActive = index == widget.activeLyricIndex;
    final currentMs = widget.currentPositionMs;

    // Depth-of-field distance calculation
    final lineDistance = widget.activeLyricIndex >= 0
        ? (index - widget.activeLyricIndex).abs()
        : 0;

    final double blurSigma = isActive ? 0.0 : math.min(1.8, 0.4 + (lineDistance * 0.28));
    final double scale = isActive ? 1.0 : (lineDistance == 1 ? 0.96 : 0.93);
    final double opacity = isActive ? 1.0 : (lineDistance == 1 ? 0.65 : 0.35);

    // Alignment: opposing duet singer aligns right, lead singer aligns left
    final alignment = line.isOppositeTurn ? Alignment.centerRight : Alignment.centerLeft;
    final textAlign = line.isOppositeTurn ? TextAlign.right : TextAlign.left;
    final wrapAlignment = line.isOppositeTurn ? WrapAlignment.end : WrapAlignment.start;

    return ApplePressable(
      key: _getKeyForIndex(index),
      onTap: () => widget.onSeekToLyric(line),
      pressedScale: 0.96,
      pressedOpacity: 0.85,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        padding: EdgeInsets.symmetric(vertical: isActive ? 14 : 9),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: line.isOppositeTurn ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
                tileMode: TileMode.decal,
              ),
              child: line.isWordSynced && line.syllables.isNotEmpty
                  ? _buildWordSyncedLine(line, isActive, currentMs, wrapAlignment)
                  : _buildStaticOrLineSyncedText(line, isActive, textAlign),
            ),
          ),
        ),
      ),
    );
  }

  /// Word-by-word karaoke syllable rendering with progressive gradient wipe
  Widget _buildWordSyncedLine(
    LyricLine line,
    bool isActive,
    int currentMs,
    WrapAlignment wrapAlignment,
  ) {
    final baseFontSize = line.isBackground ? 21.0 : (isActive ? 30.0 : 24.0);
    final fontStyle = line.isBackground ? FontStyle.italic : FontStyle.normal;

    return Wrap(
      alignment: wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: line.syllables.map((syllable) {
        if (!isActive) {
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: baseFontSize,
              fontWeight: FontWeight.w600,
              fontStyle: fontStyle,
              letterSpacing: -0.5,
              height: 1.3,
            ),
          );
        }

        // Line is active: compute syllable wipe progress
        if (currentMs >= syllable.endTimeMs) {
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: baseFontSize,
              fontWeight: FontWeight.bold,
              fontStyle: fontStyle,
              letterSpacing: -0.5,
              height: 1.3,
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
          );
        } else if (currentMs < syllable.startTimeMs) {
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: baseFontSize,
              fontWeight: FontWeight.w600,
              fontStyle: fontStyle,
              letterSpacing: -0.5,
              height: 1.3,
            ),
          );
        } else {
          // In-flight syllable: progressive gradient wipe
          final progress = syllable.getProgress(currentMs);

          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: const [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  progress.clamp(0.0, 1.0),
                  (progress + 0.10).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: Text(
              syllable.text,
              style: TextStyle(
                color: Colors.white,
                fontSize: baseFontSize,
                fontWeight: FontWeight.bold,
                fontStyle: fontStyle,
                letterSpacing: -0.5,
                height: 1.3,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.30),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  Widget _buildStaticOrLineSyncedText(
    LyricLine line,
    bool isActive,
    TextAlign textAlign,
  ) {
    final baseFontSize = line.isBackground ? 21.0 : (isActive ? 30.0 : 24.0);
    final fontStyle = line.isBackground ? FontStyle.italic : FontStyle.normal;

    return Text(
      line.text,
      textAlign: textAlign,
      style: TextStyle(
        color: Colors.white,
        fontSize: baseFontSize,
        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
        fontStyle: fontStyle,
        letterSpacing: -0.5,
        height: 1.3,
        shadows: isActive
            ? [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.40),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildAttributionFooter() {
    final source = widget.lyricsSource ?? widget.selectedProvider.attributionName;
    final songwriters = widget.lyricsSongwriters;
    final otherProvider = widget.selectedProvider == LyricsProviderType.lrcRed
        ? LyricsProviderType.youTube
        : LyricsProviderType.lrcRed;

    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (songwriters != null && songwriters.trim().isNotEmpty) ...[
            Text(
              'Written by $songwriters',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lyrics provided by $source',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ApplePressable(
                onTap: () => widget.onProviderChanged?.call(otherProvider),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        otherProvider == LyricsProviderType.lrcRed
                            ? CupertinoIcons.sparkles
                            : CupertinoIcons.play_rectangle,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        otherProvider.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
