import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/hero_card_item.dart';
import 'package:wavify/models/home_data.dart';
import 'package:wavify/models/music_category.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/models/video_item.dart';
import 'package:wavify/services/artwork_cache_service.dart';
import 'package:wavify/services/audio_cache_service.dart';
import 'package:wavify/services/home_cache_service.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/services/song_metrics_cache_service.dart';
import 'package:wavify/widgets/wavify_cached_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeData JSON Serialization & Deserialization Tests', () {
    test(
      'HomeData serializes and deserializes all sections cleanly without loss',
      () {
        const hero = HeroCardItem(
          id: 'hero_1',
          title: 'Top Hits',
          subtitle: 'Apple Music Pop',
          caption: 'Featured',
          imageUrl: 'https://example.com/hero.jpg',
          primaryColor: 0xFFFA243C,
        );

        const song = SongItem(
          id: 'song_1',
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          album: 'After Hours',
          thumbnailUrl: 'https://example.com/song.jpg',
          durationSeconds: 200,
        );

        const mood = MusicCategory(
          title: 'Chill',
          colorValue: 0xFF4A90E2,
          iconName: 'sparkles',
        );

        const album = AlbumItem(
          id: 'album_1',
          title: 'Starboy',
          artist: 'The Weeknd',
          thumbnailUrl: 'https://example.com/starboy.jpg',
          year: 2016,
        );

        const video = VideoItem(
          id: 'video_1',
          title: 'Save Your Tears (Official Video)',
          artist: 'The Weeknd',
          thumbnailUrl: 'https://example.com/video.jpg',
          durationSeconds: 240,
          views: '1.2B views',
        );

        final originalHome = HomeData(
          heroCards: const [hero],
          recents: const [song],
          quickPicks: const [song],
          moods: const [mood],
          genres: const [mood],
          albumsAndSingles: const [album],
          musicVideos: const [video],
          dailyDiscover: const [song],
          trendingSongs: const [song],
        );

        final jsonMap = originalHome.toJson();
        final jsonString = jsonEncode(jsonMap);
        final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
        final restoredHome = HomeData.fromJson(decodedMap);

        expect(restoredHome.heroCards.length, 1);
        expect(restoredHome.heroCards.first.title, 'Top Hits');
        expect(
          restoredHome.heroCards.first.imageUrl,
          'https://example.com/hero.jpg',
        );

        expect(restoredHome.recents.length, 1);
        expect(restoredHome.recents.first.title, 'Blinding Lights');
        expect(restoredHome.recents.first.artist, 'The Weeknd');

        expect(restoredHome.moods.length, 1);
        expect(restoredHome.moods.first.title, 'Chill');
        expect(restoredHome.moods.first.colorValue, 0xFF4A90E2);

        expect(restoredHome.albumsAndSingles.length, 1);
        expect(restoredHome.albumsAndSingles.first.title, 'Starboy');
        expect(restoredHome.albumsAndSingles.first.year, 2016);

        expect(restoredHome.musicVideos.length, 1);
        expect(restoredHome.musicVideos.first.views, '1.2B views');

        expect(restoredHome.isEmpty, isFalse);
      },
    );
  });

  group('HomeCacheService Tests', () {
    test(
      'HomeCacheService caches data in-memory and tracks lastCacheTime',
      () async {
        final cacheService = HomeCacheService.instance;

        const dummySong = SongItem(
          id: 's_test',
          title: 'Test Song',
          artist: 'Test Artist',
        );

        final testHomeData = HomeData(
          heroCards: const [],
          recents: const [dummySong],
          quickPicks: const [dummySong],
          moods: const [],
          albumsAndSingles: const [],
          musicVideos: const [],
          dailyDiscover: const [],
          trendingSongs: const [],
        );

        await cacheService.saveHomeData(testHomeData);

        expect(cacheService.memoryCache, isNotNull);
        expect(cacheService.memoryCache!.recents.length, 1);
        expect(cacheService.memoryCache!.recents.first.title, 'Test Song');
        expect(cacheService.lastCacheTime, isNotNull);
        expect(cacheService.isFresh(ttl: const Duration(minutes: 5)), isTrue);
      },
    );
  });

  group('ArtworkCacheService Tests', () {
    test(
      'ArtworkCacheService tracks play counts and flags songs heard repeatedly',
      () async {
        final artworkCache = ArtworkCacheService.instance;

        const song = SongItem(
          id: 'repeat_track_1',
          title: 'Repeat Song',
          artist: 'Repeat Artist',
          thumbnailUrl: 'https://example.com/repeat.jpg',
        );

        expect(artworkCache.isHeardRepeatedly(song.id), isFalse);
        expect(artworkCache.getPlayCount(song.id), 0);

        // Play once
        await artworkCache.recordSongPlay(song);
        expect(artworkCache.getPlayCount(song.id), 1);
        expect(artworkCache.isHeardRepeatedly(song.id), isFalse);

        // Play twice -> now heard repeatedly!
        await artworkCache.recordSongPlay(song);
        expect(artworkCache.getPlayCount(song.id), 2);
        expect(artworkCache.isHeardRepeatedly(song.id), isTrue);

        final frequentIds = artworkCache.getFrequentlyHeardSongIds();
        expect(frequentIds.contains('repeat_track_1'), isTrue);
      },
    );
  });

  group('AudioCacheService Tests', () {
    test(
      'AudioCacheService creates fallback AudioSource when not cached',
      () async {
        final audioCache = AudioCacheService.instance;

        final source = await audioCache.createAudioSource(
          'stream_song_1',
          'https://example.com/audio_test.mp3',
          {'User-Agent': 'WavifyTestAgent'},
        );

        expect(source, isNotNull);
        expect(source, isA<AudioSource>());
      },
    );
  });

  group('WavifyCachedImage Widget Tests', () {
    testWidgets(
      'WavifyCachedImage renders fallback gracefully when imageUrl is null',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: WavifyCachedImage(imageUrl: null, width: 50, height: 50),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.music_note), findsOneWidget);
      },
    );

    testWidgets(
      'WavifyCachedImage renders network image when given valid URL and placeholderImageUrl',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: WavifyCachedImage(
                imageUrl: 'https://example.com/artwork_highres.jpg',
                placeholderImageUrl: 'https://example.com/thumb.jpg',
                songId: 'song_art_test',
                width: 60,
                height: 60,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(WavifyCachedImage), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      },
    );
  });

  group('SongMetricsCacheService Tests', () {
    test('Stores and retrieves song duration accurately in memory and persistent cache', () async {
      final cache = SongMetricsCacheService.instance;
      await cache.clear();

      expect(cache.getDuration('song_metric_1'), isNull);

      await cache.setDuration('song_metric_1', 215);
      expect(cache.getDuration('song_metric_1'), const Duration(seconds: 215));

      // Overwriting updates value
      await cache.setDuration('song_metric_1', 220);
      expect(cache.getDuration('song_metric_1'), const Duration(seconds: 220));

      await cache.clear();
      expect(cache.getDuration('song_metric_1'), isNull);
    });

    test('AudioStreamInfo exposes durationMs and durationSeconds', () {
      const info = AudioStreamInfo(
        url: 'https://example.com/stream.mp4',
        headers: {},
        bitrate: 128000,
        mimeType: 'audio/mp4',
        durationMs: 185000,
      );

      expect(info.durationMs, 185000);
      expect(info.durationSeconds, 185);
    });
  });
}
