import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/user_account.dart';
import '../providers/auth_provider.dart';

/// Screen allowing users to sign in with their Google account to authorize
/// YouTube Music and receive personalized recommendations.
class GoogleSignInScreen extends ConsumerStatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleDarkSurface = Color(0xFF1C1C1E);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  WebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _isSuccessCaptured = false;
  String _currentUrl = 'https://accounts.google.com';

  // Standard Chrome mobile user agent so Google allows authentication
  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    try {
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
              _checkCookiesAndComplete(url);
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _currentUrl = url;
                });
              }
              _checkCookiesAndComplete(url);
            },
            onUrlChange: (change) {
              if (change.url != null) {
                _checkCookiesAndComplete(change.url!);
              }
            },
          ),
        )
        ..loadRequest(
          Uri.parse(
            'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com%2F',
          ),
        );

      _webViewController = controller;
    } catch (e) {
      debugPrint('WebView initialization failed (expected in test runtime): $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkCookiesAndComplete(String url) async {
    if (_isSuccessCaptured || !mounted) return;

    try {
      // Check if user has landed on YouTube Music or has session cookies
      if (url.contains('music.youtube.com') || url.contains('youtube.com')) {
        final cookies = await _extractCookiesFromWebview();

        if (cookies.isNotEmpty &&
            (cookies.contains('SAPISID') ||
                cookies.contains('LOGIN_INFO') ||
                cookies.contains('__Secure-3PAPISID') ||
                cookies.contains('SID'))) {
          _isSuccessCaptured = true;

          // Attempt to extract user's display name or avatar from page
          String displayName = 'Google User';
          String email = '';
          String? avatarUrl;

          try {
            final pageTitle = await _webViewController?.getTitle();
            if (pageTitle != null && pageTitle.isNotEmpty && pageTitle != 'YouTube Music') {
              displayName = pageTitle;
            }
          } catch (_) {}

          final account = UserAccount(
            id: 'google_ytm_${DateTime.now().millisecondsSinceEpoch}',
            displayName: displayName.isNotEmpty ? displayName : 'YouTube Music User',
            email: email,
            avatarUrl: avatarUrl,
            cookies: cookies,
            connectedAt: DateTime.now(),
            isPersonalizedEnabled: true,
          );

          if (!mounted) return;
          await ref.read(authProvider.notifier).signInWithGoogleAccount(account);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Signed in with Google! YouTube Music recommendations active.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: appleDarkSurface,
              duration: const Duration(seconds: 4),
            ),
          );

          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error inspecting cookies in webview: $e');
    }
  }

  Future<String> _extractCookiesFromWebview() async {
    if (_webViewController == null) return '';
    try {
      final jsCookies = await _webViewController!.runJavaScriptReturningResult(
        'document.cookie',
      );
      final raw = jsCookies.toString();
      // Remove enclosing quotes from javascript string result if any
      if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
        return raw.substring(1, raw.length - 1);
      }
      return raw;
    } catch (e) {
      debugPrint('Error reading document.cookie: $e');
      return '';
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
                const Icon(CupertinoIcons.lock_fill, color: Colors.greenAccent, size: 10),
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
        bottom: _isLoading
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
        child: Column(
          children: [
            // Informational badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1C1C1E),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.play_arrow_solid,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Sign into your Google account to sync your YouTube Music recommendations and mixes.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Embedded Google Sign-In WebView
            Expanded(
              child: _webViewController != null
                  ? WebViewWidget(controller: _webViewController!)
                  : const Center(
                      child: CircularProgressIndicator(color: appleRed),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
