// ignore_for_file: experimental_member_use

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_device_item.dart';
import '../models/song_item.dart';
import '../models/lyric_line.dart';
import '../services/artwork_cache_service.dart';
import '../services/audio_cache_service.dart';
import '../services/player_history_cache_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../services/lyrics_service.dart';
import '../services/cadmium_audio_handler.dart';
import '../utils/notification_permission.dart';
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
  final List<SongItem> autoplayQueue;
  final List<SongItem> recentlyPlayed;
  final List<SongItem> history;
  final List<SongItem> originalQueue;
  final LoopMode loopMode;
  final bool isShuffle;
  final bool isAutoplay;
  final double volume;
  final String? errorMessage;
  final List<LyricLine> lyrics;
  final bool isLoadingLyrics;
  final int activeLyricIndex;
  final String? lyricsSource;
  final String? lyricsSongwriters;
  final bool hasWordSyncedLyrics;
  final LyricsProviderType selectedLyricsProvider;
  final String? animatedArtworkUrl;
  final Map<String, String>? animatedArtworkHeaders;
  final AudioDeviceItem connectedDevice;
  final String? selectedDeviceId;
  final List<AudioDeviceItem> availableAudioDevices;
  final Duration? sleepTimerDuration;
  final DateTime? sleepTimerEndTime;

  const PlayerStateModel({
    this.currentSong,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isResolvingStream = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.autoplayQueue = const [],
    this.recentlyPlayed = const [],
    this.history = const [],
    this.originalQueue = const [],
    this.loopMode = LoopMode.off,
    this.isShuffle = false,
    this.isAutoplay = true,
    this.volume = 0.8,
    this.errorMessage,
    this.lyrics = const [],
    this.isLoadingLyrics = false,
    this.activeLyricIndex = -1,
    this.lyricsSource,
    this.lyricsSongwriters,
    this.hasWordSyncedLyrics = false,
    this.selectedLyricsProvider = LyricsProviderType.lrcRed,
    this.animatedArtworkUrl,
    this.animatedArtworkHeaders,
    this.connectedDevice = const AudioDeviceItem(
      id: 'speaker',
      name: 'Phone Speaker',
      category: OutputDeviceCategory.speaker,
      isSelected: true,
    ),
    this.selectedDeviceId,
    this.availableAudioDevices = const [
      AudioDeviceItem(
        id: 'speaker',
        name: 'Phone Speaker',
        category: OutputDeviceCategory.speaker,
        isSelected: true,
      ),
    ],
    this.sleepTimerDuration,
    this.sleepTimerEndTime,
  });

  /// Whether the player is actively resolving stream or buffering before audio starts.
  bool get isLoading => isPlaying && (isResolvingStream || (isBuffering && position == Duration.zero));

  PlayerStateModel copyWith({
    SongItem? currentSong,
    bool? isPlaying,
    bool? isBuffering,
    bool? isResolvingStream,
    Duration? position,
    Duration? duration,
    List<SongItem>? queue,
    List<SongItem>? autoplayQueue,
    List<SongItem>? recentlyPlayed,
    List<SongItem>? history,
    List<SongItem>? originalQueue,
    LoopMode? loopMode,
    bool? isShuffle,
    bool? isAutoplay,
    double? volume,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<LyricLine>? lyrics,
    bool? isLoadingLyrics,
    int? activeLyricIndex,
    String? lyricsSource,
    bool clearLyricsSource = false,
    String? lyricsSongwriters,
    bool clearLyricsSongwriters = false,
    bool? hasWordSyncedLyrics,
    LyricsProviderType? selectedLyricsProvider,
    String? animatedArtworkUrl,
    Map<String, String>? animatedArtworkHeaders,
    bool clearAnimatedArtwork = false,
    AudioDeviceItem? connectedDevice,
    String? selectedDeviceId,
    List<AudioDeviceItem>? availableAudioDevices,
    Duration? sleepTimerDuration,
    DateTime? sleepTimerEndTime,
    bool clearSleepTimer = false,
  }) {
    return PlayerStateModel(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isResolvingStream: isResolvingStream ?? this.isResolvingStream,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      autoplayQueue: autoplayQueue ?? this.autoplayQueue,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      history: history ?? this.history,
      originalQueue: originalQueue ?? this.originalQueue,
      loopMode: loopMode ?? this.loopMode,
      isShuffle: isShuffle ?? this.isShuffle,
      isAutoplay: isAutoplay ?? this.isAutoplay,
      volume: volume ?? this.volume,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      lyrics: lyrics ?? this.lyrics,
      isLoadingLyrics: isLoadingLyrics ?? this.isLoadingLyrics,
      activeLyricIndex: activeLyricIndex ?? this.activeLyricIndex,
      lyricsSource: clearLyricsSource ? null : (lyricsSource ?? this.lyricsSource),
      lyricsSongwriters: clearLyricsSongwriters ? null : (lyricsSongwriters ?? this.lyricsSongwriters),
      hasWordSyncedLyrics: hasWordSyncedLyrics ?? this.hasWordSyncedLyrics,
      selectedLyricsProvider: selectedLyricsProvider ?? this.selectedLyricsProvider,
      animatedArtworkUrl: clearAnimatedArtwork ? null : (animatedArtworkUrl ?? this.animatedArtworkUrl),
      animatedArtworkHeaders: clearAnimatedArtwork ? null : (animatedArtworkHeaders ?? this.animatedArtworkHeaders),
      connectedDevice: connectedDevice ?? this.connectedDevice,
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      availableAudioDevices: availableAudioDevices ?? this.availableAudioDevices,
      sleepTimerDuration: clearSleepTimer ? null : (sleepTimerDuration ?? this.sleepTimerDuration),
      sleepTimerEndTime: clearSleepTimer ? null : (sleepTimerEndTime ?? this.sleepTimerEndTime),
    );
  }
}

