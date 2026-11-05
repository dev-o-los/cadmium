import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/user_account.dart';
import '../providers/auth_provider.dart';
import '../providers/music_service_provider.dart';
import '../services/music_service.dart';

/// Screen allowing users to sign in with their Google account to authorize
/// YouTube Music, fetch their verified profile, and receive personalized recommendations.
class GoogleSignInScreen extends ConsumerStatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  static const String _loginUrl =
      'https://accounts.google.com/ServiceLogin'
      '?ltmpl=music&service=youtube&prompt=select_account'
      '&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  // Platform-appropriate User Agent string free of embedded WebView markers
  static String get _userAgent {
    if (kIsWeb) return '';
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';
  }

  // ytcfg & DOM extraction probe adapted from BitChord with deep avatar detection
  static const String _sessionProbeScript = '''
(function () {
  try {
    var get = function (key) {
      if (window.ytcfg && window.ytcfg.get) {
        var val = window.ytcfg.get(key);
        if (val !== undefined && val !== null && val !== '') return String(val);
      }
      if (window.ytcfg && window.ytcfg.data_ && window.ytcfg.data_[key]) {
        return String(window.ytcfg.data_[key]);
      }
      return null;
    };

    var avatarSrc = null;

    // 1. Deep check window.ytInitialData / window.ytmusicInitialData for Google avatar URL
    try {
      var d = window.ytInitialData || window.ytmusicInitialData;
      if (d) {
        var str = JSON.stringify(d);
        var matches = str.match(/https:\\/\\/[a-zA-Z0-9_\\-\\.]+\\.(googleusercontent\\.com|ggpht\\.com)\\/[a-zA-Z0-9_\\-=\\/]+/g);
        if (matches && matches.length > 0) {
          for (var i = 0; i < matches.length; i++) {
            var u = matches[i];
            if (u.indexOf('/yti/') !== -1 || u.indexOf('/a/') !== -1 || u.indexOf('=s') !== -1 || u.indexOf('/a-/') !== -1) {
              avatarSrc = u;
              break;
            }
          }
          if (!avatarSrc) avatarSrc = matches[0];
        }
      }
    } catch (e) {}

    // 2. Recursive DOM + Shadow DOM traversal searching for avatar img
    if (!avatarSrc) {
      try {
        function searchDom(node) {
          if (!node) return null;
          if (node.tagName === 'IMG') {
            var s = node.currentSrc || node.src || '';
            if (s.indexOf('googleusercontent.com') !== -1 || s.indexOf('ggpht.com') !== -1) {
              return s;
            }
          }
          if (node.shadowRoot) {
            var found = searchDom(node.shadowRoot);
            if (found) return found;
          }
          var children = node.children || node.childNodes || [];
          for (var j = 0; j < children.length; j++) {
            var f = searchDom(children[j]);
            if (f) return f;
          }
          return null;
        }
        avatarSrc = searchDom(document.body || document.documentElement);
      } catch (e) {}
    }

    // 3. Fallback: all images in document
    if (!avatarSrc) {
      try {
        var imgs = document.querySelectorAll('img');
        for (var k = 0; k < imgs.length; k++) {
          var isrc = imgs[k].src || imgs[k].getAttribute('src') || '';
          if (isrc.indexOf('googleusercontent.com') !== -1 || isrc.indexOf('ggpht.com') !== -1) {
            avatarSrc = isrc;
            break;
          }
        }
      } catch (e) {}
    }

    var btn = document.querySelector('#avatar-btn, ytmusic-settings-button button, button[aria-label*="Account"], button[aria-label*="Profile"]');
    var ariaLabel = btn ? (btn.getAttribute('aria-label') || btn.getAttribute('title')) : null;

    var loggedIn = false;
    if (window.ytcfg && window.ytcfg.get) {
      loggedIn = !!window.ytcfg.get('LOGGED_IN');
    }

    return JSON.stringify({
      loggedIn: String(loggedIn),
      pageId: get('DELEGATED_SESSION_ID'),
      dataSyncId: get('DATASYNC_ID'),
      authUser: get('SESSION_INDEX'),
      visitorData: get('VISITOR_DATA'),
      clientVersion: get('INNERTUBE_CLIENT_VERSION'),
      userName: get('USER_NAME') || get('USER_DISPLAY_NAME'),
      userEmail: get('USER_EMAIL'),
      domAvatar: avatarSrc,
      domLabel: ariaLabel
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
  bool _pageReady = false;

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
        ..setUserAgent(_userAgent)
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

  /// Gathers all native and JavaScript cookies across YouTube and Google domains,
  /// with YouTube tokens taking precedence over generic Google account tokens.
  Future<Map<String, String>> _collectAllCookies() async {
    final cookieJar = <String, String>{};

    try {
      final cm = _safeCookieManager;
      if (cm != null) {
        // 1. Collect Google accounts domains first
        final googleDomains = [
          Uri.parse('https://accounts.google.com'),
          Uri.parse('https://google.com'),
          Uri.parse('https://www.google.com'),
        ];

        for (final domain in googleDomains) {
          try {
            final cookies = await cm.getCookies(domain: domain);
            for (final c in cookies) {
              if (c.name.isNotEmpty && c.value.isNotEmpty) {
                cookieJar[c.name] = c.value;
              }
            }
          } catch (_) {}
        }

        // 2. Collect YouTube domains second so YouTube session cookies (LOGIN_INFO, SID, HSID, SSID)
        // override Google accounts cookies!
        final youtubeDomains = [
          Uri.parse('https://youtube.com'),
          Uri.parse('https://www.youtube.com'),
          Uri.parse('https://music.youtube.com'),
        ];

        for (final domain in youtubeDomains) {
          try {
            final cookies = await cm.getCookies(domain: domain);
            for (final c in cookies) {
              if (c.name.isNotEmpty && c.value.isNotEmpty) {
                cookieJar[c.name] = c.value;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error reading native cookie jar: $e');
    }

    // Also extract document.cookie from WebView context
    try {
      if (_webViewController != null) {
        final jsCookieRes = await _webViewController!
            .runJavaScriptReturningResult('document.cookie');
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
              cookieJar[name] = val; // Direct JS cookies take top priority
            }
          }
        }
      }
    } catch (_) {}

    return cookieJar;
  }

  /// Detects when navigation reaches YouTube Music with verified authentication cookies,
  /// extracts native session tokens & profile info, and connects the user's authentic account.
  Future<void> _checkSessionTransition(String url, {bool forceCapture = false}) async {
    if (_isAuthorizing || !mounted) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final isMusicYouTube = uri.host == 'music.youtube.com';
    if (!isMusicYouTube) {
      if (_pageReady && mounted) {
        setState(() => _pageReady = false);
      }
      return;
    }

    // Verify whether authentic login session cookies exist
    final cookieJar = await _collectAllCookies();
    final cookiesString = cookieJar.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    final sapisid = MusicService.extractSapisid(cookiesString);

    if (sapisid == null || sapisid.isEmpty) {
      return;
    }

    if (!_pageReady && mounted) {
      setState(() => _pageReady = true);
    }

    // Check if YouTube page has finished initializing LOGGED_IN state (BitChord pattern)
    bool isPageLoggedIn = false;
    try {
      if (_webViewController != null) {
        final probeResult = await _webViewController!.runJavaScriptReturningResult(
          '(function() { return String(!!(window.ytcfg && window.ytcfg.get && window.ytcfg.get("LOGGED_IN"))); })()',
        );
        isPageLoggedIn = probeResult.toString().replaceAll('"', '').trim() == 'true';
      }
    } catch (_) {}

    final hasLoginInfo = cookieJar.containsKey('LOGIN_INFO');

    // Only auto-capture when YouTube Music has genuinely finished login handshake.
    // If not yet ready, keep the "Use Account" button visible so user isn't rushed.
    if (!forceCapture && (!isPageLoggedIn && !hasLoginInfo)) {
      return;
    }

    if (!forceCapture) {
      // Small pause to allow multi-channel account switcher if needed
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _isAuthorizing) return;
    }

    setState(() {
      _isAuthorizing = true;
    });

    try {
      await _performAccountVerification(cookieJar, cookiesString);
    } catch (e) {
      debugPrint('Verification error: $e');
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to connect YouTube Music account. Please try again.',
            ),
            backgroundColor: Color(0xFF1C1C1E),
          ),
        );
      }
    }
  }

  Future<void> _performAccountVerification(
    Map<String, String> cookieJar,
    String cookiesString,
  ) async {
    // 1. Probe ytcfg & DOM for session metadata (BitChord probe)
    String? pageId;
    String? dataSyncId;
    String? authUser;
    String? visitorData;
    String? clientVersion;
    String? probedName;
    String? probedEmail;
    String? probedAvatar;

    try {
      if (_webViewController != null) {
        final probeResult = await _webViewController!
            .runJavaScriptReturningResult(_sessionProbeScript);
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
          dataSyncId = pageId ?? UserAccount.normalizeDataSyncId(probeJson['dataSyncId']?.toString());
          authUser = probeJson['authUser']?.toString();
          visitorData = probeJson['visitorData']?.toString();
          clientVersion = probeJson['clientVersion']?.toString();
          probedName = probeJson['userName']?.toString();
          probedEmail = probeJson['userEmail']?.toString();
          probedAvatar = probeJson['domAvatar']?.toString();

          if (probedName == null || probedName.isEmpty) {
            probedName = probeJson['domLabel']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Error probing ytcfg: $e');
    }

    // 2. Query InnerTube account_menu using SAPISIDHASH to retrieve verified profile
    final musicService = ref.read(musicServiceProvider);
    var profile = await musicService.fetchAccountProfile(
      cookies: cookiesString,
      dataSyncId: dataSyncId,
      pageId: pageId,
      authUser: authUser,
      visitorData: visitorData,
      clientVersion: clientVersion,
    );

    // If initial query was empty, retry once after a short delay
    if (profile == null) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      profile = await musicService.fetchAccountProfile(
        cookies: cookiesString,
        dataSyncId: dataSyncId,
        pageId: pageId,
        authUser: authUser,
        visitorData: visitorData,
        clientVersion: clientVersion,
      );
    }

    final displayName = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : (probedName != null && probedName.isNotEmpty
              ? probedName
              : 'YouTube Music User');
    final email = profile?.email.isNotEmpty == true
        ? profile!.email
        : (probedEmail ?? '');
    final avatarUrl = UserAccount.cleanAvatarUrl(profile?.avatarUrl ?? probedAvatar);

    // 3. Construct verified UserAccount model
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

    // 4. Persist account and trigger recommendations & liked songs refresh
    await ref.read(authProvider.notifier).signInWithGoogleAccount(account);

    if (!mounted) return;

    // 5. Navigate straight back to Home screen
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                  color: Colors.white,
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
                        color: Colors.white,
                      ),
                    ),
            ),

            // Bottom interactive confirmation bar once YouTube Music is reachable (BitChord flow)
            if (_pageReady && !_isAuthorizing)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.checkmark_alt,
                          color: Colors.greenAccent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'YouTube Music Ready',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Tap to connect this account',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final currentUrl = await _webViewController?.currentUrl() ?? 'https://music.youtube.com/';
                          _checkSessionTransition(currentUrl, forceCapture: true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Use Account',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Clean dark overlay while credentials and profile are being connected
            if (_isAuthorizing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.92),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(
                          radius: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Connecting YouTube Music...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Syncing profile and recommendations',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ],
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
