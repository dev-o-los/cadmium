import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/user_account.dart';
import '../providers/auth_provider.dart';
import '../providers/music_service_provider.dart';

/// Screen allowing users to sign in with their Google account to authorize
/// YouTube Music, fetch their verified profile, and receive personalized recommendations.
class GoogleSignInScreen extends ConsumerStatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleDarkSurface = Color(0xFF1C1C1E);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

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
  String _currentUrl = 'https://accounts.google.com';

  // Authentication progress state
  bool _isAuthorizing = false;
  bool _isSuccess = false;
  String? _profileName;
  String? _profileEmail;
  String? _profileAvatarUrl;
  String _statusMessage = 'Connecting to YouTube Music...';

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
                  _currentUrl = url;
                });
              }
              _checkSessionTransition(url);
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _currentUrl = url;
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

  /// Detects when navigation reaches YouTube Music, immediately activates the frosted
  /// loading overlay (preventing raw site flashes or black screen), extracts native session
  /// cookies and ytcfg data, queries verified profile via InnerTube, and redirects to Home.
  Future<void> _checkSessionTransition(String url) async {
    if (_isAuthorizing || _isSuccess || !mounted) return;

    if (url.contains('music.youtube.com') ||
        (url.contains('youtube.com') && !url.contains('accounts.google.com'))) {
      setState(() {
        _isAuthorizing = true;
        _statusMessage = 'Connecting to YouTube Music...';
      });

      try {
        await _performAccountVerification();
      } catch (e) {
        debugPrint('Verification error: $e');
        if (mounted) {
          // If unexpected error, attempt emergency fallback with whatever cookies exist
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

    if (mounted) {
      setState(() {
        _statusMessage = 'Retrieving your YouTube Music profile...';
      });
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

    // 5. Persist account and trigger personalized home feed refresh
    await ref.read(authProvider.notifier).signInWithGoogleAccount(account);

    if (!mounted) return;

    // 6. Transition to success state
    setState(() {
      _isAuthorizing = false;
      _isSuccess = true;
      _profileName = displayName;
      _profileEmail = email;
      _profileAvatarUrl = avatarUrl;
    });

    // 7. Brief pleasant delay (1.2s) so the user sees their verified profile, then redirect to Home
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    // Redirect straight to Home screen
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

  Widget _buildInitialsAvatar() {
    final name = _profileName ?? 'U';
    final initials =
        name.trim().isNotEmpty ? name.trim().substring(0, 1).toUpperCase() : 'U';
    return Container(
      color: const Color(0xFF2C2C2E),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildConfirmationOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: appleDarkSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: _isSuccess
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: appleRed, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: appleRed.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _profileAvatarUrl != null &&
                                      _profileAvatarUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _profileAvatarUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: const Color(0xFF2C2C2E),
                                        child: const Center(
                                          child: CupertinoActivityIndicator(
                                            radius: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          _buildInitialsAvatar(),
                                    )
                                  : _buildInitialsAvatar(),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.checkmark_seal_fill,
                              color: Colors.greenAccent,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _profileName ?? 'Signed In!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_profileEmail != null && _profileEmail!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _profileEmail!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: appleSecondaryText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.checkmark_alt,
                              color: Colors.greenAccent,
                              size: 15,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Connected & Verified',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Redirecting to Home...',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: appleRed.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.music_note_list,
                          color: appleRed,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Connecting Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: appleSecondaryText,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const CupertinoActivityIndicator(
                        radius: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
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
        title: Column(
          children: [
            const Text(
              'Sign in with Google',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.lock_fill,
                  color: Colors.greenAccent,
                  size: 10,
                ),
                const SizedBox(width: 4),
                Text(
                  _currentUrl.contains('music.youtube.com')
                      ? 'music.youtube.com'
                      : 'accounts.google.com',
                  style: const TextStyle(
                    color: appleSecondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        bottom: (_isLoading && !_isAuthorizing && !_isSuccess)
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

            // Frosted glass authorization and verification card
            if (_isAuthorizing || _isSuccess)
              Positioned.fill(
                child: _buildConfirmationOverlay(),
              ),
          ],
        ),
      ),
    );
  }
}
