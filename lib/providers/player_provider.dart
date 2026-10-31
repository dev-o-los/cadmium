import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../models/lyric_line.dart';
import 'music_service_provider.dart';

/// Immutable model representing the active player playback state.
class PlayerStateModel {
  final SongItem? currentSong;
  final bool isPlaying;
  final bool isBuffering;
  final bool isResolvingStream;
  final Duration position;
  final Duration duration;
  final List<SongItem> queue;
  final List<SongItem> recentlyPlayed;
  final LoopMode loopMode;
  final bool isShuffle;
  final double volume;
  final String? errorMessage;
  final List<LyricLine> lyrics;
  final bool isLoadingLyrics;
  final int activeLyricIndex;

  const PlayerStateModel({
    this.currentSong,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isResolvingStream = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.recentlyPlayed = const [],
    this.loopMode = LoopMode.off,
    this.isShuffle = false,
    this.volume = 0.8,
    this.errorMessage,
    this.lyrics = const [],
    this.isLoadingLyrics = false,
    this.activeLyricIndex = -1,
  });

  PlayerStateModel copyWith({
    SongItem? currentSong,
    bool? isPlaying,
    bool? isBuffering,
    bool? isResolvingStream,
    Duration? position,
    Duration? duration,
    List<SongItem>? queue,
    List<SongItem>? recentlyPlayed,
    LoopMode? loopMode,
    bool? isShuffle,
    double? volume,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<LyricLine>? lyrics,
    bool? isLoadingLyrics,
    int? activeLyricIndex,
  }) {
    return PlayerStateModel(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isResolvingStream: isResolvingStream ?? this.isResolvingStream,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      loopMode: loopMode ?? this.loopMode,
      isShuffle: isShuffle ?? this.isShuffle,
      volume: volume ?? this.volume,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      lyrics: lyrics ?? this.lyrics,
      isLoadingLyrics: isLoadingLyrics ?? this.isLoadingLyrics,
      activeLyricIndex: activeLyricIndex ?? this.activeLyricIndex,
    );
  }
}

/// StateNotifier that manages the AudioPlayer, audio streaming, lyrics synchronization,
/// and queue handling using Riverpod for clean, reactive state management.
class PlayerNotifier extends StateNotifier<PlayerStateModel> {
  final Ref _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  PlayerNotifier(this._ref) : super(const PlayerStateModel()) {
    _initAudioListeners();
  }

  AudioPlayer get audioPlayer => _audioPlayer;

