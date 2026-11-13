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
import 'package:wavify/screens/google_signin_screen.dart';
import 'package:wavify/services/music_service.dart';

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

    test('UserAccount serializes and deserializes BitChord session metadata', () {
      final now = DateTime.now();
      final account = UserAccount(
        id: 'user_bitchord_1',
        displayName: 'BitChord Listener',
        email: 'listener@youtube.com',
        avatarUrl: 'https://lh3.googleusercontent.com/a/sample_avatar',
        cookies: '__Secure-3PAPISID=token_3papisid_val; SID=sid_token;',
        connectedAt: now,
        isPersonalizedEnabled: true,
        dataSyncId: '123456789_datasync',
        pageId: 'page_id_brand_channel',
        authUser: '0',
        visitorData: 'CgtzYW1wbGVfdmlzaXRvcg',
      );

      final json = account.toJson();
      final restored = UserAccount.fromJson(json);

      expect(restored.dataSyncId, '123456789_datasync');
      expect(restored.pageId, 'page_id_brand_channel');
      expect(restored.authUser, '0');
      expect(restored.visitorData, 'CgtzYW1wbGVfdmlzaXRvcg');
      expect(restored.avatarUrl, 'https://lh3.googleusercontent.com/a/sample_avatar');
      expect(restored.sapisid, 'token_3papisid_val');
    });

    test('UserAccount sapisid getter resolves SAPISID, __Secure-3PAPISID, and __Secure-1PAPISID', () {
      const c1 = 'FOO=bar; SAPISID=plain_sapisid; BAR=baz;';
      final a1 = UserAccount(
        id: '1',
        displayName: 'Test',
        email: '',
        cookies: c1,
        connectedAt: DateTime.now(),
      );
      expect(a1.sapisid, 'plain_sapisid');

      const c2 = 'FOO=bar; __Secure-3PAPISID=secure_3p_val; BAR=baz;';
      final a2 = UserAccount(
        id: '2',
        displayName: 'Test',
        email: '',
        cookies: c2,
        connectedAt: DateTime.now(),
      );
      expect(a2.sapisid, 'secure_3p_val');

      const c3 = 'FOO=bar; __Secure-1PAPISID=secure_1p_val; BAR=baz;';
      final a3 = UserAccount(
        id: '3',
        displayName: 'Test',
        email: '',
        cookies: c3,
        connectedAt: DateTime.now(),
      );
      expect(a3.sapisid, 'secure_1p_val');
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

      // Account modal sheet displays only user details, settings tile, and the single clean Log Out button
      expect(find.text('Utkarsh Google'), findsOneWidget);
      expect(find.text('utkarsh@gmail.com'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);

      // Verify removed items
      expect(find.text('Sync Library & Home Feed'), findsNothing);
      expect(find.text('Connected to YouTube'), findsNothing);
      expect(find.text('YouTube Music Connected'), findsNothing);
      expect(find.text('Personalized Feed'), findsNothing);
      expect(find.text('Refresh Recommendations'), findsNothing);

      // Tap on Settings tile and verify SettingsScreen is pushed
      await tester.tap(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('PLAYBACK & AUDIO'), findsOneWidget);
      expect(find.text('High Quality Audio'), findsOneWidget);
    });

    testWidgets('When not signed in, tapping top-right icon opens dialogue and transfers to GoogleSignInScreen',
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

      // Tapping it opens the account modal sheet dialogue
      await tester.tap(iconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sign In with Google Account'), findsOneWidget);

      // Tapping the dialogue button transfers to GoogleSignInScreen
      await tester.tap(find.text('Sign In with Google Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });

  group('InnerTube Account Menu Parser Tests (BitChord Engine)', () {
    test('MusicService.extractSapisid retrieves SAPISID from various cookie formats', () {
      expect(
        MusicService.extractSapisid('SAPISID=auth_token_123; SID=sid_123;'),
        'auth_token_123',
      );
      expect(
        MusicService.extractSapisid('__Secure-3PAPISID=secure_token_456; SID=sid_123;'),
        'secure_token_456',
      );
      expect(
        MusicService.extractSapisid('__Secure-1PAPISID=first_party_789; SID=sid_123;'),
        'first_party_789',
      );
      expect(
        MusicService.extractSapisid('LOGIN_INFO=only_login_no_sapisid;'),
        isNull,
      );
    });

    test('MusicService.computeSapisidHash produces valid SAPISIDHASH header', () {
      final header = MusicService.computeSapisidHash('sample_sapisid_token');
      expect(header, startsWith('SAPISIDHASH '));
      final parts = header.substring('SAPISIDHASH '.length).split('_');
      expect(parts.length, 2);
      expect(int.tryParse(parts[0]), isNotNull);
      expect(parts[1].length, 40); // 40-character SHA1 hex digest
    });

    test('MusicService.parseAccountMenu parses activeAccountHeaderRenderer with runs & avatar', () {
      final mockData = {
        'actions': [
          {
            'openPopupAction': {
              'popup': {
                'multiPageMenuRenderer': {
                  'header': {
                    'activeAccountHeaderRenderer': {
                      'accountName': {
                        'runs': [
                          {'text': 'Utkarsh Kumar'}
                        ]
                      },
                      'email': {
                        'runs': [
                          {'text': 'utkarsh@example.com'}
                        ]
                      },
                      'channelHandle': {
                        'runs': [
                          {'text': '@utkarshkumar'}
                        ]
                      },
                      'accountPhoto': {
                        'thumbnails': [
                          {
                            'url': '//lh3.googleusercontent.com/a/avatar_low=s88-c-k-c0x00ffffff-no-rj',
                            'width': 88,
                            'height': 88,
                          },
                          {
                            'url': '//lh3.googleusercontent.com/a/avatar_high=s88-c-k-c0x00ffffff-no-rj',
                            'width': 176,
                            'height': 176,
                          }
                        ]
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      };

      final profile = MusicService.parseAccountMenu(mockData);
      expect(profile, isNotNull);
      expect(profile!.displayName, 'Utkarsh Kumar');
      expect(profile.email, 'utkarsh@example.com');
      // Should upgrade leading '//' to 'https://' and resolution to '=s256'
      expect(profile.avatarUrl, startsWith('https://lh3.googleusercontent.com/a/avatar_high=s256'));
    });

    test('MusicService.parseAccountMenu falls back to channelHandle when email is missing', () {
      final mockData = {
        'header': {
          'activeAccountHeaderRenderer': {
            'accountName': {'simpleText': 'Music Enthusiast'},
            'channelHandle': {'simpleText': '@musiclover'},
            'accountPhoto': {
              'thumbnails': [
                {'url': 'https://yt3.ggpht.com/channel_avatar'}
              ]
            }
          }
        }
      };

      final profile = MusicService.parseAccountMenu(mockData);
      expect(profile, isNotNull);
      expect(profile!.displayName, 'Music Enthusiast');
      expect(profile.email, '@musiclover');
      expect(profile.avatarUrl, 'https://yt3.ggpht.com/channel_avatar');
    });

    test('MusicService.parseAccountMenu falls back to accountItem when header is missing', () {
      final mockData = {
        'contents': [
          {
            'accountItem': {
              'accountName': {'simpleText': 'Channel Name'},
              'accountByline': {'simpleText': 'handle_or_email@channel.com'},
              'accountPhoto': {
                'thumbnails': [
                  {'url': 'https://yt3.ggpht.com/avatar_item'}
                ]
              }
            }
          }
        ]
      };

      final profile = MusicService.parseAccountMenu(mockData);
      expect(profile, isNotNull);
      expect(profile!.displayName, 'Channel Name');
      expect(profile.email, 'handle_or_email@channel.com');
      expect(profile.avatarUrl, 'https://yt3.ggpht.com/avatar_item');
    });

    test('MusicService.parseAccountMenu returns null on empty or invalid data', () {
      expect(MusicService.parseAccountMenu(null), isNull);
      expect(MusicService.parseAccountMenu({}), isNull);
      expect(MusicService.parseAccountMenu({'random': 'data'}), isNull);
    });
  });

  group('GoogleSignInScreen Widget Smoke Tests', () {
    testWidgets('GoogleSignInScreen mounts with Apple AppBar and close button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: GoogleSignInScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify AppBar header elements
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);
    });
  });
}
