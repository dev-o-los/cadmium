import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/artist_details.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/screens/album_screen.dart';
import 'package:wavify/screens/artist_screen.dart';
import 'package:wavify/screens/library_screen.dart';
import 'package:wavify/services/music_service.dart';

class MockArtistMusicService extends MusicService {
  final ArtistDetails details;

  MockArtistMusicService(this.details);

  @override
  Future<ArtistDetails> getArtistDetails(
    String artistIdOrName, {
    String? fallbackName,
  }) async {
    return details;
  }

  @override
  Future<List<SongItem>> getLikedSongs() async {
    return [
      const SongItem(id: 'liked_1', title: 'Hold Up', artist: 'Kunwarr', durationSeconds: 180),
      const SongItem(id: 'liked_2', title: 'Starboy', artist: 'The Weeknd', durationSeconds: 230),
    ];
  }

  @override
  Future<AlbumDetails> getAlbumDetails(
    AlbumItem initialAlbum, {
    String? queryFallback,
  }) async {
    return AlbumDetails(
      album: initialAlbum,
      tracks: [
        const SongItem(
          id: 'liked_1',
          title: 'Hold Up',
          artist: 'Kunwarr',
          durationSeconds: 180,
        ),
        const SongItem(
          id: 'liked_2',
          title: 'Starboy',
          artist: 'The Weeknd',
          durationSeconds: 230,
        ),
      ],
      totalDurationSeconds: 410,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Artist & Title Sanitization Tests', () {
    test('SongItem.sanitizeArtist correctly parses "Hold Up by Kunwarr" and variations', () {
      expect(SongItem.sanitizeArtist('Hold Up by Kunwarr'), equals('Kunwarr'));
      expect(SongItem.sanitizeArtist('hold up by kunwarr'), equals('kunwarr'));
      expect(SongItem.sanitizeArtist('Hold Up by Kunawarr'), equals('Kunawarr'));
      expect(SongItem.sanitizeArtist('hold up by kunawarr'), equals('kunawarr'));
      expect(
        SongItem.sanitizeArtist('Play Hold Up by Kunwarr'),
        equals('Kunwarr'),
      );
      expect(SongItem.sanitizeArtist('by Kunwarr'), equals('Kunwarr'));
      expect(SongItem.sanitizeArtist('by kunwarr'), equals('kunwarr'));
      expect(SongItem.sanitizeArtist('Kunwarr - Topic'), equals('Kunwarr'));
      expect(
        SongItem.sanitizeArtist('Song • Kunwarr • 2:45'),
        equals('Kunwarr'),
      );
      expect(
        SongItem.sanitizeArtist('Video • Kunwarr • 10M views'),
        equals('Kunwarr'),
      );
      expect(
        SongItem.sanitizeArtist('Kunwarr • 1.2M views'),
        equals('Kunwarr'),
      );
      expect(SongItem.sanitizeArtist('Kunwarr'), equals('Kunwarr'));
    });

    test('SongItem.sanitizeTitle correctly parses titles with "Play " and "by [Artist]"', () {
      expect(SongItem.sanitizeTitle('Hold Up by Kunwarr'), equals('Hold Up'));
      expect(SongItem.sanitizeTitle('hold up by kunawarr'), equals('hold up'));
      expect(SongItem.sanitizeTitle('Hold Up by Kunawarr'), equals('Hold Up'));
      expect(
        SongItem.sanitizeTitle('Play Hold Up by Kunwarr'),
        equals('Hold Up'),
      );
      expect(SongItem.sanitizeTitle('Play Starboy'), equals('Starboy'));
      expect(SongItem.sanitizeTitle('Hold Up • 2022'), equals('Hold Up'));
      expect(SongItem.sanitizeTitle('Starboy'), equals('Starboy'));
    });

    test('AlbumItem.subtitle accurately shows track count for Liked Music and albums', () {
      const likedAlbum = AlbumItem(
        id: 'LM',
        title: 'Liked Music',
        artist: '',
        trackCount: 42,
      );
      expect(likedAlbum.subtitle, equals('Playlist • 42 tracks'));

      const singleTrackLiked = AlbumItem(
        id: 'LM',
        title: 'Liked Music',
        artist: '',
        trackCount: 1,
      );
      expect(singleTrackLiked.subtitle, equals('Playlist • 1 track'));

      const albumWithArtist = AlbumItem(
        id: 'a1',
        title: 'Starboy',
        artist: 'The Weeknd',
        year: 2016,
        trackCount: 18,
      );
      expect(albumWithArtist.subtitle, equals('Album • The Weeknd • 2016'));
    });
  });

