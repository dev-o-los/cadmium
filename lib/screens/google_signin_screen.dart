import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/user_account.dart';
import '../providers/auth_provider.dart';
import '../providers/music_service_provider.dart';

/// Screen allowing users to sign in with their Google account to authorize
/// YouTube Music, fetch their profile, and receive personalized recommendations.
class GoogleSignInScreen extends ConsumerStatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  static const Color appleRed = Color(0xFFFA243C);

  static const String _loginUrl =
      'https://accounts.google.com/ServiceLogin'
      '?ltmpl=music&service=youtube&prompt=select_account'
      '&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  // Standard mobile Chrome user agent supported by Google sign-in
  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

  // ytcfg extraction probe adapted from BitChord
  static const String _ytcfgProbe = '''
(function () {
  try {
    if (!window.ytcfg || !window.ytcfg.get) return null;
    var get = function (key) {
      var value = window.ytcfg.get(key);
      return (value === undefined || value === null || value === '') ? null : String(value);
    };
    return JSON.stringify({
      loggedIn: String(!!window.ytcfg.get('LOGGED_IN')),
      pageId: get('DELEGATED_SESSION_ID'),
      dataSyncId: get('DATASYNC_ID'),
      authUser: get('SESSION_INDEX'),
      visitorData: get('VISITOR_DATA'),
      clientVersion: get('INNERTUBE_CLIENT_VERSION')
    });
  } catch (e) {
    return null;
  }
})()
''';

  WebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _isAuthorizing = false;

  WebViewCookieManager? _cookieManager;

  WebViewCookieManager? get _safeCookieManager {
    try {
      return _cookieManager ??= WebViewCookieManager();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      // Clear previous cookies so new login is completely fresh
      await _safeCookieManager?.clearCookies();

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_mobileChromeUserAgent)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _progress = progress / 100.0;
                });
              }
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                });
              }
              _checkSessionTransition(url);
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              _checkSessionTransition(url);
            },
            onUrlChange: (change) {
              if (change.url != null) {
                _checkSessionTransition(change.url!);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(_loginUrl));

      if (mounted) {
        setState(() {
          _webViewController = controller;
        });
      }
    } catch (e) {
      debugPrint('WebView initialization failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Detects when navigation reaches YouTube Music, extracts native session cookies
  /// and ytcfg data, queries profile via InnerTube, saves credentials, and directly navigates Home.
  Future<void> _checkSessionTransition(String url) async {
    if (_isAuthorizing || !mounted) return;

    if (url.contains('music.youtube.com') ||
        (url.contains('youtube.com') && !url.contains('accounts.google.com'))) {
      setState(() {
        _isAuthorizing = true;
      });

      try {
        await _performAccountVerification();
      } catch (e) {
        debugPrint('Verification error: $e');
        if (mounted) {
          _performFallbackSignIn();
        }
      }
    }
  }

  Future<void> _performAccountVerification() async {
    // 1. Extract cookies from native platform cookie jar across YouTube and Google domains
    final cookieJar = <String, String>{};

    try {
      final cm = _safeCookieManager;
      if (cm != null) {
        final domains = [
          Uri.parse('https://music.youtube.com'),
          Uri.parse('https://youtube.com'),
          Uri.parse('https://accounts.google.com'),
        ];

        for (final domain in domains) {
          final cookies = await cm.getCookies(domain: domain);
          for (final c in cookies) {
            if (c.name.isNotEmpty && c.value.isNotEmpty) {
              cookieJar[c.name] = c.value;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading native cookie jar: $e');
    }

    // Also check document.cookie from WebView as complementary source
    try {
      if (_webViewController != null) {
        final jsCookieRes =
            await _webViewController!.runJavaScriptReturningResult('document.cookie');
        var jsCookieStr = jsCookieRes.toString().trim();
        if (jsCookieStr.startsWith('"') &&
            jsCookieStr.endsWith('"') &&
            jsCookieStr.length >= 2) {
          jsCookieStr = jsCookieStr.substring(1, jsCookieStr.length - 1);
        }
        for (final part in jsCookieStr.split(';')) {
          final eq = part.indexOf('=');
          if (eq > 0) {
            final name = part.substring(0, eq).trim();
            final val = part.substring(eq + 1).trim();
            if (name.isNotEmpty && val.isNotEmpty) {
              cookieJar.putIfAbsent(name, () => val);
            }
          }
        }
      }
    } catch (_) {}

    final cookiesString =
        cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');

    // 2. Extract ytcfg from the live page
    String? pageId;
    String? dataSyncId;
    String? authUser;
    String? visitorData;
    String? clientVersion;

    try {
      if (_webViewController != null) {
        final probeResult =
            await _webViewController!.runJavaScriptReturningResult(_ytcfgProbe);
        var probeStr = probeResult.toString().trim();
        if (probeStr.startsWith('"') &&
            probeStr.endsWith('"') &&
            probeStr.length >= 2) {
          probeStr = probeStr
              .substring(1, probeStr.length - 1)
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
        }

        if (probeStr.isNotEmpty && probeStr != 'null') {
          final probeJson = jsonDecode(probeStr) as Map<String, dynamic>;
          pageId = probeJson['pageId']?.toString();
          dataSyncId = pageId ?? probeJson['dataSyncId']?.toString();
          authUser = probeJson['authUser']?.toString();
          visitorData = probeJson['visitorData']?.toString();
          clientVersion = probeJson['clientVersion']?.toString();
        }
      }
    } catch (e) {
      debugPrint('Error probing ytcfg: $e');
    }

    // 3. Query InnerTube account_menu using SAPISIDHASH to retrieve real name, email, and avatar
    final musicService = ref.read(musicServiceProvider);
    final profile = await musicService.fetchAccountProfile(
      cookies: cookiesString,
      dataSyncId: dataSyncId,
      pageId: pageId,
      authUser: authUser,
      visitorData: visitorData,
      clientVersion: clientVersion,
    );

    final displayName = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : 'YouTube Music User';
    final email = profile?.email ?? '';
    final avatarUrl = profile?.avatarUrl;

    // 4. Construct authentic UserAccount model
    final account = UserAccount(
      id: 'google_ytm_${DateTime.now().millisecondsSinceEpoch}',
      displayName: displayName,
      email: email,
      avatarUrl: avatarUrl,
      cookies: cookiesString,
      connectedAt: DateTime.now(),
      isPersonalizedEnabled: true,
      dataSyncId: dataSyncId,
      pageId: pageId,
      authUser: authUser,
      visitorData: visitorData,
    );

    // 5. Persist account and trigger recommendations refresh
    await ref.read(authProvider.notifier).signInWithGoogleAccount(account);

    if (!mounted) return;

    // 6. Directly navigate straight to Home screen without any delay or verify screens
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _performFallbackSignIn() async {
    try {
      final account = UserAccount(
        id: 'google_ytm_${DateTime.now().millisecondsSinceEpoch}',
        displayName: 'YouTube Music User',
        email: '',
        cookies: '',
        connectedAt: DateTime.now(),
        isPersonalizedEnabled: true,
      );
      await ref.read(authProvider.notifier).signInWithGoogleAccount(account);
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Sign in with Google',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        bottom: (_isLoading && !_isAuthorizing)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: appleRed,
                  backgroundColor: Colors.white10,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Embedded Google Sign-In WebView
            Positioned.fill(
              child: _webViewController != null
                  ? WebViewWidget(controller: _webViewController!)
                  : const Center(
                      child: CupertinoActivityIndicator(
                        radius: 14,
                        color: appleRed,
                      ),
                    ),
            ),

            // Clean dark overlay while credentials are being finalized
            if (_isAuthorizing)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: CupertinoActivityIndicator(
                      radius: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
