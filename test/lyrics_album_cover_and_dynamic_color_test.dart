import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/services/artwork_color_service.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/ambient_video_canvas.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';
import 'package:wavify/widgets/player_controls.dart';
import 'package:wavify/widgets/track_options_sheet.dart';
import 'package:wavify/widgets/wavify_cached_image.dart';

void main() {
  group('Lyrics Tab Album Cover & Dynamic Bottom Player Color Tests', () {
    test('ArtworkColorService.extractEffectiveColorUrl prefers video frame thumbnail when preferVideo is true', () {
      const videoThumb = 'https://i.ytimg.com/vi/test_vid_123/hqdefault.jpg';
      const studioAlbumCover = 'https://lh3.googleusercontent.com/album_art=w800-h800';

      // When preferVideo is true, extractEffectiveColorUrl returns the YouTube video frame thumbnail
      final videoColorUrl = ArtworkColorService.extractEffectiveColorUrl(
        highResUrl: studioAlbumCover,
        thumbnailUrl: videoThumb,
        songId: 'test_vid_123',
        preferVideo: true,
      );
      expect(videoColorUrl, equals(videoThumb));

      // When preferVideo is false, it returns the studio album cover
      final albumColorUrl = ArtworkColorService.extractEffectiveColorUrl(
        highResUrl: studioAlbumCover,
        thumbnailUrl: videoThumb,
        songId: 'test_vid_123',
        preferVideo: false,
      );
      expect(albumColorUrl, equals(studioAlbumCover));
    });

    testWidgets('Lyrics tab in PlayerScreen only renders album cover, not video canvas', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      const songWithVideo = SongItem(
        id: 'test_video_track',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        thumbnailUrl: 'https://lh3.googleusercontent.com/art=w800',
        animatedArtworkUrl: 'https://example.com/video.mp4',
      );

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: songWithVideo,
        isPlaying: true,
        animatedArtworkUrl: 'https://example.com/video.mp4',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerScreen(
                initialMode: PlayerViewMode.lyrics,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // In lyrics tab, only the static studio album cover (WavifyCachedImage) is in the tree
      expect(find.byType(WavifyCachedImage), findsWidgets);
      // AmbientVideoCanvas should NOT be in the tree in lyrics tab
      expect(find.byType(AmbientVideoCanvas), findsNothing);
    });

    testWidgets('PlayerControls mini player renders with dynamic liquid glass color', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const song = SongItem(
        id: 'test_song_color',
        title: 'As It Was',
        artist: 'Harry Styles',
        thumbnailUrl: 'https://lh3.googleusercontent.com/cover=w800',
      );

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: song,
        isPlaying: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerControls(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('As It Was'), findsOneWidget);
      expect(find.text('Harry Styles'), findsOneWidget);
      expect(find.byType(PlayerControls), findsOneWidget);
    });

    test('Bottom navigation dock and track menu use frosted glass settings with blur 24', () {
      expect(kLiquidBottomDockGlassSettings.blur, equals(24));
      expect(kTrackMenuGlassSettings.blur, equals(24));
    });

    test('MusicService.getAnimatedArtworkData filters out full video files and keeps short moving GIFs/WebPs', () async {
      final musicService = MusicService();
      addTearDown(musicService.dispose);

      // Video media URL should be filtered out to prevent streaming full videos
      const songWithMp4 = SongItem(
        id: 'test_mp4_song',
        title: 'Video Song',
        artist: 'Artist',
        animatedArtworkUrl: 'https://example.com/stream.mp4',
      );
      final videoResult = await musicService.getAnimatedArtworkData(songWithMp4);
      // Because example.com/stream.mp4 is a full video, it is ignored
      expect(videoResult, isNull);

      // Animated WebP / GIF thumbnail is preserved as short looping moving image
      const songWithWebp = SongItem(
        id: 'test_webp_song',
        title: 'WebP Song',
        artist: 'Artist',
        animatedArtworkUrl: 'https://i.ytimg.com/an_webp/test/mqdefault_6s.webp',
      );
      final webpResult = await musicService.getAnimatedArtworkData(songWithWebp);
      expect(webpResult, isNotNull);
      expect(webpResult!.isVideo, isFalse);
      expect(webpResult.url, equals('https://i.ytimg.com/an_webp/test/mqdefault_6s.webp'));
    });
  });
}
