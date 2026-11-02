import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/artist_item.dart';
import 'package:wavify/models/playlist_item.dart';
import 'package:wavify/models/recent_search_item.dart';
import 'package:wavify/models/search_result_set.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/models/video_item.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/search_provider.dart';
import 'package:wavify/screens/search_screen.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/wavify_cached_image.dart';

class MockMusicService extends Fake implements MusicService {
  @override
  Future<SearchResultSet> searchAll(String query) async {
    return const SearchResultSet(
      songs: [
        SongItem(
          id: 'test_song_1',
          title: 'YAH YAH',
          artist: 'Tsumyoki',
          durationSeconds: 188,
        ),
        SongItem(
          id: 'test_song_2',
          title: 'India Type Shiz (Explicit)',
          artist: 'Tsumyoki',
          durationSeconds: 154,
        ),
      ],
      artists: [
        ArtistItem(
          id: 'test_artist_1',
          name: 'Tsumyoki',
          subscribers: '256K monthly audience',
        ),
      ],
      albums: [
        AlbumItem(
          id: 'test_album_1',
          title: 'AFRO YOKI',
          artist: 'Tsumyoki',
          year: 2026,
        ),
      ],
      playlists: [
        PlaylistItem(
          id: 'test_playlist_1',
          title: 'Mix - Tsumyoki',
          author: 'azbeachguy',
        ),
      ],
      videos: [
        VideoItem(
          id: 'test_video_1',
          title: 'OKTOBER FEST GOA 2025',
          artist: 'Travel Goa With Sandeep',
          durationSeconds: 241,
        ),
      ],
    );
  }
}

class MockCountingMusicService extends Fake implements MusicService {
  final VoidCallback onSearch;
  MockCountingMusicService(this.onSearch);

