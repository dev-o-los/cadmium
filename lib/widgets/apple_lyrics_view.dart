import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/lyric_line.dart';
import '../services/lyric_clock.dart';
import '../services/lyrics_service.dart';
import 'apple_pressable.dart';

/// Clipper that smoothly reveals the active filled layer of a syllable.
/// Hardware-accelerated scissor clipping without any GPU shader passes.
class _FractionalWidthClipper extends CustomClipper<Rect> {
  final double fraction;

  const _FractionalWidthClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction.clamp(0.0, 1.0), size.height);
  }

  @override
  bool shouldReclip(covariant _FractionalWidthClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}

/// Apple Music-style Three Animated Glowing Dots for instrumental passages and intros.
/// Pulses rhythmically to the musical beat with sequential glowing sine-waves.
class AppleInstrumentalDots extends StatefulWidget {
  final bool isActive;
  final VoidCallback? onTap;

  const AppleInstrumentalDots({
    super.key,
    required this.isActive,
    this.onTap,
  });

  @override
  State<AppleInstrumentalDots> createState() => _AppleInstrumentalDotsState();
}

class _AppleInstrumentalDotsState extends State<AppleInstrumentalDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppleInstrumentalDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ApplePressable(
      onTap: widget.onTap,
      pressedScale: 0.95,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 4),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final double phase = (index * 0.22);
                final double t = widget.isActive
                    ? ((_controller.value - phase) % 1.0).clamp(0.0, 1.0)
                    : 0.0;
                final double pulse = widget.isActive
                    ? math.sin(t * math.pi).clamp(0.0, 1.0)
                    : 0.0;

                final double scale = 1.0 + (pulse * 0.38);
                final double opacity = widget.isActive
                    ? (0.32 + pulse * 0.68).clamp(0.0, 1.0)
                    : 0.28;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5.5),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 9.5,
                      height: 9.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: opacity),
                        boxShadow: widget.isActive && pulse > 0.25
                            ? [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: (pulse * 0.55).clamp(0.0, 1.0)),
                                  blurRadius: 9 * pulse,
                                  spreadRadius: 1 * pulse,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// Ultra-smooth Apple Music-style Karaoke Lyrics View.
///
/// Performance and Design highlights (referencing Benjamin's am-lyrics):
/// - Driven by high-frequency LyricClock steering on a Flutter 60Hz/120Hz Ticker
/// - Completely eliminates GPU ImageFiltered blurs (zero offscreen texture lag)
/// - Syllables progressive wipe uses hardware-accelerated ClipRect
/// - Three animated glowing dots (● ● ●) pulse sequentially during instrumental intro and breaks
/// - Pinned Apple-style glass segmented toggle [ lrc.red | YouTube ]
/// - Depth-of-field scale and opacity falloff
/// - Opposing duet singer dynamic alignment
/// - ApplePressable haptic tap-to-seek
class AppleLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int activeLyricIndex;
  final int currentPositionMs;
  final bool isPlaying;
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
    this.isPlaying = true,
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

