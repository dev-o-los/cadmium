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

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    return ['tsumyoki live', 'tsumyoki hits'];
  }

  @override
  Future<List<SongItem>> searchSongs(String query) async {
    return [
      const SongItem(
        id: 'test_song_more_1',
        title: 'More Song 1',
        artist: 'Tsumyoki',
      ),
    ];
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

      // Verify video thumbnail passes resolvedThumbnailUrl and songId to WavifyCachedImage
      final videoImageFinder = find.byWidgetPredicate(
        (widget) =>
            widget is WavifyCachedImage &&
            widget.songId == 'test_video_1' &&
            widget.imageUrl == 'https://i.ytimg.com/vi/test_video_1/hqdefault.jpg',
      );
      expect(videoImageFinder, findsOneWidget);
    });

    test('VideoItem thumbnail resolution fallbacks and upgrades', () {
      // 1. Without thumbnail, resolves guaranteed YouTube static endpoint
      const videoWithoutThumb = VideoItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
      );
      expect(
        videoWithoutThumb.resolvedThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      expect(
        videoWithoutThumb.highResThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );

      // 2. Protocol-relative thumbnail prepends https:
      const videoWithProtoRelative = VideoItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        thumbnailUrl: '//i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
      );
      expect(
        videoWithProtoRelative.resolvedThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
      );
      expect(
        videoWithProtoRelative.highResThumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );
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

    test('Fast thumbnail optimization and edge CDN URL resolution', () {
      // 1. Google User Content album artwork upgrades to official edge-cached =w544-h544-l90-rj
      final albumUrl = SongItem.upgradeThumbnail(
        'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
      );
      expect(albumUrl, 'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj');

      // 2. Standard YouTube video thumbnail preserves hqdefault (guaranteed instant 20ms load)
      final ytUrl = SongItem.upgradeThumbnail(
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      expect(ytUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');

      // 3. AlbumItem resolves protocol-relative URLs cleanly
      const albumItem = AlbumItem(
        id: 'MPREb_test',
        title: 'Test Album',
        artist: 'Artist',
        thumbnailUrl: '//lh3.googleusercontent.com/album_art=w120-h120',
      );
      expect(
        albumItem.resolvedThumbnailUrl,
        'https://lh3.googleusercontent.com/album_art=w120-h120',
      );
    });

    testWidgets('clearing search input restores Recent Searches view and hides pill bar',
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

      // Search results are visible
      expect(find.text('YAH YAH'), findsOneWidget);
      expect(find.text('Songs'), findsWidgets);

      // Now clear search text completely (empty string)
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Verify Recent Searches view is restored immediately
      expect(find.text('YAH YAH'), findsNothing);
      expect(find.text('No results found for ""'), findsNothing);
    });

    test('SearchNotifier infinite scrolling loadMore fetches related queries', () async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchProvider.notifier);
      await notifier.search('tsumyoki');

      final initialSongs = container.read(searchProvider).results.songs.length;
      expect(initialSongs, 2);

      // Switch to Songs category and trigger loadMore
      notifier.setCategory('Songs');
      await notifier.loadMore();

      final updatedSongs = container.read(searchProvider).results.songs.length;
      expect(updatedSongs, greaterThan(initialSongs));
      expect(container.read(searchProvider).results.songs.any((s) => s.id == 'test_song_more_1'), isTrue);
    });

    testWidgets('renders proper spacing and font sizes for mobile screens',
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
      await tester.enterText(find.byType(TextField), 'tsumyoki');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Check title track text style
      final titleWidget = tester.widget<Text>(find.text('YAH YAH'));
      expect(titleWidget.style?.fontSize, 15.0);
      expect(titleWidget.style?.fontWeight, FontWeight.w500);

      // Check artist text style
      final artistWidget = tester.widget<Text>(find.text('Tsumyoki').first);
      expect(artistWidget.style?.fontSize, 13.0);
      expect(artistWidget.style?.fontWeight, FontWeight.w400);
    });
  });
}
