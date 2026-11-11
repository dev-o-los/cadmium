import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/services/music_service.dart';

class MockMusicService extends MusicService {
  @override
  Future<AudioStreamInfo> resolveAudioStream(
    String videoId, {
    bool forceRefresh = false,
  }) async {
    return const AudioStreamInfo(
      url: 'https://example.com/audio.mp3',
      headers: {},
      bitrate: 128000,
      mimeType: 'audio/mp4',
    );
  }

  @override
  Future<List<LyricLine>> getLyrics(
    String videoId, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
  }) async => const [];

  @override
  Future<List<SongItem>> getSongRadio(
    String videoId, {
    String? artist,
    String? title,
  }) async => const [];
}

void main() {
  group('Player Queue & Navigation Tests', () {
    const track1 = SongItem(id: 't1', title: 'Track 1', artist: 'Artist');
    const track2 = SongItem(id: 't2', title: 'Track 2', artist: 'Artist');
    const track3 = SongItem(id: 't3', title: 'Track 3', artist: 'Artist');
    const allAlbumTracks = [track1, track2, track3];

    testWidgets('Navigating Next and Previous in an album works like Apple Music', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      // Start playing Track 1 with remaining tracks in queue
      notifier.state = const PlayerStateModel(
        currentSong: track1,
        isPlaying: true,
        queue: [track2, track3],
        history: [],
        originalQueue: allAlbumTracks,
        position: Duration.zero,
      );

      // Press Next -> Track 2
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t2'));
      expect(container.read(playerProvider).queue.map((s) => s.id), equals(['t3']));
      expect(container.read(playerProvider).history.map((s) => s.id), equals(['t1']));

      // Press Next -> Track 3
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t3'));
      expect(container.read(playerProvider).queue, isEmpty);
      expect(container.read(playerProvider).history.map((s) => s.id), equals(['t1', 't2']));

      // If position >= 3s, skipPrevious restarts track
      notifier.state = notifier.state.copyWith(position: const Duration(seconds: 15));
      notifier.skipPrevious();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t3'));

      // If position < 3s, skipPrevious goes back to Track 2 and puts Track 3 in queue
      notifier.state = notifier.state.copyWith(position: const Duration(seconds: 1));
      notifier.skipPrevious();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t2'));
      expect(container.read(playerProvider).queue.map((s) => s.id), equals(['t3']));
      expect(container.read(playerProvider).history.map((s) => s.id), equals(['t1']));

      // Pressing Next goes back to Track 3
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t3'));
      expect(container.read(playerProvider).queue, isEmpty);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Repeat-All loops the entire album when queue ends', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      notifier.state = const PlayerStateModel(
        currentSong: track3,
        isPlaying: true,
        queue: [],
        history: [track1, track2],
        originalQueue: allAlbumTracks,
        loopMode: LoopMode.all,
      );

      // Next at the end of album with LoopMode.all restarts Track 1
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t1'));
      expect(container.read(playerProvider).queue.map((s) => s.id), equals(['t2', 't3']));

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Repeat-One repeats current track on skipNext', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      notifier.state = const PlayerStateModel(
        currentSong: track2,
        isPlaying: true,
        queue: [track3],
        history: [track1],
        loopMode: LoopMode.one,
      );

      notifier.skipNext();
      await tester.pump();
      // Still on Track 2
      expect(container.read(playerProvider).currentSong?.id, equals('t2'));
      expect(container.read(playerProvider).queue.map((s) => s.id), equals(['t3']));

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Autoplay OFF stops playback when queue ends and does NOT loop recentlyPlayed', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      notifier.state = const PlayerStateModel(
        currentSong: track1,
        isPlaying: true,
        queue: [],
        history: [],
        isAutoplay: false, // Autoplay OFF
        recentlyPlayed: [track1, track2, track3],
      );

      notifier.skipNext();
      await tester.pump();
      // Should stop playing!
      expect(container.read(playerProvider).isPlaying, isFalse);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Autoplay ON continues with autoplay recommendations when queue ends', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      const radioSong = SongItem(id: 'radio_1', title: 'Radio Track', artist: 'Similar Artist');

      notifier.state = const PlayerStateModel(
        currentSong: track1,
        isPlaying: true,
        queue: [],
        history: [],
        isAutoplay: true,
        autoplayQueue: [radioSong],
      );

      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('radio_1'));
      expect(container.read(playerProvider).history.map((s) => s.id), equals(['t1']));

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Toggling shuffle scrambles queue and toggling off restores original order', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      final songs = List.generate(
        10,
        (i) => SongItem(id: 's_$i', title: 'Song $i', artist: 'Artist'),
      );

      notifier.state = PlayerStateModel(
        currentSong: songs[0],
        isPlaying: true,
        queue: songs.sublist(1),
        originalQueue: songs,
        isShuffle: false,
      );

      // Toggle shuffle ON
      notifier.toggleShuffle();
      expect(container.read(playerProvider).isShuffle, isTrue);

      // Toggle shuffle OFF -> queue order matches original tracklist order
      notifier.toggleShuffle();
      expect(container.read(playerProvider).isShuffle, isFalse);
      expect(container.read(playerProvider).queue.map((s) => s.id), equals(songs.sublist(1).map((s) => s.id)));
    });

    testWidgets('Turning Autoplay OFF removes all items from autoplay and does not play similar songs', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      const radioSong = SongItem(id: 'radio_1', title: 'Radio Track', artist: 'Similar Artist');

      notifier.state = const PlayerStateModel(
        currentSong: track1,
        isPlaying: true,
        queue: [],
        history: [],
        isAutoplay: true,
        autoplayQueue: [radioSong],
      );

      // Turn Autoplay OFF via toggleAutoplay
      notifier.toggleAutoplay();
      expect(container.read(playerProvider).isAutoplay, isFalse);
      // Items must be completely removed from autoplay
      expect(container.read(playerProvider).autoplayQueue, isEmpty);

      // skipNext must stop and NOT play similar songs
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).isPlaying, isFalse);
      expect(container.read(playerProvider).currentSong?.id, equals('t1'));

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Loop mode cycle: off -> all -> one -> off, and loops queue vs repeating same song', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      final notifier = container.read(playerProvider.notifier);

      notifier.state = const PlayerStateModel(
        currentSong: track1,
        isPlaying: true,
        queue: [track2],
        history: [],
        originalQueue: [track1, track2],
        loopMode: LoopMode.off,
      );

      // Cycle 1: off -> all
      notifier.cycleLoopMode();
      expect(container.read(playerProvider).loopMode, equals(LoopMode.all));

      // With LoopMode.all, playing next advances through queue
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t2'));
      expect(container.read(playerProvider).queue, isEmpty);

      // Next at end of queue with LoopMode.all loops back to queue track 1
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t1'));

      // Cycle 2: all -> one (repeat same song)
      notifier.cycleLoopMode();
      expect(container.read(playerProvider).loopMode, equals(LoopMode.one));

      // With LoopMode.one, skipNext repeats the SAME track
      notifier.skipNext();
      await tester.pump();
      expect(container.read(playerProvider).currentSong?.id, equals('t1'));

      // Cycle 3: one -> off
      notifier.cycleLoopMode();
      expect(container.read(playerProvider).loopMode, equals(LoopMode.off));

      notifier.pause();
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
