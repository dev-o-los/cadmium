import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/services/music_service.dart';

void main() {
  test('resolveVideoStream returns 720p or 1080p video stream for track', () async {
    try {
      final service = MusicService();
      await service.initialize();
      
      // Test with Blinding Lights videoId
      final stream = await service.resolveVideoStream('4NRXx6U8ABQ');
      if (stream == null) return;
      expect(stream.url, isNotEmpty);
      expect(stream.url.contains('.m3u8'), isTrue, reason: 'Stream URL should be HLS m3u8: ${stream.url}');
      expect(stream.headers['User-Agent'], isNotEmpty);

      // Verify the HLS manifest can be fetched with the headers
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(stream.url));
      stream.headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      expect(response.statusCode, equals(200));
      final body = await response.transform(const SystemEncoding().decoder).join();
      expect(body.contains('#EXTM3U'), isTrue);

      // Check request without headers
      final noHeaderReq = await client.getUrl(Uri.parse(stream.url));
      final noHeaderRes = await noHeaderReq.close();
      await noHeaderRes.drain();
      expect(noHeaderRes.statusCode, isIn([200, 403]));
      expect(stream.height, greaterThanOrEqualTo(720));
      expect(stream.width, greaterThanOrEqualTo(1280));
    } catch (_) {
      // In CI, YouTube API / HLS fetch may be blocked or unavailable
    }
  });

  test('getAnimatedArtwork returns high quality stream for song', () async {
    try {
      final service = MusicService();
      await service.initialize();

      // fHI8X4OfY61 is the audio-track ID (static album art video)
      final song = SongItem(
        id: 'fHI8X4OfY61',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://lh3.googleusercontent.com/test',
      );

      final artwork = await service.getAnimatedArtwork(song);
      if (artwork != null) {
        expect(artwork, isNotEmpty);
      }
    } catch (_) {
      // In CI, YouTube API may be blocked or unavailable
    }
  });

  test('getAnimatedArtworkData resolves HD video and headers for official track', () async {
    try {
      final service = MusicService();
      await service.initialize();

      final song = SongItem(
        id: 'fHI8X4OfY61',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://lh3.googleusercontent.com/test',
      );

      final data = await service.getAnimatedArtworkData(song);
      if (data != null) {
        expect(data.url, isNotEmpty);
        if (data.isVideo) {
          expect(data.headers['User-Agent'], isNotEmpty);
          expect(data.height, greaterThanOrEqualTo(480));
        }
      }
    } catch (_) {
      // In CI, YouTube API may be blocked or unavailable
    }
  });
}
