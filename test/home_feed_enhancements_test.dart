import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/hero_card_item.dart';
import 'package:wavify/models/home_data.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/home_data_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/home_screen.dart';
import 'package:wavify/services/home_cache_service.dart';
import 'package:wavify/services/player_history_cache_service.dart';

class _MockHomeDataNotifier extends HomeDataNotifier {
  final HomeData mockData;
  _MockHomeDataNotifier(this.mockData);

  @override
  Future<HomeData> build() async => mockData;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerHistoryCacheService.instance.resetForTesting();
  });

  group('Home Feed & Recents Enhancements Tests', () {
    test('Playing a song immediately moves it to index 0 in recentlyPlayed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const songA = SongItem(id: 's_a', title: 'Song Alpha', artist: 'Artist A');
      const songB = SongItem(id: 's_b', title: 'Song Beta', artist: 'Artist B');
      const songC = SongItem(id: 's_c', title: 'Song Gamma', artist: 'Artist C');

      final notifier = container.read(playerProvider.notifier);

      notifier.playSong(songA);
      expect(container.read(playerProvider).recentlyPlayed.first.id, equals('s_a'));

      notifier.playSong(songB);
      expect(container.read(playerProvider).recentlyPlayed.first.id, equals('s_b'));
      expect(container.read(playerProvider).recentlyPlayed[1].id, equals('s_a'));

      // Replaying songA should immediately bring it back to index 0 without duplicating
      notifier.playSong(songA, forceReload: true);
      expect(container.read(playerProvider).recentlyPlayed.first.id, equals('s_a'));
      expect(container.read(playerProvider).recentlyPlayed[1].id, equals('s_b'));
      expect(container.read(playerProvider).recentlyPlayed.length, equals(2));

      notifier.playSong(songC);
      expect(container.read(playerProvider).recentlyPlayed.first.id, equals('s_c'));
      expect(container.read(playerProvider).recentlyPlayed[1].id, equals('s_a'));
      expect(container.read(playerProvider).recentlyPlayed[2].id, equals('s_b'));
    });

    testWidgets('Recents on Home screen immediately updates with the played song at top',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const newlyPlayed = SongItem(
        id: 'new_1',
        title: 'Freshly Listened',
        artist: 'Fresh Artist',
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Play a song via PlayerNotifier
      container.read(playerProvider.notifier).playSong(newlyPlayed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The newly played song must immediately appear in the UI
      expect(find.text('Freshly Listened'), findsWidgets);
      expect(find.text('Fresh Artist'), findsWidgets);
    });

    testWidgets('Top Picks Hero Card with Album opens AlbumScreen accurately',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const testAlbum = AlbumItem(
        id: 'album_xyz',
        title: 'Chromakopia',
        artist: 'Tyler, The Creator',
        type: 'Album',
      );

      const heroAlbum = HeroCardItem(
        id: 'hero_chromakopia',
        title: 'Chromakopia',
        subtitle: 'New from Tyler, The Creator',
        caption: 'Album • 2024',
        album: testAlbum,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeDataProvider.overrideWith(
              () => _MockHomeDataNotifier(
                const HomeData(
                  heroCards: [heroAlbum],
                  recents: [],
                  quickPicks: [],
                  moods: [],
                  albumsAndSingles: [],
                  musicVideos: [],
                  dailyDiscover: [],
                  trendingSongs: [],
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Chromakopia'), findsOneWidget);

      // Tap the hero card
      await tester.tap(find.text('Chromakopia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Must open AlbumScreen for the exact album
      expect(find.byType(AlbumScreen), findsOneWidget);
    });

    test('HomeCacheService sanitizes and preserves all dynamic and personalized sections', () async {
      const album = AlbumItem(id: 'alb_1', title: 'Hit Me Hard', artist: 'Billie Eilish');
      const song = SongItem(id: 's_1', title: 'Birds of a Feather', artist: 'Billie Eilish');
      final dynamicSec = HomeSectionData(
        id: 'sec_1',
        title: 'More from Billie',
        layout: HomeSectionLayout.songColumns,
        songs: [song],
      );

      final data = HomeData(
        heroCards: const [],
        recents: const [song],
        quickPicks: const [song],
        moods: const [],
        albumsAndSingles: const [album],
        musicVideos: const [],
        dailyDiscover: const [song],
        trendingSongs: const [song],
        dynamicSections: [dynamicSec],
        followedArtistNewReleases: const [album],
      );

      await HomeCacheService.instance.saveHomeData(data);
      final loaded = await HomeCacheService.instance.loadHomeData();

      expect(loaded, isNotNull);
      expect(loaded!.dynamicSections.length, equals(1));
      expect(loaded.dynamicSections.first.title, equals('More from Billie'));
      expect(loaded.followedArtistNewReleases.length, equals(1));
    });
  });
}
