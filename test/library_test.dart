import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/artist_item.dart';
import 'package:wavify/models/playlist_item.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/providers/library_provider.dart';
import 'package:wavify/screens/home_screen.dart';
import 'package:wavify/services/music_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Library URL & ID Parsing Tests', () {
    test('extractPlaylistId extracts list query parameter from various URLs', () {
      expect(
        MusicService.extractPlaylistId('https://music.youtube.com/playlist?list=PL4fGSIqq985TWX4_C48q8_wP79Xf11uI_'),
        'PL4fGSIqq985TWX4_C48q8_wP79Xf11uI_',
      );
      expect(
        MusicService.extractPlaylistId('https://www.youtube.com/playlist?list=RDCLAK5uy_kmPRjFGNQStVPkuDY27sopV4JyQuqJEe0'),
        'RDCLAK5uy_kmPRjFGNQStVPkuDY27sopV4JyQuqJEe0',
      );
      expect(
        MusicService.extractPlaylistId('PLtest123'),
        'PLtest123',
      );
      expect(
        MusicService.extractPlaylistId(''),
        '',
      );
    });
  });

  group('SavedPlaylistsNotifier Persistence Tests', () {
    test('addPlaylist and removePlaylist persist to local SharedPreferences', () async {
      final notifier = SavedPlaylistsNotifier();
      // Allow initial load
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const newPlaylist = PlaylistItem(
        id: 'custom_pl_1',
        title: 'Late Night Drive',
        author: 'User',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        trackCount: 25,
        isCustom: true,
      );

      await notifier.addPlaylist(newPlaylist);
      expect(notifier.isPlaylistSaved('custom_pl_1'), isTrue);
      expect(notifier.state.any((p) => p.id == 'custom_pl_1'), isTrue);

      // Verify reloaded notifier reads persisted list
      final reloaded = SavedPlaylistsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reloaded.isPlaylistSaved('custom_pl_1'), isTrue);

      await notifier.removePlaylist('custom_pl_1');
      expect(notifier.isPlaylistSaved('custom_pl_1'), isFalse);
    });
  });

  group('SavedAlbumsNotifier & SavedArtistsNotifier Persistence Tests', () {
    test('SavedAlbumsNotifier toggles and persists albums', () async {
      final notifier = SavedAlbumsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const album = AlbumItem(
        id: 'album_test_1',
        title: 'Dawn FM',
        artist: 'The Weeknd',
        year: 2022,
      );

      final added = await notifier.toggleAlbum(album);
      expect(added, isTrue);
      expect(notifier.isAlbumSaved('album_test_1'), isTrue);

      final toggledOff = await notifier.toggleAlbum(album);
      expect(toggledOff, isFalse);
      expect(notifier.isAlbumSaved('album_test_1'), isFalse);
    });

    test('SavedArtistsNotifier toggles and persists artists', () async {
      final notifier = SavedArtistsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const artist = ArtistItem(
        id: 'artist_test_1',
        name: 'Travis Scott',
        subscribers: '18M subscribers',
      );

      final added = await notifier.toggleArtist(artist);
      expect(added, isTrue);
      expect(notifier.isArtistSaved('artist_test_1'), isTrue);

      final toggledOff = await notifier.toggleArtist(artist);
      expect(toggledOff, isFalse);
      expect(notifier.isArtistSaved('artist_test_1'), isFalse);
    });
  });

  group('Library Tab UI & Layout Tests', () {
    testWidgets('Library tab renders square album card sections and excludes old list tiles',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) {
              final n = FavoritesNotifier();
              n.state = const [
                SongItem(
                  id: 'fav_1',
                  title: 'Favorite Track 1',
                  artist: 'Favorite Artist 1',
                  thumbnailUrl: null,
                ),
              ];
              return n;
            }),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the Library navigation item (3rd tab)
      final libraryNavButton = find.text('Library');
      expect(libraryNavButton, findsOneWidget);
      await tester.tap(libraryNavButton);
      await tester.pumpAndSettle();

      // Verify Library screen header
      expect(find.text('Library'), findsWidgets);

      // Verify modern album card sections are present
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Liked Music'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);

      // Verify "Save Playlist" ("From YouTube") button is present
      expect(find.text('Save Playlist'), findsOneWidget);
      expect(find.text('From YouTube'), findsWidgets);

      // Verify "Favorite Track 1" is displayed
      expect(find.text('Favorite Track 1'), findsOneWidget);

      // Verify OLD list tiles have been removed!
      expect(find.text('Connect YouTube Music Account'), findsNothing);
      expect(find.text('Downloaded'), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
    });
  });
}

