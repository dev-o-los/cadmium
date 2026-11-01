import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/lyric_line.dart';
import 'apple_pressable.dart';

/// Apple Music-style Karaoke Lyrics View inspired by binimum/am-lyrics (Benjamin).
/// Features:
/// - Live active lyric correctly positioned in the prime upper-middle viewing area below album art
/// - Previously sung verses smoothly scroll upwards and dissolve beneath the top bar / album art
/// - Word-by-word / Syllable progressive gradient wipe synchronization for real-time karaoke
/// - Distance-based Gaussian blur (depth-of-field) and scale falloff for inactive lines
/// - Dynamic Apple duet alignment (right-aligned for opposing singer, left-aligned for lead)
/// - Background vocal italicization and subtle indentation
/// - Fluid auto-scrolling with user-drag pause detection
/// - ApplePressable haptic tap-to-seek interaction on any lyric line
/// - Multi-provider attribution footer (Apple Music via lrc.red / BiniLyrics / LRCLIB)
class AppleLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int activeLyricIndex;
  final int currentPositionMs;
  final bool isLoading;
  final String? lyricsSource;
  final String? lyricsSongwriters;
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
        alignment: 0.0, // Positions live lyric directly below the album art header
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
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _isUserScrolling = true;
      _userScrollDebounce?.cancel();
    } else if (notification is ScrollEndNotification) {
      _userScrollDebounce?.cancel();
      _userScrollDebounce = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _isUserScrolling = false);
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
    if (widget.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Connecting lyrics...',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (widget.lyrics.isEmpty) {
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
                child: const Icon(
                  CupertinoIcons.quote_bubble,
                  color: Color(0xFF8E8E93),
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No lyrics available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lyrics for this track haven\'t been published yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTapBackground,
      behavior: HitTestBehavior.opaque,
      child: Stack(
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
                  stops: [0.0, 0.02, 0.90, 1.0],
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
                    padding: const EdgeInsets.only(top: 14, bottom: 220),
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
      ),
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
          // Line is inactive: render all syllables in standard inactive style
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
          // Syllable has finished singing: solid bright white with subtle glow
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
          // Syllable hasn't started yet: secondary inactive tone
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
          // Currently singing this syllable: progressive gradient wipe!
          final progress = syllable.getProgress(currentMs);

          return ShaderMask(
            shaderCallback: (bounds) {
              final stopA = (progress - 0.05).clamp(0.0, 1.0);
              final stopB = (progress + 0.12).clamp(0.0, 1.0);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.white,
                  Colors.white,
                  Color(0x60FFFFFF),
                  Color(0x60FFFFFF),
                ],
                stops: [0.0, stopA, stopB, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn,
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
                    color: Colors.white.withValues(alpha: 0.60),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  /// Line-synced or plain text fallback rendering
  Widget _buildStaticOrLineSyncedText(LyricLine line, bool isActive, TextAlign textAlign) {
    final baseFontSize = line.isBackground ? 20.0 : (isActive ? 30.0 : 23.0);
    final fontStyle = line.isBackground ? FontStyle.italic : FontStyle.normal;

    return Text(
      line.text,
      textAlign: textAlign,
      style: TextStyle(
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.38),
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
    final source = widget.lyricsSource ?? 'Apple Music (via BiniLyrics)';
    final songwriters = widget.lyricsSongwriters;

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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Icon(CupertinoIcons.music_mic, color: Colors.white70, size: 16),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Icon(CupertinoIcons.sparkles, color: Colors.white70, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
