import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/widgets/player_controls.dart';
import 'package:wavify/widgets/wavify_cached_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SongItem Artwork & Thumbnail Resolution Tests', () {
    test('resolvedThumbnailUrl returns explicit thumbnailUrl when present', () {
      const song = SongItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        thumbnailUrl: 'https://lh3.googleusercontent.com/test_art=w120-h120',
      );

      expect(
        song.resolvedThumbnailUrl,
        'https://lh3.googleusercontent.com/test_art=w120-h120',
      );
    });

    test('resolvedThumbnailUrl falls back to YouTube hqdefault when thumbnailUrl is null or empty', () {
      const songWithoutThumb = SongItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        thumbnailUrl: null,
      );

      expect(
        songWithoutThumb.resolvedThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );

      const songWithEmptyThumb = SongItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        thumbnailUrl: '   ',
      );

      expect(
        songWithEmptyThumb.resolvedThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('resolvedThumbnailUrl does not synthesize YouTube URL for local/non-YouTube IDs', () {
      const localSong = SongItem(
        id: 'local_file_123',
        title: 'Local Audio',
        artist: 'Me',
        thumbnailUrl: null,
      );

      expect(localSong.resolvedThumbnailUrl, isNull);
    });

    test(
      'highResThumbnailUrl upgrades Google User Content and YouTube URLs',
      () {
        const gSong = SongItem(
          id: 'song_1',
          title: 'Track',
          artist: 'Artist',
          thumbnailUrl:
              'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
        );

        expect(
          gSong.highResThumbnailUrl,
          'https://lh3.googleusercontent.com/abc=w800-h800-l95-rj',
        );

        const ytSong = SongItem(
          id: 'dQw4w9WgXcQ',
          title: 'Track',
          artist: 'Artist',
          thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        );

        expect(
          ytSong.highResThumbnailUrl,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
        );
      },
    );
  });

  group('WavifyCachedImage Candidate Cascade Tests', () {
    test(
      'buildCandidates builds full resolution cascade for YouTube thumbnails',
      () {
        final candidates = WavifyCachedImage.buildCandidates(
          imageUrl: 'https://i.ytimg.com/vi/abc12345678/maxresdefault.jpg',
          placeholderImageUrl:
              'https://i.ytimg.com/vi/abc12345678/hqdefault.jpg',
          songId: 'abc12345678',
        );

        expect(
          candidates,
          contains('https://i.ytimg.com/vi/abc12345678/maxresdefault.jpg'),
        );
        expect(
          candidates,
          contains('https://i.ytimg.com/vi/abc12345678/sddefault.jpg'),
        );
        expect(
          candidates,
          contains('https://i.ytimg.com/vi/abc12345678/hqdefault.jpg'),
        );
        expect(
          candidates,
          contains('https://i.ytimg.com/vi/abc12345678/mqdefault.jpg'),
        );
        // Candidate 0 is maxresdefault, with sddefault and guaranteed hqdefault in chain
        expect(
          candidates.first,
          'https://i.ytimg.com/vi/abc12345678/maxresdefault.jpg',
        );
        expect(
          candidates[1],
          'https://i.ytimg.com/vi/abc12345678/sddefault.jpg',
        );
        expect(
          candidates[2],
          'https://i.ytimg.com/vi/abc12345678/hqdefault.jpg',
        );
      },
    );

    test('buildCandidates builds fallback chain for Google User Content', () {
      final candidates = WavifyCachedImage.buildCandidates(
        imageUrl: 'https://lh3.googleusercontent.com/art123=w800-h800-l95-rj',
        songId: 'song_yt_id',
      );

      expect(
        candidates,
        contains('https://lh3.googleusercontent.com/art123=w800-h800-l95-rj'),
      );
      expect(
        candidates,
        contains('https://lh3.googleusercontent.com/art123=w544-h544-l90-rj'),
      );
      expect(candidates, contains('https://lh3.googleusercontent.com/art123'));
      expect(
        candidates,
        contains('https://i.ytimg.com/vi/song_yt_id/hqdefault.jpg'),
      );
    });

    test(
      'buildCandidates falls back to YouTube video ID when imageUrl is null',
      () {
        final candidates = WavifyCachedImage.buildCandidates(
          imageUrl: null,
          placeholderImageUrl: null,
          songId: 'videoIdXYZ1',
        );

        expect(
          candidates.first,
          'https://i.ytimg.com/vi/videoIdXYZ1/hqdefault.jpg',
        );
        expect(
          candidates,
          contains('https://i.ytimg.com/vi/videoIdXYZ1/mqdefault.jpg'),
        );
      },
    );

    testWidgets(
      'WavifyCachedImage automatically renders YouTube candidate when imageUrl is null but songId is present',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: WavifyCachedImage(
                imageUrl: null,
                songId: 'dQw4w9WgXcQ',
                width: 50,
                height: 50,
              ),
            ),
          ),
        );
        await tester.pump();

        // Should render network image candidate cascade starting with YouTube hqdefault
        expect(find.byType(WavifyCachedImage), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      },
    );
  });

  group('PlayerControls Artwork Continuity Tests', () {
    testWidgets(
      'PlayerControls displays album art even when song thumbnailUrl is null',
      (tester) async {
        const songWithoutThumb = SongItem(
          id: 'dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          thumbnailUrl: null,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerProvider.overrideWith((ref) {
                final notifier = PlayerNotifier(ref);
                notifier.state = notifier.state.copyWith(
                  currentSong: songWithoutThumb,
                  isPlaying: false,
                  duration: const Duration(seconds: 213),
                );
                return notifier;
              }),
            ],
            child: const MaterialApp(home: Scaffold(body: PlayerControls())),
          ),
        );
        await tester.pumpAndSettle();

        // Artwork widget is rendered using WavifyCachedImage and fallback cascade
        expect(find.byType(WavifyCachedImage), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      },
    );
  });
}