/// StateNotifier that manages the AudioPlayer, audio streaming, lyrics synchronization,
/// and queue handling using Riverpod for clean, reactive state management.
class PlayerNotifier extends StateNotifier<PlayerStateModel> {
  final Ref _ref;
  final CadmiumAudioHandler _audioHandler;
  AudioPlayer get _audioPlayer => _audioHandler.player;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<Set<AudioDevice>>? _devicesSub;
  StreamSubscription<void>? _becomingNoisySub;
  AudioSession? _audioSession;
  int _currentStreamRequestId = 0;
  int _recoveryAttempts = 0;
  String? _lastRecoveredSongId;
  int _lyricsRequestId = 0;
  Duration? _pendingSeekPosition;
  int _seekGeneration = 0;
  // Throttle: only emit a Riverpod position update every 250 ms to avoid
  // rebuilding the entire widget tree 10 times per second.
  // Start at -1000 so the very first position event always passes through.
  int _lastPositionEmitMs = -1000;
  int _lastSavedPositionSec = -1;

  PlayerNotifier(this._ref)
      : _audioHandler = _ref.read(cadmiumAudioHandlerProvider),
        super(_buildInitialState()) {
    _audioHandler.onSkipNext = () => skipNext();
    _audioHandler.onSkipPrevious = () => skipPrevious();
    _audioHandler.onPlay = () => play();
    _audioHandler.onPause = () => pause();
    _audioHandler.onStop = () => stop();
    _audioHandler.onFastForward = () => fastForward();
    _audioHandler.onRewind = () => rewind();
    _audioHandler.onSeek = (pos) => seek(pos);
    _audioHandler.onSetRepeatMode = (mode) {
      if (mode == AudioServiceRepeatMode.none) {
        setLoopMode(LoopMode.off);
      } else if (mode == AudioServiceRepeatMode.one) {
        setLoopMode(LoopMode.one);
      } else {
        setLoopMode(LoopMode.all);
      }
    };
    _audioHandler.onSetShuffleMode = (mode) {
      setShuffle(mode != AudioServiceShuffleMode.none);
    };

    ArtworkCacheService.instance.onArtworkReady = (songId, localPath) {
      if (state.currentSong?.id == songId) {
        _audioHandler.updateArtworkPath(localPath);
      }
    };

    _initAudioListeners();
    _initAudioSession();
    _restorePersistedPlayback();
  }

  static PlayerStateModel _buildInitialState() {
    final cachedSong = PlayerHistoryCacheService.instance.lastPlayedSong;
    final cachedHistory = PlayerHistoryCacheService.instance.recentlyPlayed;
    final cachedQueue = PlayerHistoryCacheService.instance.lastQueue;
    final cachedPositionMs = PlayerHistoryCacheService.instance.lastPositionMs;

    final initialDuration = (cachedSong != null && cachedSong.durationSeconds != null && cachedSong.durationSeconds! > 0)
        ? Duration(seconds: cachedSong.durationSeconds!)
        : (cachedSong != null ? (SongMetricsCacheService.instance.getDuration(cachedSong.id) ?? Duration.zero) : Duration.zero);

    return PlayerStateModel(
      currentSong: cachedSong,
      duration: initialDuration,
      position: Duration(milliseconds: cachedPositionMs),
      recentlyPlayed: cachedHistory,
      queue: cachedQueue,
      isPlaying: false,
      isBuffering: false,
      isResolvingStream: false,
    );
  }

  Future<void> _restorePersistedPlayback() async {
    await PlayerHistoryCacheService.instance.init();
    if (!mounted) return;
    if (state.currentSong == null) {
      final cachedSong = PlayerHistoryCacheService.instance.lastPlayedSong;
      if (cachedSong != null) {
        final initialDuration = (cachedSong.durationSeconds != null && cachedSong.durationSeconds! > 0)
            ? Duration(seconds: cachedSong.durationSeconds!)
            : (SongMetricsCacheService.instance.getDuration(cachedSong.id) ?? Duration.zero);

        state = state.copyWith(
          currentSong: cachedSong,
          duration: initialDuration,
          position: Duration(milliseconds: PlayerHistoryCacheService.instance.lastPositionMs),
          recentlyPlayed: PlayerHistoryCacheService.instance.recentlyPlayed,
          queue: PlayerHistoryCacheService.instance.lastQueue,
          isPlaying: false,
          isBuffering: false,
          isResolvingStream: false,
        );

        final cachedArt = ArtworkCacheService.instance.getCachedRoundedArtworkFile(cachedSong.id) ??
            ArtworkCacheService.instance.getCachedArtworkFile(cachedSong.id);
        _audioHandler.updateCurrentSong(
          cachedSong,
          duration: initialDuration,
          localArtworkPath: cachedArt?.path,
        );

        unawaited(ArtworkCacheService.instance.getOrGenerateRoundedArtwork(cachedSong));
        unawaited(_resolveMasterArtwork(cachedSong));
      }
    }
  }

  AudioPlayer get audioPlayer => _audioPlayer;

