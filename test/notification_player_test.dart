import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/services/artwork_cache_service.dart';
import 'package:wavify/services/cadmium_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CadmiumAudioHandler Unit Tests', () {
    late CadmiumAudioHandler handler;

    setUp(() {
      handler = CadmiumAudioHandler();
    });

    tearDown(() async {
      await handler.dispose();
    });

    test('Initializes with full system actions including fast forward, rewind, skip, repeat, shuffle', () {
      final state = handler.playbackState.value;
      expect(state, isNotNull);
      expect(state.systemActions, contains(MediaAction.play));
      expect(state.systemActions, contains(MediaAction.pause));
      expect(state.systemActions, contains(MediaAction.stop));
      expect(state.systemActions, contains(MediaAction.skipToNext));
      expect(state.systemActions, contains(MediaAction.skipToPrevious));
      expect(state.systemActions, contains(MediaAction.fastForward));
      expect(state.systemActions, contains(MediaAction.rewind));
      expect(state.systemActions, contains(MediaAction.seek));
      expect(state.systemActions, contains(MediaAction.setRepeatMode));
      expect(state.systemActions, contains(MediaAction.setShuffleMode));
      expect(state.androidCompactActionIndices, equals([0, 1, 2]));
    });

    test('Optimistic state emission on play, pause, and stop occurs instantaneously', () async {
      bool playCalled = false;
      bool pauseCalled = false;
      bool stopCalled = false;

      handler.onPlay = () => playCalled = true;
      handler.onPause = () => pauseCalled = true;
      handler.onStop = () => stopCalled = true;

      // Play
      await handler.play();
      expect(playCalled, isTrue);
      expect(handler.playbackState.value.playing, isTrue);

      // Pause
      await handler.pause();
      expect(pauseCalled, isTrue);
      expect(handler.playbackState.value.playing, isFalse);

      // Stop
      await handler.stop();
      expect(stopCalled, isTrue);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        equals(AudioProcessingState.idle),
      );
    });

    test('Fast forward and rewind invoke callbacks or seek properly', () async {
      bool ffCalled = false;
      bool rwCalled = false;

      handler.onFastForward = () => ffCalled = true;
      handler.onRewind = () => rwCalled = true;

      await handler.fastForward();
      expect(ffCalled, isTrue);

      await handler.rewind();
      expect(rwCalled, isTrue);
    });

    test('Skip next and skip previous invoke callbacks', () async {
      bool nextCalled = false;
      bool prevCalled = false;

      handler.onSkipNext = () => nextCalled = true;
      handler.onSkipPrevious = () => prevCalled = true;

      await handler.skipToNext();
      expect(nextCalled, isTrue);

      await handler.skipToPrevious();
      expect(prevCalled, isTrue);
    });

    test('updateCurrentSong updates media item and emits active state', () {
      final song = const SongItem(
        id: 'test_song_1',
        title: 'Test Song Title',
        artist: 'Test Artist',
        album: 'Test Album',
        durationSeconds: 240,
        thumbnailUrl: 'https://example.com/art.jpg',
      );

      handler.updateCurrentSong(song, isBuffering: false);

      final media = handler.mediaItem.value;
      expect(media, isNotNull);
      expect(media!.id, equals('test_song_1'));
      expect(media.title, equals('Test Song Title'));
      expect(media.artist, equals('Test Artist'));
      expect(media.album, equals('Test Album'));
      expect(media.duration, equals(const Duration(seconds: 240)));
      expect(media.artUri, equals(Uri.parse('https://example.com/art.jpg')));
    });

    test('updateArtworkPath updates local file URI for rounded notification artwork', () {
      final song = const SongItem(
        id: 'test_song_2',
        title: 'Test Song 2',
        artist: 'Test Artist 2',
      );

      handler.updateCurrentSong(song);
      handler.updateArtworkPath('/tmp/notif_rounded_test_song_2.png');

      final media = handler.mediaItem.value;
      expect(media, isNotNull);
      expect(
        media!.artUri,
        equals(Uri.file('/tmp/notif_rounded_test_song_2.png')),
      );
    });

    test('Notification controls contain exactly 3 clean buttons without stop button', () {
      final state = handler.playbackState.value;
      expect(state.controls.length, equals(3));
      expect(state.controls[0].action, equals(MediaAction.skipToPrevious));
      expect(state.controls[1].action, equals(MediaAction.play));
      expect(state.controls[2].action, equals(MediaAction.skipToNext));
      expect(state.controls.any((c) => c.action == MediaAction.stop), isFalse);
    });

    test('Repeat and shuffle modes are synced and broadcast to playbackState', () async {
      expect(handler.repeatMode, equals(AudioServiceRepeatMode.none));
      expect(handler.shuffleMode, equals(AudioServiceShuffleMode.none));

      // Test repeat mode sync
      handler.syncRepeatMode(AudioServiceRepeatMode.all);
      expect(handler.repeatMode, equals(AudioServiceRepeatMode.all));
      expect(handler.playbackState.value.repeatMode, equals(AudioServiceRepeatMode.all));

      handler.syncRepeatMode(AudioServiceRepeatMode.one);
      expect(handler.repeatMode, equals(AudioServiceRepeatMode.one));
      expect(handler.playbackState.value.repeatMode, equals(AudioServiceRepeatMode.one));

      // Test shuffle mode sync
      handler.syncShuffleMode(AudioServiceShuffleMode.all);
      expect(handler.shuffleMode, equals(AudioServiceShuffleMode.all));
      expect(handler.playbackState.value.shuffleMode, equals(AudioServiceShuffleMode.all));

      handler.syncShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.shuffleMode, equals(AudioServiceShuffleMode.none));
      expect(handler.playbackState.value.shuffleMode, equals(AudioServiceShuffleMode.none));

      // Test setRepeatMode / setShuffleMode from system
      AudioServiceRepeatMode? reportedRepeat;
      AudioServiceShuffleMode? reportedShuffle;
      handler.onSetRepeatMode = (mode) => reportedRepeat = mode;
      handler.onSetShuffleMode = (mode) => reportedShuffle = mode;

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(reportedRepeat, equals(AudioServiceRepeatMode.all));
      expect(handler.playbackState.value.repeatMode, equals(AudioServiceRepeatMode.all));

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(reportedShuffle, equals(AudioServiceShuffleMode.all));
      expect(handler.playbackState.value.shuffleMode, equals(AudioServiceShuffleMode.all));
    });
  });

  group('ArtworkCacheService Rounded Corners Tests', () {
    test(
      'createRoundedCornerArtwork renders image with transparent corners',
      () async {
        // Create a solid red 64x64 PNG in memory
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(
          recorder,
          const ui.Rect.fromLTWH(0, 0, 64, 64),
        );
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 64, 64),
          ui.Paint()..color = const ui.Color(0xFFFF0000),
        );
        final rawImg = await recorder.endRecording().toImage(64, 64);
        final rawByteData = await rawImg.toByteData(
          format: ui.ImageByteFormat.png,
        );
        expect(rawByteData, isNotNull);

        final rawBytes = rawByteData!.buffer.asUint8List();

        // Convert using createRoundedCornerArtwork
        final roundedBytes =
            await ArtworkCacheService.createRoundedCornerArtwork(
              rawBytes,
              targetSize: 64,
              cornerRadiusFraction: 0.25, // 16px radius
            );

        expect(roundedBytes, isNotNull);
        expect(roundedBytes!.lengthInBytes, greaterThan(0));

        // Decode the rounded image to inspect corner pixel alpha
        final codec = await ui.instantiateImageCodec(roundedBytes);
        final frame = await codec.getNextFrame();
        final decodedImage = frame.image;
        expect(decodedImage.width, equals(64));
        expect(decodedImage.height, equals(64));

        final byteData = await decodedImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(byteData, isNotNull);

        final pixels = byteData!.buffer.asUint8List();

        // Top-left corner (0, 0) should be transparent (alpha == 0)
        final cornerAlpha = pixels[3];
        expect(
          cornerAlpha,
          equals(0),
          reason: 'Top-left corner must be fully transparent',
        );

        // Center pixel (32, 32) should be solid opaque (alpha == 255)
        final centerIdx = (32 * 64 + 32) * 4;
        final centerAlpha = pixels[centerIdx + 3];
        expect(centerAlpha, equals(255), reason: 'Center pixel must be solid');
      },
    );
  });

  group('PlayerNotifier Navigation & Controls Integration Tests', () {
    test('Fast forward seeks +10s and rewind seeks -10s', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playerProvider.notifier);
      final song = const SongItem(
        id: 'nav_song_1',
        title: 'Nav Song 1',
        artist: 'Artist',
        durationSeconds: 300,
      );

      notifier.state = notifier.state.copyWith(
        currentSong: song,
        duration: const Duration(seconds: 300),
        position: const Duration(seconds: 50),
        isPlaying: true,
      );

      notifier.fastForward(interval: const Duration(seconds: 10));
      expect(notifier.state.position, equals(const Duration(seconds: 60)));

      notifier.rewind(interval: const Duration(seconds: 15));
      expect(notifier.state.position, equals(const Duration(seconds: 45)));
    });

    test(
      'Skip previous double-tap jumps to previous song in history',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(playerProvider.notifier);
        final song1 = const SongItem(
          id: 'song_1',
          title: 'Song 1',
          artist: 'Artist',
        );
        final song2 = const SongItem(
          id: 'song_2',
          title: 'Song 2',
          artist: 'Artist',
        );

        notifier.state = notifier.state.copyWith(
          currentSong: song2,
          history: [song1],
          position: const Duration(seconds: 15), // > 3 seconds in
          isPlaying: true,
        );

        // First tap restarts song to 0:00
        notifier.skipPrevious();
        expect(notifier.state.position, equals(Duration.zero));

        // Immediate second tap jumps to song1 in history
        notifier.skipPrevious();
        expect(notifier.state.currentSong?.id, equals('song_1'));
      },
    );
  });
}