  group('ArtistScreen Scroll & Snapping Tests', () {
    const testDetails = ArtistDetails(
      id: 'kunwarr_id',
      name: 'Kunwarr',
      bannerUrl: 'https://example.com/kunwarr_banner.jpg',
      topSongs: [
        SongItem(id: 'k1', title: 'Hold Up', artist: 'Kunwarr'),
        SongItem(id: 'k2', title: 'Bewafa', artist: 'Kunwarr'),
        SongItem(id: 'k3', title: 'All Eyes', artist: 'Kunwarr'),
        SongItem(id: 'k4', title: 'Piche Piche', artist: 'Kunwarr'),
        SongItem(id: 'k5', title: 'Crazy4U', artist: 'Kunwarr'),
      ],
    );

    testWidgets(
      'Top Songs in ArtistScreen renders with snapping PageView and PageScrollPhysics',
      (tester) async {
        final mockMusicService = MockArtistMusicService(testDetails);
        final container = ProviderContainer(
          overrides: [musicServiceProvider.overrideWithValue(mockMusicService)],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: ArtistScreen(artistId: 'kunwarr_id', artistName: 'Kunwarr'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Top songs'), findsOneWidget);
        expect(find.text('Hold Up'), findsOneWidget);

        // Verify snapping PageView is present with PageScrollPhysics
        final pageViewFinder = find.byType(PageView);
        expect(pageViewFinder, findsOneWidget);

        final pageView = tester.widget<PageView>(pageViewFinder);
        expect(pageView.physics, isA<PageScrollPhysics>());

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );

    testWidgets(
      'ArtistScreen renders atmospheric secondary color gradient in downside layout',
      (tester) async {
        final mockMusicService = MockArtistMusicService(testDetails);
        final container = ProviderContainer(
          overrides: [musicServiceProvider.overrideWithValue(mockMusicService)],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: ArtistScreen(artistId: 'kunwarr_id', artistName: 'Kunwarr'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Atmosphere gradient container exists in stack
        final containerWithGradients = find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final decor = widget.decoration as BoxDecoration;
            return decor.gradient is LinearGradient;
          }
          return false;
        });
        expect(containerWithGradients, findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });

  group('AlbumScreen Liked Music Track Loading & Secondary Color Tests', () {
    testWidgets(
      'Liked Music album loads tracks immediately from favoritesProvider and displays correct trackCount',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const likedAlbum = AlbumItem(
          id: 'LM',
          title: 'Liked Music',
          artist: '',
          type: 'Playlist',
          trackCount: 2,
        );

        final mockMusicService = MockArtistMusicService(
          const ArtistDetails(id: 'a', name: 'A'),
        );

        final container = ProviderContainer(
          overrides: [musicServiceProvider.overrideWithValue(mockMusicService)],
        );

        // Prepopulate favorites with Kunwarr's Hold Up
        container.read(favoritesProvider.notifier).toggleFavorite(
          const SongItem(id: 'liked_1', title: 'Hold Up', artist: 'Kunwarr', durationSeconds: 180),
        );
        container.read(favoritesProvider.notifier).toggleFavorite(
          const SongItem(id: 'liked_2', title: 'Starboy', artist: 'The Weeknd', durationSeconds: 230),
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: AlbumScreen(album: likedAlbum)),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Verify tracks and metadata display accurately with track count
        expect(find.text('Hold Up'), findsOneWidget);
        expect(find.text('Kunwarr'), findsOneWidget);
        expect(find.textContaining('2 Tracks'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });

  group('LibraryScreen Track Count & Liked Album Tests', () {
    testWidgets('LibraryScreen displays accurate total track count on Liked Music album card', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockMusicService = MockArtistMusicService(
        const ArtistDetails(id: 'a', name: 'A'),
      );

      final container = ProviderContainer(
        overrides: [musicServiceProvider.overrideWithValue(mockMusicService)],
      );

      // Add Kunwarr's Hold Up to favorites
      await container.read(favoritesProvider.notifier).toggleFavorite(
        const SongItem(id: 'liked_1', title: 'Hold Up', artist: 'Kunwarr', durationSeconds: 180),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Liked Music card displays 1 track accurately
      expect(find.text('Liked Music'), findsWidgets);
      expect(find.text('Playlist • 1 track'), findsWidgets);

      // Add second track
      await container.read(favoritesProvider.notifier).toggleFavorite(
        const SongItem(id: 'liked_2', title: 'Starboy', artist: 'The Weeknd', durationSeconds: 230),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Liked Music card updates to 2 tracks
      expect(find.text('Playlist • 2 tracks'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });
}
