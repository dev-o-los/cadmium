import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/home_data.dart';
import 'package:wavify/models/user_account.dart';
import 'package:wavify/providers/auth_provider.dart';
import 'package:wavify/providers/home_data_provider.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/screens/home_screen.dart';

class _MockHomeDataNotifier extends HomeDataNotifier {
  final HomeData mockData;
  _MockHomeDataNotifier(this.mockData);

  @override
  Future<HomeData> build() async => mockData;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserAccount Model Tests', () {
    test('UserAccount serializes to JSON and deserializes correctly', () {
      final now = DateTime.now();
      final account = UserAccount(
        id: 'user_123',
        displayName: 'Alex Rivers',
        email: 'alex.rivers@gmail.com',
        cookies: 'SAPISID=sample_sapisid_token; LOGIN_INFO=sample_login_info;',
        connectedAt: now,
        isPersonalizedEnabled: true,
      );

      final json = account.toJson();
      final fromJson = UserAccount.fromJson(json);

      expect(fromJson.id, 'user_123');
      expect(fromJson.displayName, 'Alex Rivers');
      expect(fromJson.email, 'alex.rivers@gmail.com');
      expect(fromJson.cookies, contains('SAPISID=sample_sapisid_token'));
      expect(fromJson.sapisid, 'sample_sapisid_token');
      expect(fromJson.initials, 'AR');
      expect(fromJson.isPersonalizedEnabled, isTrue);
    });

    test('UserAccount initials generation handles single and multi-word names', () {
      final singleName = UserAccount(
        id: '1',
        displayName: 'Utkarsh',
        email: 'u@example.com',
        cookies: '',
        connectedAt: DateTime.now(),
      );
      expect(singleName.initials, 'U');

      final twoNames = UserAccount(
        id: '2',
        displayName: 'John Mayer',
        email: 'jm@example.com',
        cookies: '',
        connectedAt: DateTime.now(),
      );
      expect(twoNames.initials, 'JM');
    });
  });

  group('AuthNotifier & MusicService Integration Tests', () {
    test('Signing in saves account to SharedPreferences and updates MusicService', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final authNotifier = container.read(authProvider.notifier);
      final musicService = container.read(musicServiceProvider);

      final account = UserAccount(
        id: 'google_user_1',
        displayName: 'Taylor Swift Fan',
        email: 'taylor@gmail.com',
        cookies: 'SAPISID=taylor_sapisid_val; SID=session_id_val;',
        connectedAt: DateTime.now(),
        isPersonalizedEnabled: true,
      );

      await authNotifier.signInWithGoogleAccount(account);

      // Verify AuthNotifier state
      expect(container.read(authProvider), equals(account));

      // Verify MusicService received account and generated SAPISID hash
      expect(musicService.currentAccount, equals(account));
      final sapisidHash = musicService.getSapisidHash();
      expect(sapisidHash, isNotNull);
      expect(sapisidHash, startsWith('SAPISIDHASH '));

      // Verify sign out clears account
      await authNotifier.signOut();
      expect(container.read(authProvider), isNull);
      expect(musicService.currentAccount, isNull);
      expect(musicService.getSapisidHash(), isNull);
    });
  });

  group('Home Screen Google Account Top-Right Button UI Tests', () {
    testWidgets('Top-right avatar renders connected account and opens modal sheet on tap',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final signedInAccount = UserAccount(
        id: 'user_active_1',
        displayName: 'Utkarsh Google',
        email: 'utkarsh@gmail.com',
        cookies: 'SAPISID=test_cookie;',
        connectedAt: DateTime.now(),
        isPersonalizedEnabled: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(ref);
              notifier.state = signedInAccount;
              return notifier;
            }),
            homeDataProvider.overrideWith(
              () => _MockHomeDataNotifier(
                const HomeData(
                  heroCards: [],
                  recents: [],
                  quickPicks: [],
                  moods: [],
                  albumsAndSingles: [],
                  musicVideos: [],
                  dailyDiscover: [],
                  genres: [],
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

      // Verify user's initials 'UG' are rendered in top-right avatar
      expect(find.text('UG'), findsOneWidget);

      // Tap on top-right profile avatar
      await tester.tap(find.text('UG'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Account modal sheet should display the connected Google / YouTube Music details
      expect(find.text('Utkarsh Google'), findsOneWidget);
      expect(find.text('utkarsh@gmail.com'), findsOneWidget);
      expect(find.text('YouTube Music Connected'), findsOneWidget);
      expect(find.text('Personalized Feed'), findsOneWidget);
      expect(find.text('Refresh Recommendations'), findsOneWidget);
      expect(find.text('Sign Out of Google Account'), findsOneWidget);
    });

    testWidgets('When not signed in, tapping top-right icon directly opens GoogleSignInScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeDataProvider.overrideWith(
              () => _MockHomeDataNotifier(
                const HomeData(
                  heroCards: [],
                  recents: [],
                  quickPicks: [],
                  moods: [],
                  albumsAndSingles: [],
                  musicVideos: [],
                  dailyDiscover: [],
                  genres: [],
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

      // Find top-right profile icon
      final iconFinder = find.byIcon(CupertinoIcons.person_crop_circle_fill);
      expect(iconFinder, findsOneWidget);

      // Tapping it directly navigates to GoogleSignInScreen (WebView)
      await tester.tap(iconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });
}