  void _initAudioListeners() {
    _playerStateSub = _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processing = playerState.processingState;
      final isBuffering = processing == ProcessingState.buffering ||
          processing == ProcessingState.loading;

      if (processing == ProcessingState.completed) {
        // Guard against premature stream EOF (e.g. network blip or socket dropped mid-song)
        final currentPos = _audioPlayer.position;
        final totalDur = state.duration;
        final isNearEnd = totalDur > Duration.zero && currentPos >= totalDur - const Duration(seconds: 4);

        if (!isNearEnd && totalDur > const Duration(seconds: 15)) {
          // Playback cut off prematurely! Keep it playing by recovering stream:
          debugPrint('Premature stream EOF detected at $currentPos / $totalDur. Auto-recovering...');
          _recoverAndResumePlayback(currentPos);
          return;
        }

        if (state.loopMode == LoopMode.one) {
          seek(Duration.zero);
          play();
        } else {
          skipNext();
        }
        return;
      }

      // While actively resolving a stream, keep optimistic isPlaying state
      if (state.isResolvingStream) {
        state = state.copyWith(
          isBuffering: isBuffering,
        );
        return;
      }

      // When audio is ready, sync isPlaying directly to the player's true playing state
      if (processing == ProcessingState.ready) {
        state = state.copyWith(
          isPlaying: isPlaying,
          isBuffering: false,
          isResolvingStream: false,
        );
        return;
      }

      // When audio idles while we are NOT resolving a stream, the player stopped
      if (processing == ProcessingState.idle) {
        state = state.copyWith(
          isPlaying: false,
          isBuffering: false,
        );
        return;
      }

      state = state.copyWith(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
      );
    });

    _positionSub = _audioPlayer.positionStream.listen((pos) {
      // Guard against stale position packets arriving during asynchronous seek transitions
      if (_pendingSeekPosition != null) {
        return;
      }

      final newLyricIdx = LyricsService.computeActiveLyricIndex(pos.inMilliseconds, state.lyrics);
      final bool lyricChanged = newLyricIdx != state.activeLyricIndex;

      // Once playback position advances, audio is unequivocally playing out of speakers:
      // clear any residual loading or resolving states immediately!
      if (pos > Duration.zero && (state.isResolvingStream || state.isBuffering)) {
        state = state.copyWith(
          position: pos,
          activeLyricIndex: newLyricIdx,
          isResolvingStream: false,
          isBuffering: false,
          isPlaying: true,
        );
        _lastPositionEmitMs = pos.inMilliseconds;
        return;
      }

      // Throttle position-only Riverpod rebuilds to ≤4 Hz (250 ms).
      // Always allow through if the lyric index changed so the lyrics view
      // snaps to the new active line without perceptible delay.
      final int nowMs = pos.inMilliseconds;
      final bool throttleExpired = (nowMs - _lastPositionEmitMs).abs() >= 250;
      if (!lyricChanged && !throttleExpired) return;

      _lastPositionEmitMs = nowMs;
      state = state.copyWith(
        position: pos,
        activeLyricIndex: newLyricIdx,
      );

      // Persist playback position periodically (every 5 seconds)
      if ((pos.inSeconds - _lastSavedPositionSec).abs() >= 5) {
        _lastSavedPositionSec = pos.inSeconds;
        unawaited(PlayerHistoryCacheService.instance.savePosition(pos.inMilliseconds));
      }
    });

    _durationSub = _audioPlayer.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        state = state.copyWith(duration: dur);
        _audioHandler.updateDuration(dur);
        final songId = state.currentSong?.id;
        if (songId != null && songId.isNotEmpty) {
          unawaited(SongMetricsCacheService.instance.setDuration(songId, dur.inSeconds));
        }
      }
    });

    _playbackEventSub = _audioPlayer.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Player playback event error: $e');
        final currentPos = _audioPlayer.position;
        if (state.currentSong != null && currentPos > Duration.zero) {
          _recoverAndResumePlayback(currentPos);
        } else {
          state = state.copyWith(
            isResolvingStream: false,
            isPlaying: false,
            isBuffering: false,
            errorMessage: 'Unable to stream audio track.',
          );
        }
      },
    );
  }

  /// Auto-recovers an interrupted or prematurely severed audio stream and resumes
  /// playback seamlessly from [resumePosition].
  Future<void> _recoverAndResumePlayback(Duration resumePosition) async {
    final song = state.currentSong;
    if (song == null) return;

    if (_lastRecoveredSongId == song.id) {
      _recoveryAttempts++;
      if (_recoveryAttempts > 3) {
        debugPrint('Max recovery attempts reached for ${song.title}');
        state = state.copyWith(
          isPlaying: false,
          isBuffering: false,
          isResolvingStream: false,
          errorMessage: 'Playback error: Unable to keep stream alive.',
        );
        return;
      }
    } else {
      _lastRecoveredSongId = song.id;
      _recoveryAttempts = 1;
    }

    state = state.copyWith(isBuffering: true);

    try {
      final musicService = _ref.read(musicServiceProvider);
      musicService.invalidateStream(song.id);
      final streamInfo = await musicService.resolveAudioStream(song.id, forceRefresh: true);

      final audioSource = await AudioCacheService.instance.createAudioSource(
        song.id,
        streamInfo.url,
        streamInfo.headers,
      );

      await _audioPlayer.setAudioSource(
        audioSource,
        initialPosition: resumePosition,
        preload: true,
      );
      await _audioSession?.setActive(true);
      await _audioPlayer.play();

      state = state.copyWith(
        isPlaying: true,
        isBuffering: false,
        isResolvingStream: false,
        errorMessage: null,
      );
      _recoveryAttempts = 0;
    } catch (e) {
      debugPrint('Stream auto-recovery failed: $e');
      state = state.copyWith(
        isPlaying: false,
        isBuffering: false,
        isResolvingStream: false,
        errorMessage: 'Unable to stream "${song.title}".',
      );
    }
  }

  /// Optimistically primes the player UI with song metadata (e.g. from an album or single)
  /// so that the full player screen opens immediately while the audio stream resolves.
  void prepareSong(SongItem song) {
    final initialDuration = (song.durationSeconds != null && song.durationSeconds! > 0)
        ? Duration(seconds: song.durationSeconds!)
        : (SongMetricsCacheService.instance.getDuration(song.id) ?? Duration.zero);

    state = state.copyWith(
      currentSong: song,
      animatedArtworkUrl: song.animatedArtworkUrl,
      clearAnimatedArtwork: song.animatedArtworkUrl == null,
      isResolvingStream: true,
      isPlaying: true,
      clearErrorMessage: true,
      lyrics: const [],
      isLoadingLyrics: true,
      activeLyricIndex: -1,
      position: Duration.zero,
      duration: initialDuration,
      autoplayQueue: state.isAutoplay ? state.autoplayQueue : const [],
    );

    // Keep native just_audio loop mode synced:
    // Only LoopMode.one loops the single track natively;
    // LoopMode.all and LoopMode.off must allow ProcessingState.completed so queue advances!
    unawaited(_audioPlayer.setLoopMode(state.loopMode == LoopMode.one ? LoopMode.one : LoopMode.off));
    ArtworkCacheService.instance.recordSongPlay(song);
    _fetchLyrics(song);
    _fetchAnimatedArtwork(song);
    _resolveMasterArtwork(song);
    refreshAudioDevices();
  }

  /// Selects and plays a song, automatically resolving its stream and fetching synced lyrics.
  Future<void> playSong(
    SongItem song, {
    List<SongItem>? contextQueue,
    List<SongItem>? initialHistory,
    List<SongItem>? originalTracklist,
    bool forceReload = false,
  }) async {
    // If user clicked the song currently loaded and not resolving:
    // If paused, immediately start playing. If already playing, continue playing.
    if (state.currentSong?.id == song.id && !forceReload) {
      if (_audioPlayer.audioSource != null && !state.isResolvingStream) {
        if (!state.isPlaying) {
          play();
        }
        return;
      }
      if (state.isResolvingStream) {
        return; // Already resolving this song in background
      }
    }

    final requestId = ++_currentStreamRequestId;
    _lyricsRequestId++;
    _recoveryAttempts = 0;
    _lastRecoveredSongId = null;
    _pendingSeekPosition = null;
    _seekGeneration++;

    // Immediately stop previous audio playback
    try {
      _audioPlayer.stop();
    } catch (_) {}

    final updatedRecentlyPlayed = List<SongItem>.from(state.recentlyPlayed);
    if (!updatedRecentlyPlayed.any((s) => s.id == song.id)) {
      updatedRecentlyPlayed.insert(0, song);
      if (updatedRecentlyPlayed.length > 30) {
        updatedRecentlyPlayed.removeLast();
      }
    }

    List<SongItem> updatedQueue = state.queue;
    if (contextQueue != null) {
      updatedQueue = contextQueue.where((s) => s.id != song.id).toList();
    }

    List<SongItem> updatedHistory = state.history;
    if (initialHistory != null) {
      updatedHistory = List<SongItem>.from(initialHistory);
    }

    List<SongItem> updatedOriginalQueue = state.originalQueue;
    if (originalTracklist != null && originalTracklist.isNotEmpty) {
      updatedOriginalQueue = List<SongItem>.from(originalTracklist);
    } else if (contextQueue != null) {
      updatedOriginalQueue = [song, ...updatedQueue];
    }

    // If shuffle is enabled, shuffle the upcoming queue
    if (state.isShuffle && contextQueue != null && updatedQueue.isNotEmpty) {
      updatedQueue = List<SongItem>.from(updatedQueue)..shuffle();
    }

    final initialDuration = (song.durationSeconds != null && song.durationSeconds! > 0)
        ? Duration(seconds: song.durationSeconds!)
        : (SongMetricsCacheService.instance.getDuration(song.id) ?? Duration.zero);

    // Immediately show new song in player bar and enter play mode
    state = state.copyWith(
      currentSong: song,
      animatedArtworkUrl: song.animatedArtworkUrl,
      clearAnimatedArtwork: song.animatedArtworkUrl == null,
      isResolvingStream: true,
      isPlaying: true, // Optimistically show playing state to eliminate button lag
      isBuffering: true,
      clearErrorMessage: true,
      recentlyPlayed: updatedRecentlyPlayed,
      queue: updatedQueue,
      history: updatedHistory,
      originalQueue: updatedOriginalQueue,
      lyrics: const [],
      isLoadingLyrics: true,
      activeLyricIndex: -1,
      position: Duration.zero,
      duration: initialDuration,
      autoplayQueue: state.isAutoplay ? state.autoplayQueue : const [],
    );

    // Keep native just_audio loop mode synced:
    // Only LoopMode.one loops the single track natively;
    // LoopMode.all and LoopMode.off must allow ProcessingState.completed so queue advances!
    unawaited(_audioPlayer.setLoopMode(state.loopMode == LoopMode.one ? LoopMode.one : LoopMode.off));

    // Request notification permission on Android 13+ (OnePlus, Samsung, Pixel) if needed
    unawaited(requestNotificationPermissionIfNeeded());

    // Immediately broadcast to system media notification & lock screen with active buffering state
    final cachedArt = ArtworkCacheService.instance.getCachedRoundedArtworkFile(song.id) ??
        ArtworkCacheService.instance.getCachedArtworkFile(song.id);
    _audioHandler.updateCurrentSong(
      song,
      duration: initialDuration,
      localArtworkPath: cachedArt?.path,
      isBuffering: true,
    );

    // Warm up / generate hardware-antialiased rounded artwork for Android notifications
    unawaited(
      ArtworkCacheService.instance.getOrGenerateRoundedArtwork(song).then((file) {
        if (file != null && state.currentSong?.id == song.id) {
          _audioHandler.updateArtworkPath(file.path);
        }
      }),
    );

    // Fetch lyrics asynchronously in background
    _fetchLyrics(song);

    // Fetch animated looping artwork ("GIF video") asynchronously in background
    _fetchAnimatedArtwork(song);

    // Fetch YouTube Music AutoPlay recommendations asynchronously in background
    if (state.isAutoplay) {
      _fetchAutoplayQueue(song);
    }

    // Resolve studio-master album artwork asynchronously if needed
    _resolveMasterArtwork(song);

    // Refresh currently connected audio output device (Bluetooth, headphones, speaker)
    refreshAudioDevices();

    // Track play count and pre-cache high-res artwork for tracks heard repeatedly
    ArtworkCacheService.instance.recordSongPlay(song);

    // Persist as last played song, queue, and history so the player constantly remembers
    unawaited(PlayerHistoryCacheService.instance.saveLastPlayedSong(
      song,
      history: updatedRecentlyPlayed,
      queue: updatedQueue,
    ));

    try {
      AudioSource audioSource;
      final cachedAudio = AudioCacheService.instance.getCachedAudioFile(song.id);

      if (cachedAudio != null) {
        // Fast-path: local cached audio file (instant 0ms playback!)
        audioSource = AudioSource.file(cachedAudio.path, tag: song.id);
      } else {
        final musicService = _ref.read(musicServiceProvider);
        final streamInfo = await musicService.resolveAudioStream(song.id);

        // Guard: User might have skipped track while resolving stream
        if (requestId != _currentStreamRequestId || state.currentSong?.id != song.id) {
          if (requestId == _currentStreamRequestId) {
            state = state.copyWith(isResolvingStream: false, isBuffering: false);
          }
          return;
        }

        if (streamInfo.durationSeconds != null && streamInfo.durationSeconds! > 0) {
          if (state.duration == Duration.zero) {
            state = state.copyWith(
              duration: Duration(seconds: streamInfo.durationSeconds!),
            );
          }
        }

        audioSource = await AudioCacheService.instance.createAudioSource(
          song.id,
          streamInfo.url,
          streamInfo.headers,
        );
        if (!mounted) return;

        // If heard repeatedly, trigger background audio cache download
        if (ArtworkCacheService.instance.isHeardRepeatedly(song.id)) {
          AudioCacheService.instance.cacheAudioInBackground(
            song.id,
            streamInfo.url,
            streamInfo.headers,
            contentLength: streamInfo.contentLength,
          );
        }
      }

      await _audioPlayer.setAudioSource(audioSource, preload: true);
      if (!mounted) return;

      // Stream resolution is completed once audio source is loaded
      if (requestId == _currentStreamRequestId && state.currentSong?.id == song.id) {
        state = state.copyWith(isResolvingStream: false);
      }

      final playerDur = _audioPlayer.duration;
      if (playerDur != null && playerDur > Duration.zero) {
        state = state.copyWith(duration: playerDur);
        _audioHandler.updateDuration(playerDur);
        unawaited(SongMetricsCacheService.instance.setDuration(song.id, playerDur.inSeconds));
      }

      // Guard: User might have skipped track while setting audio source
      if (requestId != _currentStreamRequestId || state.currentSong?.id != song.id) {
        if (requestId == _currentStreamRequestId && mounted) {
          state = state.copyWith(isResolvingStream: false, isBuffering: false);
        }
        return;
      }

      await _audioSession?.setActive(true);
      await _audioPlayer.play();
      if (!mounted) return;

      if (requestId != _currentStreamRequestId) return;

      state = state.copyWith(
        isResolvingStream: false,
        isPlaying: _audioPlayer.playing,
        isBuffering: false,
      );
    } catch (e) {
      if (!mounted) return;
      if (requestId == _currentStreamRequestId && state.currentSong?.id == song.id) {
        state = state.copyWith(
          isResolvingStream: false,
          isPlaying: false,
          isBuffering: false,
          errorMessage: 'Unable to stream "${song.title}": Restricted or unavailable.',
        );
      }
    }
  }

  /// Changes the active lyrics provider (lrc.red or YouTube) and fetches the lyrics.
  void setLyricsProvider(LyricsProviderType provider) {
    if (state.selectedLyricsProvider == provider) return;
    _lyricsRequestId++;
    state = state.copyWith(
      selectedLyricsProvider: provider,
      isLoadingLyrics: true,
      lyrics: const [],
      activeLyricIndex: -1,
      clearLyricsSource: true,
      clearLyricsSongwriters: true,
      hasWordSyncedLyrics: false,
    );
    final song = state.currentSong;
    if (song != null) {
      _fetchLyrics(song, provider: provider);
    } else {
      state = state.copyWith(isLoadingLyrics: false);
    }
  }

  Future<void> _fetchLyrics(SongItem song, {LyricsProviderType? provider}) async {
    final targetProvider = provider ?? state.selectedLyricsProvider;
    final requestId = ++_lyricsRequestId;
    try {
      state = state.copyWith(isLoadingLyrics: true);
      final musicService = _ref.read(musicServiceProvider);
      final cachedDur = SongMetricsCacheService.instance.getDuration(song.id);
      final durSec = (song.durationSeconds != null && song.durationSeconds! > 0)
          ? song.durationSeconds
          : (cachedDur?.inSeconds);

      final result = await musicService.getLyricsWithMetadata(
        videoId: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        durationSeconds: durSec,
        provider: targetProvider,
      );
      if (!mounted) return;
      if (requestId == _lyricsRequestId &&
          state.currentSong?.id == song.id &&
          state.selectedLyricsProvider == targetProvider) {
        final linesWithGaps = LyricsService.withInstrumentalGaps(result.lines);
        final currentMs = state.position.inMilliseconds > 0
            ? state.position.inMilliseconds
            : _audioPlayer.position.inMilliseconds;
        final newActiveIdx = LyricsService.computeActiveLyricIndex(currentMs, linesWithGaps);
        state = state.copyWith(
          lyrics: linesWithGaps,
          activeLyricIndex: newActiveIdx,
          lyricsSource: result.source,
          lyricsSongwriters: result.songwriters,
          hasWordSyncedLyrics: result.hasWordSync,
          isLoadingLyrics: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (requestId == _lyricsRequestId &&
          state.currentSong?.id == song.id &&
          state.selectedLyricsProvider == targetProvider) {
        state = state.copyWith(
          lyrics: const [],
          activeLyricIndex: -1,
          clearLyricsSource: true,
          clearLyricsSongwriters: true,
          hasWordSyncedLyrics: false,
          isLoadingLyrics: false,
        );
      }
    }
  }

  Future<void> _fetchAnimatedArtwork(SongItem song) async {
    try {
      final musicService = _ref.read(musicServiceProvider);
      final artworkData = await musicService.getAnimatedArtworkData(song);
      if (!mounted) return;
      if (state.currentSong?.id == song.id && artworkData != null) {
        state = state.copyWith(
          animatedArtworkUrl: artworkData.url,
          animatedArtworkHeaders: artworkData.headers,
        );
      }
    } catch (_) {}
  }

  Future<void> _resolveMasterArtwork(SongItem song) async {
    // If the song already has a studio-master Google User Content URL, nothing needed
    if (song.thumbnailUrl != null &&
        (song.thumbnailUrl!.contains('googleusercontent.com') ||
         song.thumbnailUrl!.contains('ggpht.com'))) {
      return;
    }

    try {
      final musicService = _ref.read(musicServiceProvider);
      final masterArt = await musicService.getAlbumArtwork(
        song.album ?? '',
        title: song.title,
        artist: song.artist,
      );
      if (!mounted) return;
      if (masterArt != null && masterArt.isNotEmpty && state.currentSong?.id == song.id) {
        final updatedSong = song.copyWith(thumbnailUrl: masterArt);
        state = state.copyWith(currentSong: updatedSong);

        final cachedArt = ArtworkCacheService.instance.getCachedRoundedArtworkFile(song.id) ??
            ArtworkCacheService.instance.getCachedArtworkFile(song.id);
        _audioHandler.updateCurrentSong(
          updatedSong,
          duration: state.duration,
          localArtworkPath: cachedArt?.path,
        );

        unawaited(
          ArtworkCacheService.instance.getOrGenerateRoundedArtwork(updatedSong).then((file) {
            if (file != null && state.currentSong?.id == song.id) {
              _audioHandler.updateArtworkPath(file.path);
            }
          }),
        );

        unawaited(PlayerHistoryCacheService.instance.saveLastPlayedSong(
          updatedSong,
          history: state.recentlyPlayed,
          queue: state.queue,
        ));
      }
    } catch (_) {}
  }

  void togglePlayPause() {
    // 1. If currently resolving stream, handle instant responsive toggle
    if (state.isResolvingStream) {
      if (state.isPlaying) {
        // User tapped pause while connecting: immediately cancel and update state to pause
        _currentStreamRequestId++;
        try {
          _audioPlayer.stop();
        } catch (_) {}
        state = state.copyWith(
          isPlaying: false,
          isResolvingStream: false,
          isBuffering: false,
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

    // 3. Responsive playback state toggle based directly on user-facing isPlaying state
    if (state.isPlaying) {
      _audioPlayer.pause();
      state = state.copyWith(isPlaying: false, isBuffering: false);
    } else {
      _audioPlayer.play();
      state = state.copyWith(isPlaying: true);
    }
  }

  void pause() {
    if (state.isResolvingStream) {
      _currentStreamRequestId++;
    }
    _audioPlayer.pause();
    state = state.copyWith(isPlaying: false, isBuffering: false);
  }

  void play() {
    if (_audioPlayer.audioSource == null && state.currentSong != null) {
      playSong(state.currentSong!, forceReload: true);
      return;
    }
    _audioPlayer.play();
    state = state.copyWith(isPlaying: true);
  }

  void stop() {
    if (state.isResolvingStream) {
      _currentStreamRequestId++;
    }
    _audioPlayer.stop();
    state = state.copyWith(
      isPlaying: false,
      isBuffering: false,
      isResolvingStream: false,
      position: Duration.zero,
    );
  }

  void fastForward({Duration interval = const Duration(seconds: 10)}) {
    final currentPos = state.position;
    final totalDur = state.duration;
    final target = currentPos + interval;
    if (totalDur > Duration.zero && target >= totalDur) {
      skipNext();
    } else {
      seek(target);
    }
  }

  void rewind({Duration interval = const Duration(seconds: 10)}) {
    final currentPos = state.position;
    final target = currentPos - interval;
    seek(target > Duration.zero ? target : Duration.zero);
  }

  Future<void> seek(Duration position) async {
    final thisSeekGen = ++_seekGeneration;
    _pendingSeekPosition = position;
    final newLyricIdx = LyricsService.computeActiveLyricIndex(position.inMilliseconds, state.lyrics);
    state = state.copyWith(
      position: position,
      activeLyricIndex: newLyricIdx,
      isBuffering: true,
    );

    try {
      await _audioPlayer.seek(position).timeout(const Duration(seconds: 2));
      unawaited(PlayerHistoryCacheService.instance.savePosition(position.inMilliseconds));
    } catch (_) {}

    if (_seekGeneration == thisSeekGen) {
      _pendingSeekPosition = null;
    }
  }

  void seekToLyric(LyricLine line) {
    if (line.startTimeMs != null) {
      seek(Duration(milliseconds: line.startTimeMs!));
    }
  }

  Timer? _sleepTimer;

  void skipNext() {
    if (state.currentSong == null) return;

    // If Repeat-One is active ("loop many times, then repeat the same song"), repeat current track
    if (state.loopMode == LoopMode.one) {
      seek(Duration.zero);
      play();
      return;
    }

    // 1. Regular queue has tracks ("When the loop is on, just play the music that is in queue")
    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remainingQueue = state.queue.sublist(1);
      final updatedHistory = [...state.history, state.currentSong!];
      _playTrackFromQueue(nextSong, queue: remainingQueue, history: updatedHistory);
      return;
    }

    // 2. Queue is empty, check Repeat-All ("When the loop is on, just play the music that is in queue")
    if (state.loopMode == LoopMode.all) {
      final allTracks = state.originalQueue.isNotEmpty
          ? (state.isShuffle
              ? (List<SongItem>.from(state.originalQueue)..shuffle())
              : List<SongItem>.from(state.originalQueue))
          : (state.history.isNotEmpty
              ? (state.isShuffle
                  ? (List<SongItem>.from([...state.history, state.currentSong!])..shuffle())
                  : [...state.history, state.currentSong!])
              : <SongItem>[]);

      if (allTracks.isNotEmpty) {
        final firstTrack = allTracks.first;
        final remainingQueue = allTracks.length > 1 ? allTracks.sublist(1) : <SongItem>[];
        _playTrackFromQueue(firstTrack, queue: remainingQueue, history: const []);
        return;
      }
    }

    // 3. Queue is empty and Loop is OFF: check Autoplay (Infinity / Radio)
    if (state.isAutoplay) {
      if (state.autoplayQueue.isNotEmpty) {
        final nextSong = state.autoplayQueue.first;
        final remainingAutoplay = state.autoplayQueue.sublist(1);
        final updatedHistory = [...state.history, state.currentSong!];
        state = state.copyWith(autoplayQueue: remainingAutoplay);
        _playTrackFromQueue(nextSong, queue: const [], history: updatedHistory);
        if (remainingAutoplay.length <= 2) {
          _fetchAutoplayQueue(nextSong);
        }
        return;
      } else {
        _fetchAutoplayNext();
        return;
      }
    }

    // 4. Autoplay is OFF and queue is empty:
    // "don't play similar types of songs" - stop playback cleanly!
    pause();
    seek(Duration.zero);
  }

  void _playTrackFromQueue(
    SongItem song, {
    required List<SongItem> queue,
    required List<SongItem> history,
  }) {
    state = state.copyWith(
      queue: queue,
      history: history,
    );
    playSong(
      song,
      contextQueue: queue,
      initialHistory: history,
      originalTracklist: state.originalQueue,
      forceReload: true,
    );
  }

  Future<void> _fetchAutoplayQueue(SongItem song) async {
    if (!state.isAutoplay) return;
    try {
      final musicService = _ref.read(musicServiceProvider);
      final tracks = await musicService.getSongRadio(
        song.id,
        artist: song.artist,
        title: song.title,
      );
      if (!mounted) return;
      if (!state.isAutoplay) return; // User turned off autoplay while request was in-flight
      final candidateTracks = tracks.where((s) => s.id != song.id).toList();
      if (candidateTracks.isNotEmpty && state.isAutoplay) {
        state = state.copyWith(autoplayQueue: candidateTracks);
      }
    } catch (e) {
      debugPrint('[PlayerNotifier] Error fetching autoplay queue: $e');
    }
  }

  Future<void> fetchAutoplayQueueForCurrentSong() async {
    final current = state.currentSong;
    if (current != null && state.isAutoplay) {
      await _fetchAutoplayQueue(current);
    }
  }

  Future<void> _fetchAutoplayNext() async {
    if (!state.isAutoplay) {
      pause();
      seek(Duration.zero);
      return;
    }
    final current = state.currentSong;
    if (current == null) return;
    try {
      final musicService = _ref.read(musicServiceProvider);
      final tracks = await musicService.getSongRadio(
        current.id,
        artist: current.artist,
        title: current.title,
      );
      if (!mounted) return;
      if (!state.isAutoplay) {
        pause();
        seek(Duration.zero);
        return;
      }
      final candidateTracks = tracks.where((s) => s.id != current.id).toList();
      if (candidateTracks.isNotEmpty && state.isAutoplay) {
        final nextSong = candidateTracks.first;
        final nextQueue = candidateTracks.sublist(1);
        final updatedHistory = [...state.history, current];
        state = state.copyWith(autoplayQueue: nextQueue);
        _playTrackFromQueue(nextSong, queue: const [], history: updatedHistory);
        return;
      }
    } catch (_) {}

    // If radio fails or autoplay is off, pause cleanly
    pause();
    seek(Duration.zero);
  }

  Future<void> startRadio(SongItem song) async {
    state = state.copyWith(
      isAutoplay: true,
      queue: const [],
      history: const [],
      originalQueue: [song],
    );
    await playSong(song, forceReload: true);
    await _fetchAutoplayQueue(song);
  }

  DateTime? _lastPreviousTapTime;

  void skipPrevious() {
    if (state.currentSong == null) return;

    final now = DateTime.now();
    final isDoubleTap = _lastPreviousTapTime != null &&
        now.difference(_lastPreviousTapTime!) < const Duration(milliseconds: 1800);
    _lastPreviousTapTime = now;

    // 1. If double-tapped within 1.8 seconds, immediately jump to previous track in history
    if (isDoubleTap && state.history.isNotEmpty) {
      final prevSong = state.history.last;
      final remainingHistory = state.history.sublist(0, state.history.length - 1);
      final updatedQueue = [state.currentSong!, ...state.queue];
      _playTrackFromQueue(prevSong, queue: updatedQueue, history: remainingHistory);
      return;
    }

    // 2. If played >= 3 seconds and not rapid double tap, restart current track to beginning
    if (state.position.inSeconds >= 3 && !isDoubleTap) {
      seek(Duration.zero);
      play();
      return;
    }

    // 3. If within first 3 seconds, go to previous track in history
    if (state.history.isNotEmpty) {
      final prevSong = state.history.last;
      final remainingHistory = state.history.sublist(0, state.history.length - 1);
      // Prepend currentSong back to queue so 'next' can return to it
      final updatedQueue = [state.currentSong!, ...state.queue];
      _playTrackFromQueue(prevSong, queue: updatedQueue, history: remainingHistory);
      return;
    }

    // 4. If history is empty, restart track
    seek(Duration.zero);
    play();
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
    setLoopMode(nextMode);
  }

  void setLoopMode(LoopMode mode) {
    // Only configure native player loop when repeating the exact same audio stream (LoopMode.one).
    // For LoopMode.all, Wavify coordinates advancing and cycling across tracks in the queue.
    _audioPlayer.setLoopMode(mode == LoopMode.one ? LoopMode.one : LoopMode.off);
    state = state.copyWith(loopMode: mode);
  }

  void toggleShuffle() {
    setShuffle(!state.isShuffle);
  }

  void setShuffle(bool enabled) {
    if (state.isShuffle == enabled) return;
    _audioPlayer.setShuffleModeEnabled(enabled);

    if (enabled) {
      // Shuffling: save original order if needed and shuffle upcoming queue
      final orig = state.originalQueue.isNotEmpty
          ? state.originalQueue
          : (state.currentSong != null ? [state.currentSong!, ...state.queue] : state.queue);
      final shuffledQueue = List<SongItem>.from(state.queue)..shuffle();
      state = state.copyWith(
        isShuffle: true,
        queue: shuffledQueue,
        originalQueue: orig,
      );
    } else {
      // Un-shuffling: restore remaining unplayed tracks in original order
      if (state.originalQueue.isNotEmpty) {
        final currentId = state.currentSong?.id;
        final historyIds = state.history.map((s) => s.id).toSet();
        final unplayedTracks = state.originalQueue
            .where((s) => s.id != currentId && !historyIds.contains(s.id))
            .toList();
        state = state.copyWith(
          isShuffle: false,
          queue: unplayedTracks,
        );
      } else {
        state = state.copyWith(isShuffle: false);
      }
    }
  }

  void toggleAutoplay() {
    setAutoplay(!state.isAutoplay);
  }

  void setAutoplay(bool enabled) {
    state = state.copyWith(
      isAutoplay: enabled,
      autoplayQueue: enabled ? state.autoplayQueue : const [],
    );
    if (enabled) {
      if (state.currentSong != null) {
        _fetchAutoplayQueue(state.currentSong!);
      }
    }
  }

  void setVolume(double val) {
    _audioPlayer.setVolume(val);
    state = state.copyWith(volume: val);
  }

  void addToQueue(SongItem song) {
    final updated = List<SongItem>.from(state.queue)..add(song);
    state = state.copyWith(queue: updated);
  }

  void playNext(SongItem song) {
    final updated = [song, ...state.queue];
    state = state.copyWith(queue: updated);
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < state.queue.length) {
      final updated = List<SongItem>.from(state.queue)..removeAt(index);
      state = state.copyWith(queue: updated);
    }
  }

  void removeFromAutoplayQueue(int index) {
    if (index >= 0 && index < state.autoplayQueue.length) {
      final updated = List<SongItem>.from(state.autoplayQueue)..removeAt(index);
      state = state.copyWith(autoplayQueue: updated);
    }
  }

  void removeCurrentSong() {
    if (state.queue.isNotEmpty || state.autoplayQueue.isNotEmpty) {
      skipNext();
    } else {
      pause();
      seek(Duration.zero);
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    final updated = List<SongItem>.from(state.queue);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= updated.length) return;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = state.copyWith(queue: updated);
  }

  void reorderAutoplayQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.autoplayQueue.length) return;
    final updated = List<SongItem>.from(state.autoplayQueue);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= updated.length) return;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = state.copyWith(autoplayQueue: updated);
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (duration == null || duration == Duration.zero) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }

    final endTime = DateTime.now().add(duration);
    state = state.copyWith(
      sleepTimerDuration: duration,
      sleepTimerEndTime: endTime,
    );

    _sleepTimer = Timer(duration, () {
      pause();
      cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(clearSleepTimer: true);
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _audioSession = session;

      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      final devices = await session.getDevices(includeOutputs: true, includeInputs: false);
      _updateAudioDevices(devices);

      _devicesSub = session.devicesStream.listen((devices) {
        _updateAudioDevices(devices);
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        refreshAudioDevices();
      });
    } catch (e) {
      debugPrint('AudioSession init error: $e');
    }
  }

  Future<void> refreshAudioDevices() async {
    try {
      if (_audioSession != null) {
        final devices = await _audioSession!.getDevices(includeOutputs: true, includeInputs: false);
        _updateAudioDevices(devices);
      }
    } catch (_) {}
  }

  void _updateAudioDevices(Set<AudioDevice> rawDevices) {
    if (!mounted) return;

    final outputDevices = rawDevices.where((d) => d.isOutput).toList();
    final List<AudioDeviceItem> mappedDevices = [];

    for (final dev in outputDevices) {
      final formattedName = _formatDeviceName(dev);
      if (!mappedDevices.any((d) => d.name == formattedName)) {
        mappedDevices.add(AudioDeviceItem(
          id: dev.id,
          name: formattedName,
          category: _mapCategory(dev.type),
        ));
      }
    }

    // Always ensure "Phone Speaker" is present in available devices list
    if (!mappedDevices.any((d) => d.isSpeaker)) {
      mappedDevices.add(const AudioDeviceItem(
        id: 'speaker',
        name: 'Phone Speaker',
        category: OutputDeviceCategory.speaker,
      ));
    }

    AudioDeviceItem? activeDevice;

    // Check if user previously manually selected a device that is still connected
    final currentSelectedId = state.selectedDeviceId;
    if (currentSelectedId != null) {
      for (final d in mappedDevices) {
        if (d.id == currentSelectedId) {
          activeDevice = d;
          break;
        }
      }
    }

    if (activeDevice == null) {
      // 1. Bluetooth devices (A2DP, LE, SCO)
      for (final d in mappedDevices) {
        if (d.isBluetooth) {
          activeDevice = d;
          break;
        }
      }

      // 2. Wired headphones / USB audio
      if (activeDevice == null) {
        for (final d in mappedDevices) {
          if (d.isHeadphones) {
            activeDevice = d;
            break;
          }
        }
      }

      // 3. Speaker
      if (activeDevice == null) {
        for (final d in mappedDevices) {
          if (d.isSpeaker) {
            activeDevice = d;
            break;
          }
        }
      }

      activeDevice ??= mappedDevices.firstOrNull ??
          const AudioDeviceItem(
            id: 'speaker',
            name: 'Phone Speaker',
            category: OutputDeviceCategory.speaker,
          );
    }

    final updatedList = mappedDevices.map((d) {
      return d.copyWith(isSelected: d.id == activeDevice!.id);
    }).toList();

    state = state.copyWith(
      connectedDevice: activeDevice.copyWith(isSelected: true),
      availableAudioDevices: updatedList,
    );
  }

  OutputDeviceCategory _mapCategory(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothLe:
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.hearingAid:
        return OutputDeviceCategory.bluetooth;
      case AudioDeviceType.wiredHeadphones:
      case AudioDeviceType.wiredHeadset:
        return OutputDeviceCategory.headphones;
      case AudioDeviceType.usbAudio:
        return OutputDeviceCategory.usb;
      case AudioDeviceType.builtInSpeaker:
      case AudioDeviceType.builtInSpeakerSafe:
      case AudioDeviceType.builtInEarpiece:
        return OutputDeviceCategory.speaker;
      default:
        return OutputDeviceCategory.other;
    }
  }

  String _formatDeviceName(AudioDevice device) {
    final rawName = device.name.trim();
    if (rawName.isNotEmpty &&
        rawName.toLowerCase() != 'speaker' &&
        rawName.toLowerCase() != 'built-in speaker' &&
        rawName.toLowerCase() != 'built-in earpiece' &&
        rawName.toLowerCase() != 'audio_device') {
      return rawName;
    }

    switch (device.type) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothLe:
      case AudioDeviceType.bluetoothSco:
        return rawName.isNotEmpty ? rawName : 'Bluetooth Audio';
      case AudioDeviceType.wiredHeadphones:
      case AudioDeviceType.wiredHeadset:
        return 'Headphones';
      case AudioDeviceType.usbAudio:
        return rawName.isNotEmpty ? rawName : 'USB Audio';
      case AudioDeviceType.builtInSpeaker:
      case AudioDeviceType.builtInSpeakerSafe:
        return 'Phone Speaker';
      case AudioDeviceType.builtInEarpiece:
        return 'Phone Earpiece';
      default:
        return rawName.isNotEmpty ? rawName : 'Phone Speaker';
    }
  }

  void selectAudioDevice(AudioDeviceItem device) {
    final updatedList = state.availableAudioDevices.map((d) {
      return d.copyWith(isSelected: d.id == device.id);
    }).toList();

    state = state.copyWith(
      connectedDevice: device.copyWith(isSelected: true),
      selectedDeviceId: device.id,
      availableAudioDevices: updatedList,
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playbackEventSub?.cancel();
    _devicesSub?.cancel();
    _becomingNoisySub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Global Riverpod provider for player state management.
final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerStateModel>((ref) {
  return PlayerNotifier(ref);
});

/// Riverpod provider determining whether the play/pause button should display a loading spinner.
/// True ONLY while the stream is actively resolving or buffering before initial audio playback.
/// Once audio is ready or playing, this is guaranteed to be false.
final playerIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(playerProvider.select((state) {
    if (!state.isPlaying) return false;
    if (state.isResolvingStream) return true;
    if (state.isBuffering && state.position == Duration.zero) return true;
    return false;
  }));
});

