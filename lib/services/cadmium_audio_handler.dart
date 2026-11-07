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
/// Features:
/// 1. Broadcasts real-time playback state, position, buffering, and duration for the
///    system notification seekbar (scroll bar).
/// 2. Displays song title, artist, album, and high-res cover art in the notification.
/// 3. Provides media controls: Previous, Play/Pause, Next, and Seek scrubbing.
/// 4. Handles background playback when the app is minimized or the screen is locked.
class CadmiumAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  CadmiumAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _initListeners();
  }

  AudioPlayer get player => _player;

  void _initListeners() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) => _broadcastPlaybackState(),
      onError: (e) => debugPrint('CadmiumAudioHandler playbackEvent error: $e'),
    );

    _playerStateSub = _player.playerStateStream.listen(
      (state) => _broadcastPlaybackState(),
      onError: (e) => debugPrint('CadmiumAudioHandler playerState error: $e'),
    );
  }

  /// Broadcasts the current player state to the OS notification and lock screen.
  void _broadcastPlaybackState() {
    final isPlaying = _player.playing;
    final processingState = _player.processingState;

    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // In Android notifications, shows Previous, Play/Pause, and Next in compact mode
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[processingState] ?? AudioProcessingState.idle,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
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
    // enters the active foreground state, displaying the notification player and
    // Dynamic Island / Aqua Dynamics live alert capsule without delay!
    final isPlaying = isBuffering || _player.playing;
    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : (_player.playing
                ? AudioProcessingState.ready
                : AudioProcessingState.idle),
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: 1.0,
        queueIndex: 0,
      ),
    );
  }

  /// Updates the duration in the notification when stream headers resolve total length.
  void updateDuration(Duration duration) {
    final current = mediaItem.value;
    if (current != null && current.duration != duration) {
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
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
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        androidNotificationClickStartsActivity: true,
        notificationColor: Color(0xFF1C1C1E),
      ),
    );
  } catch (e) {
    debugPrint('AudioService.init error (fallback to local handler): $e');
    return CadmiumAudioHandler();
  }
}