  @override
  Future<SearchResultSet> searchAll(String query) async {
    onSearch();
    return const SearchResultSet(
      songs: [
        SongItem(
          id: 'test_song_1',
          title: 'Cached Song',
          artist: 'Cached Artist',
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RecentSearchNotifier Unit Tests', () {
    test('initially empty and adds recent items with deduplication', () async {
      final notifier = RecentSearchNotifier();
      expect(notifier.state, isEmpty);

      const item1 = RecentSearchItem(
        id: 'artist_1',
        title: 'Tsumyoki',
        subtitle: 'Artist • 256K monthly audience',
        type: RecentSearchType.artist,
        timestamp: 100,
      );

      await notifier.addRecent(item1);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.title, 'Tsumyoki');

      // Adding duplicate title moves it to front
      const item1Dup = RecentSearchItem(
        id: 'artist_1_new',
        title: 'Tsumyoki',
        subtitle: 'Artist • 256K monthly audience',
        type: RecentSearchType.artist,
        timestamp: 200,
      );

      await notifier.addRecent(item1Dup);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 'artist_1_new');

      // Add another item
      const item2 = RecentSearchItem(
        id: 'song_1',
        title: 'idfc',
        subtitle: 'blackbear',
        type: RecentSearchType.song,
        timestamp: 300,
      );

      await notifier.addRecent(item2);
      expect(notifier.state.length, 2);
      expect(notifier.state.first.title, 'idfc');
      expect(notifier.state[1].title, 'Tsumyoki');

      // Remove single item
      await notifier.removeRecent('song_1');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.title, 'Tsumyoki');

      // Clear all
      await notifier.clearAll();
      expect(notifier.state, isEmpty);
    });
  });

  group('SearchNotifier Unit Tests', () {
    test('category changes update state properly', () {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchProvider.notifier);
      expect(container.read(searchProvider).selectedCategory, 'All');

      notifier.setCategory('Videos');
      expect(container.read(searchProvider).selectedCategory, 'Videos');

      notifier.setCategory('Songs');
      expect(container.read(searchProvider).selectedCategory, 'Songs');
    });

    test('search populates bundled results and memory cache', () async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchProvider.notifier);
      await notifier.search('tsumyoki');

      final state = container.read(searchProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasSearched, isTrue);
      expect(state.query, 'tsumyoki');
      expect(state.results.songs.length, 2);
      expect(state.results.artists.length, 1);
      expect(state.results.albums.length, 1);
      expect(state.results.playlists.length, 1);
      expect(state.results.videos.length, 1);
    });

    test('memory cache serves repeated queries immediately without network calls', () async {
      int apiCallCount = 0;
      final countingService = MockCountingMusicService(() => apiCallCount++);
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(countingService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchProvider.notifier);
      await notifier.search('tsumyoki');
      expect(apiCallCount, 1);

      // Search again with same query (different case)
      await notifier.search('TSUMYOKI');
      expect(apiCallCount, 1); // Served directly from memory cache!
      expect(container.read(searchProvider).results.songs.first.title, 'Cached Song');
    });
  });

  group('SearchScreen Widget Tests', () {
    testWidgets('renders liquid glass search bar and profile avatar',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicServiceProvider.overrideWithValue(MockMusicService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SearchScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search bar placeholder
      expect(find.text('Artists, Songs, Lyrics and More'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.search), findsNWidgets(2));
      expect(find.text('Search Millions of Songs'), findsOneWidget);

      // Top right profile avatar button
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows recent searches with Clear button and item x button',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      // Preload recent search item
      await container.read(recentSearchProvider.notifier).addRecent(
            const RecentSearchItem(
              id: 'rec_1',
              title: 'Tsumyoki',
              subtitle: 'Artist • 256K monthly audience',
              type: RecentSearchType.artist,
              timestamp: 100,
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SearchScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Tsumyoki'), findsOneWidget);
      expect(find.text('Artist • 256K monthly audience'), findsOneWidget);

      // Tapping "Clear" removes recent searches
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Tsumyoki'), findsNothing);
      expect(find.text('Search Millions of Songs'), findsOneWidget);
    });

    testWidgets('typing triggers debounced search and renders capsule filters',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicServiceProvider.overrideWithValue(MockMusicService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SearchScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search text
      await tester.enterText(find.byType(TextField), 'tsumyoki');
      await tester.pump();

      // Fast forward past 380ms debouncer
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Filter capsules appear
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Songs'), findsWidgets);
      expect(find.text('Videos'), findsWidgets);
      expect(find.text('Albums'), findsWidgets);
      expect(find.text('Artists'), findsWidgets);
      expect(find.text('Playlists'), findsWidgets);

      // Songs results rendered with clean title and [E] badge
      expect(find.text('YAH YAH'), findsOneWidget);
      expect(find.text('India Type Shiz'), findsOneWidget);
      expect(find.text('E'), findsOneWidget); // Explicit badge

      // Tapping Videos capsule switches to Videos view
      await tester.tap(find.text('Videos').first);
      await tester.pumpAndSettle();

      // Full 16:9 video item is displayed
      expect(find.text('OKTOBER FEST GOA 2025'), findsOneWidget);
      expect(find.text('Travel Goa With Sandeep'), findsOneWidget);
    });

    testWidgets('switching between tabs maintains IndexedStack and WavifyCachedImage across categories',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicServiceProvider.overrideWithValue(MockMusicService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SearchScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search text and settle
      await tester.enterText(find.byType(TextField), 'tsumyoki');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Verify IndexedStack is present to preserve views & image caches
      expect(find.byType(IndexedStack), findsOneWidget);

      // Verify WavifyCachedImage is used for rendering artworks
      expect(find.byType(WavifyCachedImage), findsWidgets);

      // Switch to Songs tab
      await tester.tap(find.text('Songs').first);
      await tester.pumpAndSettle();
      expect(find.text('YAH YAH'), findsOneWidget);

      // Switch to Artists tab
      await tester.tap(find.text('Artists').first);
      await tester.pumpAndSettle();
      expect(find.text('Tsumyoki'), findsWidgets);

      // Switch back to Songs tab: instantaneously visible without reloading
      await tester.tap(find.text('Songs').first);
      await tester.pumpAndSettle();
      expect(find.text('YAH YAH'), findsOneWidget);
      expect(find.byType(WavifyCachedImage), findsWidgets);
    });
  });
}
