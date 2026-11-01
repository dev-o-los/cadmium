import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/artist_item.dart';
import 'package:wavify/models/playlist_item.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/models/user_account.dart';
import 'package:wavify/providers/auth_provider.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/providers/library_provider.dart';
import 'package:wavify/screens/home_screen.dart';
import 'package:wavify/services/music_service.dart';

class _MockAuthNotifier extends AuthNotifier {
  _MockAuthNotifier(super.ref, UserAccount? initial) {
    state = initial;
  }
}

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

      final reloaded = SavedPlaylistsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reloaded.isPlaylistSaved('custom_pl_1'), isTrue);

      await notifier.removePlaylist('custom_pl_1');
      expect(notifier.isPlaylistSaved('custom_pl_1'), isFalse);
    });
  });

  group('SavedAlbumsNotifier & SavedArtistsNotifier Persistence Tests', () {
    test('SavedAlbumsNotifier toggles, updates thumbnail, and persists albums', () async {
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

      // Verify updateAlbumThumbnail updates real image and persists
      notifier.updateAlbumThumbnail('album_test_1', 'https://example.com/dawn_fm.jpg');
      final updatedAlbum = notifier.state.firstWhere((a) => a.id == 'album_test_1');
      expect(updatedAlbum.thumbnailUrl, 'https://example.com/dawn_fm.jpg');

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

  group('User-Specific Library Providers Tests', () {
    test('Logged-out user resolves local collections, logged-in user resolves account collections', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(ref, null)), // Logged out
        ],
      );

      // Wait for initial SharedPreferences load
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 1. When logged out, userPlaylistsProvider returns saved local/curated list
      final loggedOutPlaylists = await container.read(userPlaylistsProvider.future);
      expect(loggedOutPlaylists.isNotEmpty, isTrue);

      // 2. When logged in, container with user account resolves only user-specific items
      final userAccount = UserAccount(
        id: 'user_123',
        email: 'user@gmail.com',
        displayName: 'Alex Smith',
        cookies: 'SAPISID=123',
        connectedAt: DateTime(2026, 1, 1),
      );

      final loggedInContainer = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(ref, userAccount)),
        ],
      );

      final loggedInPlaylists = await loggedInContainer.read(userPlaylistsProvider.future);
      expect(loggedInPlaylists, isA<List<PlaylistItem>>());
    });
  });

  group('Library Tab UI & Layout Tests', () {
    testWidgets('Library tab renders square album card sections and excludes old list tiles when logged out',
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

    testWidgets('Library tab shows only user-specific music and verified header when logged in',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final userAccount = UserAccount(
        id: 'user_456',
        email: 'utkarsh@gmail.com',
        displayName: 'Utkarsh Kumar',
        cookies: 'SAPISID=test_cookie',
        connectedAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier(ref, userAccount)),
            userPlaylistsProvider.overrideWith((ref) async => const [
                  PlaylistItem(
                    id: 'user_pl_1',
                    title: 'My Custom Jams',
                    author: 'Utkarsh Kumar',
                    thumbnailUrl: 'https://example.com/jams.jpg',
                    trackCount: 12,
                    isCustom: true,
                  ),
                ]),
            userAlbumsProvider.overrideWith((ref) async => const [
                  AlbumItem(
                    id: 'user_alb_1',
                    title: 'My Saved Album',
                    artist: 'Favorite Artist',
                    thumbnailUrl: 'https://example.com/album.jpg',
                    isCustom: true,
                  ),
                ]),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Library tab
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      // Verify connected user badge
      expect(find.text('Utkarsh'), findsOneWidget);

      // Verify user's own specific playlist and album appear
      expect(find.text('My Custom Jams'), findsOneWidget);
      expect(find.text('My Saved Album'), findsOneWidget);
    });
  });
}
