import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/services/music_service.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  group('MusicService Integration Tests', () {
    late MusicService musicService;

    setUp(() {
      musicService = MusicService();
    });

    tearDown(() {
      musicService.dispose();
    });

    test('searchSongs returns relevant tracks', () async {
      final results = await musicService.searchSongs('Attention Charlie Puth');
      expect(results, isNotEmpty);

      final firstTrack = results.first;
      expect(firstTrack.id, isNotEmpty);
      expect(firstTrack.title, isNotEmpty);
      expect(firstTrack.artist.toLowerCase(), contains('charlie puth'));
    });

    test('getHomeData returns heroCards, recents, quickPicks, moods, albums, and videos', () async {
      final homeData = await musicService.getHomeData();
      expect(homeData.heroCards, isNotEmpty);
      expect(homeData.recents, isNotEmpty);
      expect(homeData.quickPicks, isNotEmpty);
      expect(homeData.moods, isNotEmpty);
      expect(homeData.genres, isNotEmpty);
      expect(homeData.albumsAndSingles, isNotEmpty);
      expect(homeData.musicVideos, isNotEmpty);
      expect(homeData.trendingSongs, isNotEmpty);
    });

    test('resolveAudioStream returns working stream info with headers', () async {
      // 1. Search for Attention
      final results = await musicService.searchSongs('Attention Charlie Puth');
      expect(results, isNotEmpty);
      final videoId = results.first.id;

      // 2. Resolve audio stream
      final streamInfo = await musicService.resolveAudioStream(videoId);
      expect(streamInfo.url, isNotEmpty);
      expect(streamInfo.url, startsWith('http'));
      expect(streamInfo.headers, contains('User-Agent'));
      expect(streamInfo.bitrate, greaterThan(0));
      expect(streamInfo.mimeType, contains('audio/'));
    });
  });
}
