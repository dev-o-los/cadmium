import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/lyric_line.dart';
import '../services/lyric_clock.dart';
import '../services/lyrics_service.dart';
import 'apple_pressable.dart';

/// Hardware-accelerated scissor clipper for progressive syllable wipes.
/// Replaces expensive GPU ShaderMask passes with zero-overhead canvas clipping.
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

/// Apple Music Instrumental Three Dots component (binimum/am-lyrics).
///
/// Unlike a continuous looping spinner, the three dots act as a progressive
/// instrumental countdown to the upcoming lyric:
/// - Dot 1 fills and glows across the first third of the instrumental.
/// - Dot 2 fills and glows across the second third.
/// - Dot 3 fills and glows across the final third.
/// - When the instrumental stops, the dots collapse and singing begins.
class AppleInstrumentalDots extends StatelessWidget {
  final int gapStartMs;
  final int gapEndMs;
  final ValueListenable<int> currentPositionListenable;
  final VoidCallback? onTap;

  const AppleInstrumentalDots({
    super.key,
    required this.gapStartMs,
    required this.gapEndMs,
    required this.currentPositionListenable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gapDuration = math.max(1, gapEndMs - gapStartMs);
    final dotDuration = gapDuration / 3.0;

    return ApplePressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 4),
        child: ValueListenableBuilder<int>(
          valueListenable: currentPositionListenable,
          builder: (context, currentMs, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final dotStart = gapStartMs + (index * dotDuration);
                final dotEnd = dotStart + dotDuration;

                // Progress of this individual dot: 0.0 (unfilled) to 1.0 (fully filled)
                double progress = 0.0;
                if (currentMs >= dotEnd) {
                  progress = 1.0;
                } else if (currentMs <= dotStart) {
                  progress = 0.0;
                } else {
                  progress = ((currentMs - dotStart) / dotDuration).clamp(0.0, 1.0);
                }

                // Smooth gradual illumination matching binimum/am-lyrics
                final double opacity = 0.25 + (progress * 0.75); // 0.25 -> 1.0
                final double scale = 1.0 + (progress * 0.28);    // 1.0 -> 1.28
                final bool isGlowing = progress > 0.35;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 9.5,
                      height: 9.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: opacity),
                        boxShadow: isGlowing
                            ? [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: (progress * 0.55).clamp(0.0, 1.0)),
                                  blurRadius: 8.0 * progress,
                                  spreadRadius: 1.0 * progress,
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

/// Apple Music Lyrics View matching binimum/am-lyrics specifications:
/// - Fixed font size across active/inactive states (ZERO layout shifts or word reflow)
/// - Pure scale (0.98 -> 1.0) and opacity (0.45 -> 1.0) transforms with easeOutCubic
/// - High-frequency LyricClock frame interpolation (runs 60Hz/120Hz smoothly)
/// - Syllable progressive reveal with hardware scissor clipping
/// - Instrumental 3-dot countdown that fills gradually during intros & gaps
/// - Segmented glass provider switcher for lrc.red and YouTube
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
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _isUserScrolling = false;
  Timer? _userScrollDebounce;

  // High-frequency LyricClock & Frame Ticker (binimum/am-lyrics)
  late final LyricClock _clock;
  late final ValueNotifier<int> _smoothPositionNotifier;
  Ticker? _ticker;
  int _discontinuity = 0;
  int _lastReportedMs = 0;
  int _activeLyricIndex = -1;

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  /// Display lyrics matching withInstrumentalGaps structure.
  List<LyricLine> get _displayLyrics {
    if (widget.lyrics.isEmpty) return widget.lyrics;
    final first = widget.lyrics.first;
    if (first.text.isNotEmpty && first.startTimeMs != null && first.startTimeMs! >= 3000) {
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

  void _handleLyricTap(LyricLine line, int index) {
    _isUserScrolling = false;
    _userScrollDebounce?.cancel();

    final targetMs = line.startTimeMs ?? 0;
    _discontinuity++;
    _lastReportedMs = targetMs;
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    _clock.hold(targetMs.toDouble(), nowMs);
    _clock.restart();
    _smoothPositionNotifier.value = targetMs;

    setState(() {
      _activeLyricIndex = index;
    });

    _scrollToActiveLine();
    widget.onSeekToLyric(line);
  }

  @override
  void initState() {
    super.initState();
    _clock = LyricClock(widget.currentPositionMs.toDouble());
    _smoothPositionNotifier = ValueNotifier<int>(widget.currentPositionMs);
    _lastReportedMs = widget.currentPositionMs;
    _activeLyricIndex = widget.activeLyricIndex >= 0
        ? widget.activeLyricIndex
        : _computeActiveIndex(widget.currentPositionMs);

    // High-frequency 60Hz/120Hz frame ticker driven by LyricClock
    _ticker = createTicker((_) {
      if (!mounted) return;
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
    });

    if (widget.isPlaying && widget.lyrics.isNotEmpty) {
      _ticker?.start();
    }

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
      if (widget.isPlaying && widget.lyrics.isNotEmpty) {
        _clock.restart();
        if (_ticker != null && !_ticker!.isActive) {
          _ticker!.start();
        }
      } else {
        final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
        _clock.hold(widget.currentPositionMs.toDouble(), nowMs);
        _ticker?.stop();
        _smoothPositionNotifier.value = widget.currentPositionMs;
      }
    }

    final bool lyricsChanged = !listEquals(widget.lyrics, oldWidget.lyrics);
    final bool providerChanged = widget.selectedProvider != oldWidget.selectedProvider;

    if (lyricsChanged || providerChanged) {
      _lineKeys.clear();
      _discontinuity++;
      _lastReportedMs = widget.currentPositionMs;
      final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      _clock.hold(widget.currentPositionMs.toDouble(), nowMs);
      _clock.restart();
      _smoothPositionNotifier.value = widget.currentPositionMs;
      final newIdx = widget.activeLyricIndex >= 0
          ? widget.activeLyricIndex
          : _computeActiveIndex(widget.currentPositionMs);
      setState(() {
        _activeLyricIndex = newIdx;
      });
      _scrollToActiveLine(immediate: true);
      return;
    }

    // Detect announced seek, slider scrub, or activeLyricIndex jump
    final diff = (widget.currentPositionMs - _lastReportedMs).abs();
    final bool lyricIndexChanged = widget.activeLyricIndex != oldWidget.activeLyricIndex &&
        widget.activeLyricIndex != _activeLyricIndex;

    if (diff > 300 || lyricIndexChanged) {
      _discontinuity++;
      _lastReportedMs = widget.currentPositionMs;
      final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      _clock.hold(widget.currentPositionMs.toDouble(), nowMs);
      _clock.restart();
      _smoothPositionNotifier.value = widget.currentPositionMs;
      final newIdx = widget.activeLyricIndex >= 0
          ? widget.activeLyricIndex
          : _computeActiveIndex(widget.currentPositionMs);
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
    }
  }

  int _computeActiveIndex(int currentMs) {
    final list = _displayLyrics;
    if (list.isEmpty) return -1;

    // Guard: Before first timed line begins (e.g. intro)
    final firstStart = list.first.startTimeMs;
    if (firstStart != null && currentMs < firstStart) {
      return -1;
    }

    // 1. Direct active range check: line currently being sung / active
    for (int i = 0; i < list.length; i++) {
      final line = list[i];
      if (line.startTimeMs == null) continue;

      final start = line.startTimeMs!;
      final end = line.endTimeMs ?? (start + 3500);

      if (currentMs >= start && currentMs < end) {
        return i;
      }
    }

    // 2. Inter-line gap handling (between line i end and line i+1 start)
    for (int i = 0; i < list.length; i++) {
      final line = list[i];
      if (line.startTimeMs == null) continue;

      final nextStart = (i < list.length - 1) ? list[i + 1].startTimeMs : null;
      if (currentMs >= line.startTimeMs! && (nextStart == null || currentMs < nextStart)) {
        if (line.endTimeMs != null && (currentMs - line.endTimeMs!) > 2500) {
          if (nextStart != null && (nextStart - line.endTimeMs!) > 3500) {
            return -1; // In instrumental break
          }
        }
        return i;
      }
    }

    return -1;
  }

  /// Centers the active line cleanly at top 10% of viewport (am-lyrics layout).
  void _scrollToActiveLine({bool immediate = false}) {
    if (!_scrollController.hasClients || _activeLyricIndex < 0) return;
    final displayLines = _displayLyrics;
    if (_activeLyricIndex >= displayLines.length) return;

    final key = _lineKeys[_activeLyricIndex];
    final targetContext = key?.currentContext;

    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.10, // Positions live lyric in the top 10% breathing zone
        duration: immediate ? Duration.zero : const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      final targetOffset = _activeLyricIndex * 60.0;
      if (immediate) {
        _scrollController.jumpTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      } else {
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 400),
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
      _userScrollDebounce = Timer(const Duration(milliseconds: 3500), () {
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
    _ticker?.dispose();
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

    // Instrumental Gap Line (Intro or Bridge): Progressive Three Dots Countdown
    if (line.text.isEmpty) {
      return Container(
        key: _getKeyForIndex(index),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppleInstrumentalDots(
          gapStartMs: line.startTimeMs ?? 0,
          gapEndMs: line.endTimeMs ?? ((line.startTimeMs ?? 0) + 7000),
          currentPositionListenable: _smoothPositionNotifier,
          onTap: () => _handleLyricTap(line, index),
        ),
      );
    }

    // Fixed font size (32.0 lead / 21.0 background) prevents relayout and text shifting.
    // Subtle scale transform (0.98 -> 1.0) and opacity (0.45 -> 1.0) match binimum/am-lyrics.
    final lineDistance = _activeLyricIndex >= 0
        ? (index - _activeLyricIndex).abs()
        : 0;

    final double scale = isActive ? 1.0 : 0.98;
    final double opacity = isActive ? 1.0 : (lineDistance == 1 ? 0.65 : 0.45);

    // Alignment: opposing duet singer aligns right, lead singer aligns left
    final alignment = line.isOppositeTurn ? Alignment.centerRight : Alignment.centerLeft;
    final textAlign = line.isOppositeTurn ? TextAlign.right : TextAlign.left;
    final wrapAlignment = line.isOppositeTurn ? WrapAlignment.end : WrapAlignment.start;

    return ApplePressable(
      key: _getKeyForIndex(index),
      onTap: () => _handleLyricTap(line, index),
      pressedScale: 0.96,
      pressedOpacity: 0.85,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: line.isOppositeTurn ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 360),
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

  /// Word-by-word karaoke syllable rendering with fixed typography and hardware clipping.
  Widget _buildWordSyncedLine(
    LyricLine line,
    bool isActive,
    int currentMs,
    WrapAlignment wrapAlignment,
  ) {
    // Fixed font size: NEVER change font size on active state!
    final baseFontSize = line.isBackground ? 21.0 : 32.0;
    final fontStyle = line.isBackground ? FontStyle.italic : FontStyle.normal;

    return Wrap(
      alignment: wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: line.syllables.map((syllable) {
        if (!isActive) {
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: baseFontSize,
              fontWeight: FontWeight.w700,
              fontStyle: fontStyle,
              letterSpacing: -0.6,
              height: 1.25,
            ),
          );
        }

        // Active line: progressive hardware-clipped syllable reveal
        if (currentMs >= syllable.endTimeMs) {
          // Fully sung syllable: solid bright white with luminous Apple glow
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: baseFontSize,
              fontWeight: FontWeight.bold,
              fontStyle: fontStyle,
              letterSpacing: -0.6,
              height: 1.25,
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
          );
        } else if (currentMs < syllable.startTimeMs) {
          // Upcoming syllable: inactive tone
          return Text(
            syllable.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: baseFontSize,
              fontWeight: FontWeight.w700,
              fontStyle: fontStyle,
              letterSpacing: -0.6,
              height: 1.25,
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
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: baseFontSize,
                  fontWeight: FontWeight.w700,
                  fontStyle: fontStyle,
                  letterSpacing: -0.6,
                  height: 1.25,
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
                    letterSpacing: -0.6,
                    height: 1.25,
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
    // Fixed font size ensures stable layout across line activation
    final baseFontSize = line.isBackground ? 21.0 : 32.0;
    final fontStyle = line.isBackground ? FontStyle.italic : FontStyle.normal;

    return Text(
      line.text,
      textAlign: textAlign,
      style: TextStyle(
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.45),
        fontSize: baseFontSize,
        fontWeight: isActive ? FontWeight.bold : FontWeight.w700,
        fontStyle: fontStyle,
        letterSpacing: -0.6,
        height: 1.25,
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
