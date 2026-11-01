import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/artist_details.dart';
import 'package:wavify/models/artist_item.dart';
import 'package:wavify/models/playlist_item.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/models/video_item.dart';
import 'package:wavify/providers/library_provider.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/screens/artist_screen.dart';
import 'package:wavify/screens/album_screen.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';
import 'package:wavify/widgets/track_options_sheet.dart';

class FakeMusicService extends MusicService {
  final ArtistDetails testDetails;

  FakeMusicService(this.testDetails);

  @override
  Future<ArtistDetails> getArtistDetails(String artistIdOrName, {String? fallbackName}) async {
    return testDetails;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testArtistDetails = ArtistDetails(
    id: 'UC_sofaygo',
    name: 'SoFaygo',
    bannerUrl: 'https://example.com/banner.jpg',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    subscribers: '462K subscribers',
    monthlyListeners: '2.47M monthly listeners',
    description: 'Andre Dontrel Burt Jr., known professionally as SoFaygo, is an American rapper and singer. His 2019 single Knock Knock went viral on TikTok.',
    recentRelease: AlbumItem(
      id: 'try_and_fail',
      title: 'Try and Fail',
      artist: 'SoFaygo',
      year: 2026,
      type: 'Single',
    ),
    topSongs: [
      SongItem(id: 's1', title: 'Hell Yeah', artist: 'SoFaygo, Ken Carson'),
      SongItem(id: 's2', title: 'Everyday', artist: 'SoFaygo'),
      SongItem(id: 's3', title: 'CONTEST', artist: 'Travis Scott, SoFaygo'),
      SongItem(id: 's4', title: 'MP5', artist: 'Trippie Redd, SoFaygo'),
      SongItem(id: 's5', title: 'Knock Knock', artist: 'SoFaygo'),
      SongItem(id: 's6', title: 'Satellite', artist: 'SoFaygo'),
      SongItem(id: 's7', title: 'Off The Map', artist: 'SoFaygo'),
      SongItem(id: 's8', title: 'MM3', artist: 'SoFaygo'),
      SongItem(id: 's9', title: 'Stay Awake', artist: 'SoFaygo, Lil Uzi Vert'),
      SongItem(id: 's10', title: 'Blitz', artist: 'SoFaygo'),
      SongItem(id: 's11', title: 'Me Too', artist: 'SoFaygo'),
      SongItem(id: 's12', title: 'Fasho', artist: 'SoFaygo'),
    ],
    albums: [
      AlbumItem(id: 'a1', title: 'MANIA', artist: 'SoFaygo', year: 2025),
      AlbumItem(id: 'a2', title: 'GO+', artist: 'SoFaygo', year: 2023),
      AlbumItem(id: 'a3', title: 'Pink Heartz', artist: 'SoFaygo', year: 2022),
    ],
    singles: [
      AlbumItem(id: 'sg1', title: 'Try and Fail', artist: 'SoFaygo', year: 2026, type: 'Single'),
      AlbumItem(id: 'sg2', title: 'Satellite', artist: 'SoFaygo', year: 2025, type: 'Single'),
    ],
    videos: [
      VideoItem(id: 'v1', title: 'Knock Knock', artist: 'SoFaygo', views: '101M views'),
      VideoItem(id: 'v2', title: 'Off The Map', artist: 'SoFaygo', views: '12M views'),
    ],
    featuredOn: [
      PlaylistItem(id: 'p1', title: 'Noise Rap', author: 'YouTube Music'),
      PlaylistItem(id: 'p2', title: 'Laid-Back Hip Hop', author: 'YouTube Music'),
    ],
    playlistsByArtist: [
      PlaylistItem(id: 'pa1', title: 'After Me', author: 'SoFaygo • 51...'),
      PlaylistItem(id: 'pa2', title: 'Pink Heartz', author: 'SoFaygo • 38...'),
    ],
    similarArtists: [
      ArtistItem(id: 'sa1', name: 'Yung Fazo', subscribers: '130K monthly audience'),
      ArtistItem(id: 'sa2', name: 'Yeat', subscribers: '37.3M monthly audience'),
    ],
  );

  Widget createArtistScreen({ProviderContainer? container}) {
    final fakeService = FakeMusicService(testArtistDetails);
    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ArtistScreen(
            artistId: 'UC_sofaygo',
            artistName: 'SoFaygo',
          ),
        ),
      );
    }
    return ProviderScope(
      overrides: [
        musicServiceProvider.overrideWithValue(fakeService),
      ],
      child: const MaterialApp(
        home: ArtistScreen(
          artistId: 'UC_sofaygo',
          artistName: 'SoFaygo',
        ),
      ),
    );
  }

  testWidgets('ArtistScreen renders hero header, stat pills, action row, spotlight card, top songs, and carousels',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createArtistScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Verify Artist Header and Name
    expect(find.text('SoFaygo'), findsWidgets);

    // 2. Verify Stat Badges
    expect(find.text('462K subscribers'), findsWidgets);
    expect(find.text('2.47M monthly listeners'), findsWidgets);

    // 3. Verify Liquid Glass Action Row: Shuffle, Large Play, Star/Favorite
    expect(find.byIcon(CupertinoIcons.shuffle), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsWidgets);
    expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);

    // 4. Verify Spotlight Recent Single
    expect(find.text('Single • 2026'), findsWidgets);
    expect(find.text('Recent Single'), findsOneWidget);

    // 5. Verify Top Songs Section
    expect(find.text('Top songs'), findsOneWidget);
    expect(find.text('Hell Yeah'), findsOneWidget);
    expect(find.text('Everyday'), findsOneWidget);
    expect(find.text('CONTEST'), findsOneWidget);
    expect(find.text('MP5'), findsOneWidget);
    expect(find.text('E'), findsWidgets); // Explicit badges

    // 6. Verify Albums Carousel
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('MANIA'), findsOneWidget);
    expect(find.text('GO+'), findsOneWidget);

    // 7. Verify Singles & EPs Carousel
    expect(find.text('Singles & EPs'), findsOneWidget);
    expect(find.text('Satellite'), findsWidgets);

    // 8. Verify Videos Section
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Knock Knock'), findsWidgets);
    expect(find.text('SoFaygo • 101M views'), findsOneWidget);

    // 9. Verify Featured on Carousel
    expect(find.text('Featured on'), findsOneWidget);
    expect(find.text('Noise Rap'), findsOneWidget);
    expect(find.text('Laid-Back Hip Hop'), findsOneWidget);

    // 10. Verify Playlists by Artist Carousel
    expect(find.text('Playlists by SoFaygo'), findsOneWidget);
    expect(find.text('After Me'), findsOneWidget);

    // 11. Verify Fans might also like Carousel
    expect(find.text('Fans might also like'), findsOneWidget);
    expect(find.text('Yung Fazo'), findsOneWidget);
    expect(find.text('130K monthly audience'), findsOneWidget);
    expect(find.text('Yeat'), findsOneWidget);
    expect(find.text('37.3M monthly audience'), findsOneWidget);

    // 12. Verify About the Artist and More toggle
    expect(find.text('About the artist'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // Tap 'More' to expand bio
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Less'), findsOneWidget);

    // 13. Verify Floating Bottom Dock
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
  });

  testWidgets('Tapping Star button on ArtistScreen bookmarks artist in library',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        musicServiceProvider.overrideWithValue(FakeMusicService(testArtistDetails)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(createArtistScreen(container: container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Initially not saved
    expect(
      container.read(savedArtistsProvider).any((a) => a.id == 'UC_sofaygo' || a.name == 'SoFaygo'),
      isFalse,
    );

    // Tap Star button in action row
    await tester.tap(find.byIcon(CupertinoIcons.star_fill));
    await tester.pumpAndSettle();

    // Now saved
    expect(
      container.read(savedArtistsProvider).any((a) => a.name == 'SoFaygo'),
      isTrue,
    );
  });

  testWidgets('Tapping artist name in AlbumScreen navigates to ArtistScreen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const testAlbum = AlbumItem(
      id: 'album_pink_heartz',
      title: 'Pink Heartz',
      artist: 'SoFaygo',
      year: 2022,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicServiceProvider.overrideWithValue(FakeMusicService(testArtistDetails)),
        ],
        child: const MaterialApp(
          home: AlbumScreen(album: testAlbum),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Find and tap the artist name under the album title
    final artistNameFinder = find.text('SoFaygo');
    expect(artistNameFinder, findsWidgets);

    await tester.tap(artistNameFinder.first);
    await tester.pumpAndSettle();

    // Verify ArtistScreen is opened
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(find.text('About the artist'), findsOneWidget);
  });

  testWidgets('Tapping View Artist in TrackOptionsSheet opens ArtistScreen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const testSong = SongItem(
      id: 's1',
      title: 'Hell Yeah',
      artist: 'SoFaygo',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicServiceProvider.overrideWithValue(FakeMusicService(testArtistDetails)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => showTrackOptionsModal(context, ref, testSong),
                    child: const Text('Open Track Options'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open Track Options'));
    await tester.pumpAndSettle();

    // Verify 'View Artist: SoFaygo' option exists
    expect(find.text('View Artist: SoFaygo'), findsOneWidget);

    // Tap View Artist
    await tester.tap(find.text('View Artist: SoFaygo'));
    await tester.pumpAndSettle();

    // Verify ArtistScreen is opened
    expect(find.byType(ArtistScreen), findsOneWidget);
  });
}