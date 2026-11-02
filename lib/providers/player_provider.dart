// ignore_for_file: experimental_member_use

import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_device_item.dart';
import '../models/song_item.dart';
import '../models/lyric_line.dart';
import '../services/artwork_cache_service.dart';
import '../services/audio_cache_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../services/lyrics_service.dart';
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
  final String? lyricsSource;
  final String? lyricsSongwriters;
  final bool hasWordSyncedLyrics;
  final LyricsProviderType selectedLyricsProvider;
  final String? animatedArtworkUrl;
  final Map<String, String>? animatedArtworkHeaders;
  final AudioDeviceItem connectedDevice;
  final String? selectedDeviceId;
  final List<AudioDeviceItem> availableAudioDevices;

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
    List<SongItem>? recentlyPlayed,
    LoopMode? loopMode,
    bool? isShuffle,
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
      lyricsSource: clearLyricsSource ? null : (lyricsSource ?? this.lyricsSource),
      lyricsSongwriters: clearLyricsSongwriters ? null : (lyricsSongwriters ?? this.lyricsSongwriters),
      hasWordSyncedLyrics: hasWordSyncedLyrics ?? this.hasWordSyncedLyrics,
      selectedLyricsProvider: selectedLyricsProvider ?? this.selectedLyricsProvider,
      animatedArtworkUrl: clearAnimatedArtwork ? null : (animatedArtworkUrl ?? this.animatedArtworkUrl),
      animatedArtworkHeaders: clearAnimatedArtwork ? null : (animatedArtworkHeaders ?? this.animatedArtworkHeaders),
      connectedDevice: connectedDevice ?? this.connectedDevice,
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      availableAudioDevices: availableAudioDevices ?? this.availableAudioDevices,
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
  StreamSubscription<Set<AudioDevice>>? _devicesSub;
  StreamSubscription<void>? _becomingNoisySub;
  AudioSession? _audioSession;
  int _currentStreamRequestId = 0;

  PlayerNotifier(this._ref) : super(const PlayerStateModel()) {
    _initAudioListeners();
    _initAudioSession();
  }

  AudioPlayer get audioPlayer => _audioPlayer;

  void _initAudioListeners() {
    _playerStateSub = _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processing = playerState.processingState;
      final isBuffering = processing == ProcessingState.buffering ||
          processing == ProcessingState.loading;

      if (processing == ProcessingState.completed) {
        if (state.loopMode == LoopMode.one) {
          seek(Duration.zero);
          play();
        } else {
          skipNext();
        }
        return;
      }

      // If the audio player is ready or actively playing, stream resolution and initial buffering are completed!
      if (processing == ProcessingState.ready || (isPlaying && processing != ProcessingState.idle)) {
        state = state.copyWith(
          isPlaying: isPlaying || state.isPlaying,
          isBuffering: false,
          isResolvingStream: false,
        );
        return;
      }

      // While resolving stream, preserve optimistic isPlaying state if player is still idle/loading
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
        return;
      }

      state = state.copyWith(
        position: pos,
        activeLyricIndex: newLyricIdx,
      );
    });

    _durationSub = _audioPlayer.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        state = state.copyWith(duration: dur);
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
        state = state.copyWith(
          isResolvingStream: false,
          isPlaying: false,
          isBuffering: false,
          errorMessage: 'Unable to stream audio track.',
        );
      },
    );
  }

  int _computeActiveLyricIndex(int currentMs, List<LyricLine> lyrics) {
    if (lyrics.isEmpty) return -1;

    // Guard: Before the first timed lyric starts (song intro), no lyric should be active
    final firstStart = lyrics.first.startTimeMs;
    if (firstStart != null && currentMs < firstStart) {
      return -1;
    }

    // 1. Direct active range check: line currently being sung
    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      if (line.startTimeMs == null) continue;

      final start = line.startTimeMs!;
      final end = line.endTimeMs ?? (start + 3500);

      if (currentMs >= start && currentMs < end) {
        return i;
      }
    }

    // 2. Inter-line gap handling (between line i end and line i+1 start)
    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      if (line.startTimeMs == null) continue;

      final nextStart = (i < lyrics.length - 1) ? lyrics[i + 1].startTimeMs : null;
      if (currentMs >= line.startTimeMs! && (nextStart == null || currentMs < nextStart)) {
        // If there's an instrumental break (> 3.5s gap after endTimeMs), un-highlight
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
    );
    ArtworkCacheService.instance.recordSongPlay(song);
    _fetchLyrics(song);
    _fetchAnimatedArtwork(song);
    _resolveMasterArtwork(song);
    refreshAudioDevices();
  }

  /// Selects and plays a song, automatically resolving its stream and fetching synced lyrics.
  Future<void> playSong(SongItem song, {List<SongItem>? contextQueue, bool forceReload = false}) async {
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
    if (contextQueue != null && contextQueue.isNotEmpty) {
      updatedQueue = contextQueue.where((s) => s.id != song.id).toList();
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
      lyrics: const [],
      isLoadingLyrics: true,
      activeLyricIndex: -1,
      position: Duration.zero,
      duration: initialDuration,
    );

    // Fetch lyrics asynchronously in background
    _fetchLyrics(song);

    // Fetch animated looping artwork ("GIF video") asynchronously in background
    _fetchAnimatedArtwork(song);

    // Resolve studio-master album artwork asynchronously if needed
    _resolveMasterArtwork(song);

    // Refresh currently connected audio output device (Bluetooth, headphones, speaker)
    refreshAudioDevices();

    // Track play count and pre-cache high-res artwork for tracks heard repeatedly
    ArtworkCacheService.instance.recordSongPlay(song);

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

        // If heard repeatedly, trigger background audio cache download
        if (ArtworkCacheService.instance.isHeardRepeatedly(song.id)) {
          AudioCacheService.instance.cacheAudioInBackground(
            song.id,
            streamInfo.url,
            streamInfo.headers,
          );
        }
      }

      await _audioPlayer.setAudioSource(audioSource, preload: true);

      // Stream resolution is completed once audio source is loaded
      if (requestId == _currentStreamRequestId && state.currentSong?.id == song.id) {
        state = state.copyWith(isResolvingStream: false);
      }

      final playerDur = _audioPlayer.duration;
      if (playerDur != null && playerDur > Duration.zero) {
        state = state.copyWith(duration: playerDur);
        unawaited(SongMetricsCacheService.instance.setDuration(song.id, playerDur.inSeconds));
      }

      // Guard: User might have skipped track while setting audio source
      if (requestId != _currentStreamRequestId || state.currentSong?.id != song.id) {
        if (requestId == _currentStreamRequestId) {
          state = state.copyWith(isResolvingStream: false, isBuffering: false);
        }
        return;
      }

      await _audioPlayer.play();

      if (requestId != _currentStreamRequestId) return;

      state = state.copyWith(
        isResolvingStream: false,
        isPlaying: true,
        isBuffering: false,
      );
    } catch (e) {
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
    state = state.copyWith(
      selectedLyricsProvider: provider,
      isLoadingLyrics: true,
      lyrics: const [],
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
      if (state.currentSong?.id == song.id && state.selectedLyricsProvider == targetProvider) {
        state = state.copyWith(
          lyrics: result.lines,
          lyricsSource: result.source,
          lyricsSongwriters: result.songwriters,
          hasWordSyncedLyrics: result.hasWordSync,
          isLoadingLyrics: false,
        );
      }
    } catch (e) {
      if (state.currentSong?.id == song.id && state.selectedLyricsProvider == targetProvider) {
        state = state.copyWith(
          lyrics: const [],
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
      if (masterArt != null && masterArt.isNotEmpty && state.currentSong?.id == song.id) {
        final updatedSong = song.copyWith(thumbnailUrl: masterArt);
        state = state.copyWith(currentSong: updatedSong);
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
      playSong(nextSong, contextQueue: remainingQueue, forceReload: true);
    } else if (state.recentlyPlayed.length > 1) {
      final currentIdx = state.recentlyPlayed.indexWhere((s) => s.id == state.currentSong?.id);
      final nextIdx = (currentIdx + 1) % state.recentlyPlayed.length;
      playSong(state.recentlyPlayed[nextIdx], forceReload: true);
    } else if (state.currentSong != null) {
      seek(Duration.zero);
      play();
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
      playSong(state.recentlyPlayed[prevIdx], forceReload: true);
    } else if (state.currentSong != null) {
      seek(Duration.zero);
      play();
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

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _audioSession = session;

      await session.configure(const AudioSessionConfiguration.music());

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

