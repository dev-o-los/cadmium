import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song_item.dart';

/// Central AudioHandler that connects just_audio to the system media notification center
/// and lock screen across Android and iOS.
///
/// Production Features:
/// 1. Broadcasts real-time playback state, position, buffering, and duration for the
///    system notification seekbar (scroll bar) with zero-lag rate limiting.
/// 2. Displays song title, artist, album, and high-res rounded cover art in the notification.
/// 3. Fully wires all controls: Previous, Play/Pause, Next, Fast Forward (+10s),
///    Rewind (-10s), Seek scrubbing, Stop, Repeat, and Shuffle.
/// 4. Handles background playback when the app is minimized or the screen is locked.
/// 5. Immediate optimistic state emissions on play/pause/stop for seamless, instant response.
class CadmiumAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onStop;
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  VoidCallback? onFastForward;
  VoidCallback? onRewind;
  void Function(Duration position)? onSeek;
  void Function(AudioServiceRepeatMode repeatMode)? onSetRepeatMode;
  void Function(AudioServiceShuffleMode shuffleMode)? onSetShuffleMode;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  // Zero-lag state deduplication and position throttling
  bool _isOptimisticPlaying = false;
  bool? _lastPlaying;
  AudioProcessingState? _lastProcessingState;
  int? _lastPositionMs;
  int? _lastDurationMs;
  DateTime _lastBroadcastTime = DateTime.fromMillisecondsSinceEpoch(0);

  // System notification repeat and shuffle mode synchronization
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;

  AudioServiceRepeatMode get repeatMode => _repeatMode;
  AudioServiceShuffleMode get shuffleMode => _shuffleMode;

  CadmiumAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _initListeners();
  }

  AudioPlayer get player => _player;

  void _initListeners() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) => _broadcastPlaybackState(),
      onError: (e) => debugPrint('[CadmiumAudioHandler] playbackEvent error: $e'),
    );

    _playerStateSub = _player.playerStateStream.listen(
      (state) => _broadcastPlaybackState(),
      onError: (e) => debugPrint('[CadmiumAudioHandler] playerState error: $e'),
    );
  }

  /// System actions supported across Android notification center, lock screen,
  /// Bluetooth, smartwatches, and Android Auto.
  static const Set<MediaAction> _kStandardSystemActions = {
    MediaAction.seek,
    MediaAction.seekForward,
    MediaAction.seekBackward,
    MediaAction.play,
    MediaAction.pause,
    MediaAction.playPause,
    MediaAction.stop,
    MediaAction.skipToNext,
    MediaAction.skipToPrevious,
    MediaAction.fastForward,
    MediaAction.rewind,
    MediaAction.setRepeatMode,
    MediaAction.setShuffleMode,
  };

  /// Constructs the clean notification control buttons list.
  /// Standard 3-button media player controls: [skipToPrevious, play/pause, skipToNext].
  /// Removing MediaControl.stop eliminates the awkward wide-box layout and button
  /// crowding on Android devices, keeping the notification sleek, compact, and centered.
  List<MediaControl> _buildControls({required bool isPlaying}) {
    return [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];
  }

  /// Broadcasts an optimistic playback state immediately without waiting for ExoPlayer
  /// stream events, providing instant visual feedback on button taps.
  void _broadcastOptimisticState({
    required bool playing,
    AudioProcessingState? processingState,
  }) {
    final effectiveProcessing = processingState ??
        (playing ? AudioProcessingState.ready : AudioProcessingState.ready);

    _lastPlaying = playing;
    _lastProcessingState = effectiveProcessing;
    _lastBroadcastTime = DateTime.now();

    playbackState.add(
      PlaybackState(
        controls: _buildControls(isPlaying: playing),
        systemActions: _kStandardSystemActions,
        androidCompactActionIndices: const [0, 1, 2],
        processingState: effectiveProcessing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: playing ? (_player.speed > 0 ? _player.speed : 1.0) : 0.0,
        queueIndex: 0,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
      ),
    );
  }

  /// Broadcasts the current player state to the OS notification and lock screen.
  /// Throttles pure position updates to eliminate Android NotificationManager IPC lag.
  void _broadcastPlaybackState({bool force = false}) {
    if (_player.playing) {
      _isOptimisticPlaying = false;
    }
    final isPlaying = _isOptimisticPlaying || _player.playing;
    final processingState = _player.processingState;
    final currentPos = _player.position;
    final totalDur = _player.duration;

    final audioProcessingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[processingState] ?? AudioProcessingState.idle;

    final now = DateTime.now();
    if (!force) {
      final stateChanged = isPlaying != _lastPlaying ||
          audioProcessingState != _lastProcessingState ||
          (totalDur?.inMilliseconds != _lastDurationMs);

      final posDiff = (currentPos.inMilliseconds - (_lastPositionMs ?? 0)).abs();
      final timeDiff = now.difference(_lastBroadcastTime).inMilliseconds;

      // Throttle pure position updates to 1000ms.
      // Android SystemUI MediaSession automatically projects playback position
      // forward in time using updatePosition and speed, so frequent updates
      // only cause NotificationManager IPC lag.
      if (!stateChanged && (posDiff < 1000 || timeDiff < 1000)) {
        return;
      }
    }

    _lastPlaying = isPlaying;
    _lastProcessingState = audioProcessingState;
    _lastPositionMs = currentPos.inMilliseconds;
    _lastDurationMs = totalDur?.inMilliseconds;
    _lastBroadcastTime = now;

    final isActuallyPlaying = isPlaying && processingState == ProcessingState.ready;

    playbackState.add(
      PlaybackState(
        controls: _buildControls(isPlaying: isPlaying),
        systemActions: _kStandardSystemActions,
        // In Android notifications, shows Previous, Play/Pause, and Next in compact mode
        androidCompactActionIndices: const [0, 1, 2],
        processingState: audioProcessingState,
        playing: isPlaying,
        updatePosition: currentPos,
        bufferedPosition: _player.bufferedPosition,
        speed: isActuallyPlaying ? (_player.speed > 0 ? _player.speed : 1.0) : 0.0,
        queueIndex: 0,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
      ),
    );
  }

  /// Updates the notification metadata (title, artist, album, artwork, duration)
  /// whenever the current song changes.
  void updateCurrentSong(
    SongItem song, {
    Duration? duration,
    String? localArtworkPath,
    bool isBuffering = false,
  }) {
    Uri? artUri;
    if (localArtworkPath != null && localArtworkPath.isNotEmpty) {
      artUri = Uri.file(localArtworkPath);
    } else {
      final thumb = song.resolvedThumbnailUrl;
      if (thumb != null && thumb.isNotEmpty) {
        artUri = Uri.tryParse(thumb);
      }
    }

    final effectiveDuration = duration ??
        (song.durationSeconds != null && song.durationSeconds! > 0
            ? Duration(seconds: song.durationSeconds!)
            : mediaItem.value?.duration);

    mediaItem.add(
      MediaItem(
        id: song.id,
        album: song.album ?? 'Single',
        title: song.title,
        artist: song.artist,
        duration: effectiveDuration,
        artUri: artUri,
      ),
    );

    // Immediately emit an active playback state so that the OS MediaSession
    // enters the active foreground state, displaying the notification player without delay!
    _isOptimisticPlaying = isBuffering || _player.playing;
    _broadcastOptimisticState(
      playing: _isOptimisticPlaying,
      processingState: isBuffering
          ? AudioProcessingState.buffering
          : (_player.playing
              ? AudioProcessingState.ready
              : AudioProcessingState.idle),
    );
  }

  /// Updates the artwork in the active notification to a local rounded-corner file.
  void updateArtworkPath(String localArtworkPath) {
    final current = mediaItem.value;
    if (current != null) {
      mediaItem.add(current.copyWith(artUri: Uri.file(localArtworkPath)));
      _broadcastPlaybackState(force: true);
    }
  }

  /// Updates the duration in the notification when stream headers resolve total length.
  void updateDuration(Duration duration) {
    final current = mediaItem.value;
    if (current != null && current.duration != duration) {
      mediaItem.add(current.copyWith(duration: duration));
      _broadcastPlaybackState(force: true);
    }
  }

  @override
  Future<void> play() async {
    _isOptimisticPlaying = true;
    _broadcastOptimisticState(playing: true);
    if (onPlay != null) {
      onPlay!();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    _isOptimisticPlaying = false;
    _broadcastOptimisticState(playing: false);
    if (onPause != null) {
      onPause!();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> stop() async {
    _isOptimisticPlaying = false;
    _broadcastOptimisticState(
      playing: false,
      processingState: AudioProcessingState.idle,
    );
    if (onStop != null) {
      onStop!();
    }
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeek != null) {
      onSeek!(position);
    } else {
      await _player.seek(position);
      _broadcastPlaybackState(force: true);
    }
  }

  @override
  Future<void> fastForward() async {
    if (onFastForward != null) {
      onFastForward!();
    } else {
      final currentPos = _player.position;
      final totalDur = mediaItem.value?.duration ?? _player.duration ?? Duration.zero;
      final target = currentPos + const Duration(seconds: 10);
      if (totalDur > Duration.zero && target >= totalDur) {
        await skipToNext();
      } else {
        await seek(target);
      }
    }
  }

  @override
  Future<void> rewind() async {
    if (onRewind != null) {
      onRewind!();
    } else {
      final currentPos = _player.position;
      final target = currentPos - const Duration(seconds: 10);
      await seek(target > Duration.zero ? target : Duration.zero);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (onSkipNext != null) {
      onSkipNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipPrevious != null) {
      onSkipPrevious!();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    onSetRepeatMode?.call(repeatMode);
    _broadcastPlaybackState(force: true);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    onSetShuffleMode?.call(shuffleMode);
    _broadcastPlaybackState(force: true);
  }

  /// Synchronizes repeat mode from app player state to system media notification.
  void syncRepeatMode(AudioServiceRepeatMode repeatMode) {
    if (_repeatMode != repeatMode) {
      _repeatMode = repeatMode;
      _broadcastPlaybackState(force: true);
    }
  }

  /// Synchronizes shuffle mode from app player state to system media notification.
  void syncShuffleMode(AudioServiceShuffleMode shuffleMode) {
    if (_shuffleMode != shuffleMode) {
      _shuffleMode = shuffleMode;
      _broadcastPlaybackState(force: true);
    }
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (_player.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  Future<void> dispose() async {
    await _playbackEventSub?.cancel();
    await _playerStateSub?.cancel();
    await _player.dispose();
  }
}

/// Global provider for the Cadmium AudioHandler.
final cadmiumAudioHandlerProvider = Provider<CadmiumAudioHandler>((ref) {
  // Overridden in ProviderScope in main()
  return CadmiumAudioHandler();
});

/// Initializes the OS background media service for Android and iOS.
Future<CadmiumAudioHandler> initCadmiumAudioService() async {
  if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
    return CadmiumAudioHandler();
  }

  try {
    return await AudioService.init(
      builder: () => CadmiumAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.devolos.cadmium.playback',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationChannelDescription:
            'Cadmium high-fidelity background music playback controls',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        androidNotificationClickStartsActivity: true,
        notificationColor: Color(0xFF1C1C1E),
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
  } catch (e) {
    debugPrint('[CadmiumAudioHandler] AudioService.init error (fallback to local handler): $e');
    return CadmiumAudioHandler();
  }
}