class _AppleLyricsViewState extends State<AppleLyricsView>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _isUserScrolling = false;
  Timer? _userScrollDebounce;

  // High-frequency LyricClock & Ticker (Benjamin's am-lyrics)
  late final LyricClock _clock;
  late final ValueNotifier<int> _smoothPositionNotifier;
  int _discontinuity = 0;
  int _lastReportedMs = 0;
  int _activeLyricIndex = -1;

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  /// Ensures instrumental intros (>= 2500ms) start with an instrumental gap line.
  List<LyricLine> get _displayLyrics {
    if (widget.lyrics.isEmpty) return widget.lyrics;
    final first = widget.lyrics.first;
    if (first.text.isNotEmpty && first.startTimeMs != null && first.startTimeMs! >= 2500) {
      return [
        LyricLine(
          text: '',
          startTimeMs: 0,
          endTimeMs: first.startTimeMs,
        ),
        ...widget.lyrics,
      ];
    }
    return widget.lyrics;
  }

  @override
  void initState() {
    super.initState();
    _clock = LyricClock(widget.currentPositionMs.toDouble());
    _smoothPositionNotifier = ValueNotifier<int>(widget.currentPositionMs);
    _lastReportedMs = widget.currentPositionMs;
    _activeLyricIndex = _computeActiveIndex(widget.currentPositionMs);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeLyricIndex >= 0) {
        _scrollToActiveLine(immediate: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AppleLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _clock.restart();
      } else {
        final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
        _clock.hold(widget.currentPositionMs.toDouble(), nowMs);
        _smoothPositionNotifier.value = widget.currentPositionMs;
      }
    }

    // Detect announced seek or large player scrub
    final diff = (widget.currentPositionMs - _lastReportedMs).abs();
    if (diff > 1200) {
      _discontinuity++;
      _lastReportedMs = widget.currentPositionMs;
      _clock.restart();
      _smoothPositionNotifier.value = widget.currentPositionMs;
      final newIdx = _computeActiveIndex(widget.currentPositionMs);
      if (newIdx != _activeLyricIndex) {
        setState(() {
          _activeLyricIndex = newIdx;
        });
        if (!_isUserScrolling) {
          _scrollToActiveLine();
        }
      }
    } else {
      _lastReportedMs = widget.currentPositionMs;
      // Normal reading from audio player: steer clock
      final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      final displayed = _clock.frame(
        nowMs,
        widget.currentPositionMs.toDouble(),
        nowMs,
        _discontinuity,
      ).round();

      if (_smoothPositionNotifier.value != displayed) {
        _smoothPositionNotifier.value = displayed;
      }

      final newIdx = _computeActiveIndex(displayed);
      if (newIdx != _activeLyricIndex) {
        setState(() {
          _activeLyricIndex = newIdx;
        });
        if (!_isUserScrolling) {
          _scrollToActiveLine();
        }
      }
    }
  }

  int _computeActiveIndex(int currentMs) {
    final list = _displayLyrics;
    if (list.isEmpty) return -1;

    for (int i = 0; i < list.length; i++) {
      final line = list[i];
      final start = line.startTimeMs ?? 0;
      final end = line.endTimeMs ?? (start + 3500);
      if (currentMs >= start && currentMs <= end) {
        return i;
      }
    }

    for (int i = list.length - 1; i >= 0; i--) {
      final line = list[i];
      if (line.startTimeMs != null && currentMs >= line.startTimeMs!) {
        return i;
      }
    }
    return 0;
  }

  /// Centers the active line cleanly in the upper viewing viewport.
  void _scrollToActiveLine({bool immediate = false}) {
    if (!_scrollController.hasClients || _activeLyricIndex < 0) return;
    final displayLines = _displayLyrics;
    if (_activeLyricIndex >= displayLines.length) return;

    final key = _lineKeys[_activeLyricIndex];
    final targetContext = key?.currentContext;

    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.05,
        duration: immediate ? Duration.zero : const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      final targetOffset = _activeLyricIndex * 66.0;
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
    _smoothPositionNotifier.dispose();
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

    final displayLines = _displayLyrics;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _handleUserScroll(notification);
            return false;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 10, bottom: 220),
              itemCount: displayLines.length + 1,
              itemBuilder: (context, index) {
                if (index == displayLines.length) {
                  return _buildAttributionFooter();
                }
                return _buildLyricLineItem(displayLines, index);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricLineItem(List<LyricLine> displayLines, int index) {
    final line = displayLines[index];
    final isActive = index == _activeLyricIndex;

    // Instrumental Gap Line (Intro or Bridge): Render Apple Three Animated Dots
    if (line.text.isEmpty) {
      return Container(
        key: _getKeyForIndex(index),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppleInstrumentalDots(
          isActive: isActive && widget.isPlaying,
          onTap: () => widget.onSeekToLyric(line),
        ),
      );
    }

    // Depth-of-field distance calculation
    final lineDistance = _activeLyricIndex >= 0
        ? (index - _activeLyricIndex).abs()
        : 0;

    final double scale = isActive ? 1.0 : (lineDistance == 1 ? 0.95 : 0.92);
    final double opacity = isActive ? 1.0 : (lineDistance == 1 ? 0.65 : 0.32);

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
            child: line.isWordSynced && line.syllables.isNotEmpty
                ? (isActive
                    ? ValueListenableBuilder<int>(
                        valueListenable: _smoothPositionNotifier,
                        builder: (context, smoothMs, child) {
                          return _buildWordSyncedLine(
                            line,
                            true,
                            smoothMs,
                            wrapAlignment,
                          );
                        },
                      )
                    : _buildWordSyncedLine(
                        line,
                        false,
                        _smoothPositionNotifier.value,
                        wrapAlignment,
                      ))
                : _buildStaticOrLineSyncedText(line, isActive, textAlign),
          ),
        ),
      ),
    );
  }

  /// Word-by-word karaoke syllable rendering with zero-overhead hardware-accelerated clipping.
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

        // Active line: progressive hardware-clipped syllable reveal
        if (currentMs >= syllable.endTimeMs) {
          // Fully sung syllable: solid bright white with subtle glow
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
          // Not yet reached
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
          // In-flight syllable: zero-overhead hardware scissor clipping
          final progress = syllable.getProgress(currentMs);

          return Stack(
            children: [
              Text(
                syllable.text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: baseFontSize,
                  fontWeight: FontWeight.w600,
                  fontStyle: fontStyle,
                  letterSpacing: -0.5,
                  height: 1.3,
                ),
              ),
              ClipRect(
                clipper: _FractionalWidthClipper(progress),
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
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