  void _initAudioListeners() {
    _playerStateSub = _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processing = playerState.processingState;
      final isBuffering = processing == ProcessingState.buffering ||
          processing == ProcessingState.loading;

      // Do not overwrite optimistic playing state while audio stream is still resolving
      if (state.isResolvingStream && state.isPlaying) {
        state = state.copyWith(isBuffering: isBuffering);
        return;
      }

      state = state.copyWith(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
      );
    });

    _positionSub = _audioPlayer.positionStream.listen((pos) {
      final newLyricIdx = _computeActiveLyricIndex(pos.inMilliseconds, state.lyrics);
      state = state.copyWith(
        position: pos,
        activeLyricIndex: newLyricIdx,
      );
    });

    _durationSub = _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _playbackEventSub = _audioPlayer.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Player playback event error: $e');
        state = state.copyWith(
          isResolvingStream: false,
          errorMessage: 'Unable to stream audio track.',
        );
      },
    );
  }

  int _computeActiveLyricIndex(int currentMs, List<LyricLine> lyrics) {
    if (lyrics.isEmpty) return -1;

    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].isActiveAt(currentMs)) {
        return i;
      }
    }

    if (lyrics.first.startTimeMs != null) {
      for (int i = lyrics.length - 1; i >= 0; i--) {
        if (lyrics[i].startTimeMs != null && currentMs >= lyrics[i].startTimeMs!) {
          return i;
        }
      }
    }

    return -1;
  }

  /// Selects and plays a song, automatically resolving its stream and fetching synced lyrics.
  Future<void> playSong(SongItem song, {List<SongItem>? contextQueue, bool forceReload = false}) async {
    if (state.currentSong?.id == song.id && !forceReload && _audioPlayer.audioSource != null) {
      togglePlayPause();
      return;
    }

    final updatedRecentlyPlayed = List<SongItem>.from(state.recentlyPlayed);
    if (!updatedRecentlyPlayed.any((s) => s.id == song.id)) {
      updatedRecentlyPlayed.insert(0, song);
      if (updatedRecentlyPlayed.length > 30) {
        updatedRecentlyPlayed.removeLast();
      }
    }

    List<SongItem> updatedQueue = state.queue;
    if (contextQueue != null && contextQueue.isNotEmpty) {
      updatedQueue = contextQueue.where((s) => s.id != song.id).toList();
    }

    state = state.copyWith(
      currentSong: song,
      isResolvingStream: true,
      isPlaying: true, // Optimistically show playing state to eliminate button lag
      clearErrorMessage: true,
      recentlyPlayed: updatedRecentlyPlayed,
      queue: updatedQueue,
      lyrics: const [],
      isLoadingLyrics: true,
      activeLyricIndex: -1,
      position: Duration.zero,
      duration: Duration(seconds: song.durationSeconds ?? 0),
    );

    // Fetch lyrics asynchronously in background
    _fetchLyrics(song.id);

    try {
      final musicService = _ref.read(musicServiceProvider);
      final streamInfo = await musicService.resolveAudioStream(song.id);

      // Guard: User might have paused or changed track while resolving stream
      if (state.currentSong?.id != song.id || !state.isPlaying) {
        state = state.copyWith(isResolvingStream: false);
        return;
      }

      final audioSource = AudioSource.uri(
        Uri.parse(streamInfo.url),
        headers: streamInfo.headers,
      );

      await _audioPlayer.setAudioSource(audioSource, preload: true);

      // Guard: User might have paused while setting audio source
      if (state.currentSong?.id != song.id || !state.isPlaying) {
        state = state.copyWith(isResolvingStream: false);
        return;
      }

      await _audioPlayer.play();

      state = state.copyWith(
        isResolvingStream: false,
        isPlaying: true,
      );
    } catch (e) {
      if (state.currentSong?.id == song.id) {
        state = state.copyWith(
          isResolvingStream: false,
          isPlaying: false,
          errorMessage: 'Unable to stream "${song.title}": Restricted or unavailable.',
        );
      }
    }
  }

  Future<void> _fetchLyrics(String songId) async {
    try {
      final musicService = _ref.read(musicServiceProvider);
      final fetched = await musicService.getLyrics(songId);
      state = state.copyWith(
        lyrics: fetched,
        isLoadingLyrics: false,
      );
    } catch (e) {
      state = state.copyWith(
        lyrics: const [],
        isLoadingLyrics: false,
      );
    }
  }

  void togglePlayPause() {
    // 1. If currently resolving stream, handle instant responsive toggle
    if (state.isResolvingStream) {
      if (state.isPlaying) {
        // User tapped pause while connecting: immediately cancel and update state
        _audioPlayer.stop();
        state = state.copyWith(
          isPlaying: false,
          isResolvingStream: false,
        );
      } else {
        // User tapped play while paused: resume resolving or play
        state = state.copyWith(isPlaying: true);
        if (state.currentSong != null) {
          playSong(state.currentSong!, forceReload: true);
        }
      }
      return;
    }

    // 2. If no audio source is currently loaded, but we have a selected song:
    if (_audioPlayer.audioSource == null && state.currentSong != null) {
      playSong(state.currentSong!, forceReload: true);
      return;
    }

    // 3. Normal playback state toggle: check both player.playing and state.isPlaying
    final isCurrentlyActive = _audioPlayer.playing || state.isPlaying;
    if (isCurrentlyActive) {
      _audioPlayer.pause();
      state = state.copyWith(isPlaying: false);
    } else {
      _audioPlayer.play();
      state = state.copyWith(isPlaying: true);
    }
  }

  void pause() {
    _audioPlayer.pause();
    state = state.copyWith(isPlaying: false);
  }

  void play() {
    _audioPlayer.play();
    state = state.copyWith(isPlaying: true);
  }

  void seek(Duration position) {
    _audioPlayer.seek(position);
  }

  void seekToLyric(LyricLine line) {
    if (line.startTimeMs != null) {
      seek(Duration(milliseconds: line.startTimeMs!));
    }
  }

  void skipNext() {
    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remainingQueue = state.queue.sublist(1);
      playSong(nextSong, contextQueue: remainingQueue);
    } else if (state.recentlyPlayed.length > 1) {
      final currentIdx = state.recentlyPlayed.indexWhere((s) => s.id == state.currentSong?.id);
      final nextIdx = (currentIdx + 1) % state.recentlyPlayed.length;
      playSong(state.recentlyPlayed[nextIdx]);
    }
  }

  void skipPrevious() {
    if (state.position.inSeconds > 4) {
      seek(Duration.zero);
      return;
    }

    if (state.recentlyPlayed.length > 1) {
      final currentIdx = state.recentlyPlayed.indexWhere((s) => s.id == state.currentSong?.id);
      final prevIdx = (currentIdx - 1 + state.recentlyPlayed.length) % state.recentlyPlayed.length;
      playSong(state.recentlyPlayed[prevIdx]);
    } else {
      seek(Duration.zero);
    }
  }

  void cycleLoopMode() {
    LoopMode nextMode;
    if (state.loopMode == LoopMode.off) {
      nextMode = LoopMode.all;
    } else if (state.loopMode == LoopMode.all) {
      nextMode = LoopMode.one;
    } else {
      nextMode = LoopMode.off;
    }
    _audioPlayer.setLoopMode(nextMode);
    state = state.copyWith(loopMode: nextMode);
  }

  void toggleShuffle() {
    final nextShuffle = !state.isShuffle;
    _audioPlayer.setShuffleModeEnabled(nextShuffle);
    state = state.copyWith(isShuffle: nextShuffle);
  }

  void setVolume(double val) {
    _audioPlayer.setVolume(val);
    state = state.copyWith(volume: val);
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < state.queue.length) {
      final updated = List<SongItem>.from(state.queue)..removeAt(index);
      state = state.copyWith(queue: updated);
    }
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playbackEventSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Global Riverpod provider for player state management.
final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerStateModel>((ref) {
  return PlayerNotifier(ref);
});

