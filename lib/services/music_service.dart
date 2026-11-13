import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/song_item.dart';
import '../models/album_item.dart';
import '../models/video_item.dart';
import '../models/hero_card_item.dart';
import '../models/music_category.dart';
import '../models/lyric_line.dart';
import '../models/home_data.dart';
import '../models/user_account.dart';
import '../models/playlist_item.dart';
import '../models/artist_details.dart';
import '../models/artist_item.dart';
import '../models/search_result_set.dart';import 'artwork_cache_service.dart';
import 'home_cache_service.dart';
import 'lyrics_service.dart';
import 'song_metrics_cache_service.dart';

/// Resolved audio stream data containing direct stream URL, matching User-Agent headers,
/// bitrate, and media format specifications.
class AudioStreamInfo {
  final String url;
  final Map<String, String> headers;
  final int bitrate;
  final String mimeType;
  final int? contentLength;
  final int? durationMs;

  const AudioStreamInfo({
    required this.url,
    required this.headers,
    required this.bitrate,
    required this.mimeType,
    this.contentLength,
    this.durationMs,
  });

  int? get durationSeconds =>
      durationMs != null && durationMs! > 0 ? durationMs! ~/ 1000 : null;
}

/// Resolved video stream data for crisp moving artwork / background video playback.
class VideoStreamInfo {
  final String url;
  final Map<String, String> headers;
  final int width;
  final int height;
  final String qualityLabel;

  const VideoStreamInfo({
    required this.url,
    required this.headers,
    required this.width,
    required this.height,
    required this.qualityLabel,
  });
}

/// Resolved animated artwork data (HD video stream or animated WebP loop).
class AnimatedArtworkData {
  final String url;
  final Map<String, String> headers;
  final bool isVideo;
  final int width;
  final int height;

  const AnimatedArtworkData({
    required this.url,
    this.headers = const {},
    this.isVideo = false,
    this.width = 1280,
    this.height = 720,
  });
}

/// Client configuration for InnerTube player requests, inspired by BitChord's PlayerClient.
class _InnerTubeClientConfig {
  final String clientName;
  final String clientVersion;
  final String userAgent;

  const _InnerTubeClientConfig({
    required this.clientName,
    required this.clientVersion,
    required this.userAgent,
  });
}

/// MusicService uses `dart_ytmusic_api` to:
/// 1. Search tracks and query metadata (`searchSongs`)
/// 2. Gather Home feed information: Trending tracks, Genres, Moods, and Quick picks (`getHomeData`)
/// 3. Extract and resolve robust, unthrottled streaming URLs using multi-client
///    InnerTube rotation (VISIONOS -> ANDROID_VR -> ANDROID -> IOS) with BitChord-style
///    stream validation and header dressing.
class MusicService {
  final YTMusic _ytMusic = YTMusic();
  bool _isInitialized = false;

  // Connected Google / YouTube Music account
  UserAccount? _currentAccount;

  UserAccount? get currentAccount => _currentAccount;

  // In-memory cache for dynamically resolved album cover artwork
  final Map<String, String> _albumArtworkCache = {};

  // In-memory cache for dynamically resolved animated artwork / GIF videos
  final Map<String, String?> _animatedArtworkCache = {};

  // In-memory cache for resolved animated artwork data (URL + headers + isVideo)
  final Map<String, AnimatedArtworkData?> _animatedArtworkDataCache = {};

  // In-memory cache for dynamically resolved HD video streams (720p/1080p MP4)
  final Map<String, VideoStreamInfo?> _videoStreamCache = {};

  // In-memory caches for search results to avoid re-fetching on tab switches
  final Map<String, SearchResultSet> _searchAllMemoryCache = {};
  final Map<String, List<SongItem>> _searchSongsMemoryCache = {};

  // Apple Music-style lyrics provider service (binimum/am-lyrics pipeline)
  final LyricsService _lyricsService = LyricsService();

  /// Sets or updates the connected Google account with YouTube Music authorization.
  void setAuthAccount(UserAccount? account) {
    _currentAccount = account;
    _cachedHomeData =
        null; // Clear cached feed so next fetch reflects account state

    final cookies = account?.cookies;
    if (cookies != null && cookies.isNotEmpty) {
      for (final raw in cookies.split(';')) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          final name = trimmed.substring(0, eqIdx).trim();
          final val = trimmed.substring(eqIdx + 1).trim();
          try {
            final cookie = Cookie(name, val);
            _ytMusic.cookieJar.saveFromResponse(
              Uri.parse('https://music.youtube.com/'),
              [cookie],
            );
            _ytMusic.cookieJar.saveFromResponse(
              Uri.parse('https://www.youtube.com/'),
              [cookie],
            );
          } catch (e) {
            debugPrint('Error saving cookie $name: $e');
          }
        }
      }
    }
  }

  /// Extracts SAPISID, __Secure-3PAPISID, or __Secure-1PAPISID from cookie header
  static String? extractSapisid(String cookies) {
    final jar = <String, String>{};
    for (final part in cookies.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final name = trimmed.substring(0, eq).trim();
        final val = trimmed.substring(eq + 1).trim();
        if (name.isNotEmpty && val.isNotEmpty) {
          jar[name] = val;
        }
      }
    }
    return jar['SAPISID'] ??
        jar['__Secure-3PAPISID'] ??
        jar['__Secure-1PAPISID'];
  }

  /// Sanitizes cookie header so that tokens with the same key take their latest
  /// and most specific value (e.g. YouTube session cookies over Google accounts cookies).
  static String sanitizeCookieStringForYouTube(String cookies) {
    if (cookies.isEmpty) return cookies;
    final jar = <String, String>{};
    for (final part in cookies.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final name = trimmed.substring(0, eq).trim();
        final val = trimmed.substring(eq + 1).trim();
        if (name.isNotEmpty && val.isNotEmpty) {
          jar[name] = val;
        }
      }
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Extracts the fresh, complete cookie jar from WebView with YouTube cookies
  /// taking precedence over generic Google cookies.
  static Future<String?> extractFreshCookiesFromWebView() async {
    try {
      WebViewCookieManager cm;
      try {
        cm = WebViewCookieManager();
      } catch (_) {
        return null;
      }

      final googleDomains = [
        Uri.parse('https://accounts.google.com'),
        Uri.parse('https://google.com'),
        Uri.parse('https://www.google.com'),
      ];
      final youtubeDomains = [
        Uri.parse('https://youtube.com'),
        Uri.parse('https://www.youtube.com'),
        Uri.parse('https://music.youtube.com'),
      ];

      final jar = <String, String>{};
      for (final domain in googleDomains) {
        try {
          final cookies = await cm.getCookies(domain: domain);
          for (final c in cookies) {
            if (c.name.isNotEmpty && c.value.isNotEmpty) {
              jar[c.name] = c.value;
            }
          }
        } catch (_) {}
      }

      for (final domain in youtubeDomains) {
        try {
          final cookies = await cm.getCookies(domain: domain);
          for (final c in cookies) {
            if (c.name.isNotEmpty && c.value.isNotEmpty) {
              jar[c.name] = c.value;
            }
          }
        } catch (_) {}
      }

      if (jar.isNotEmpty &&
          (jar.containsKey('SAPISID') ||
              jar.containsKey('__Secure-3PAPISID'))) {
        return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
    } catch (_) {}
    return null;
  }

  /// Computes SAPISIDHASH authorization header from a SAPISID token
  static String computeSapisidHash(
    String sapisid, {
    String origin = 'https://music.youtube.com',
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = '$timestamp $sapisid $origin';
    final digest = sha1.convert(utf8.encode(payload)).toString();
    return 'SAPISIDHASH ${timestamp}_$digest';
  }

  /// Computes SAPISIDHASH authorization header if authenticated with a Google account
  String? getSapisidHash({String origin = 'https://music.youtube.com'}) {
    final sapisid = _currentAccount?.sapisid;
    if (sapisid == null || sapisid.isEmpty) return null;
    return computeSapisidHash(sapisid, origin: origin);
  }

  /// Recursively collects all objects named [targetKey] anywhere inside a JSON structure
  static List<Map<String, dynamic>> _collectRenderers(
    dynamic root,
    String targetKey,
  ) {
    final results = <Map<String, dynamic>>[];
    void search(dynamic node) {
      if (node is List) {
        for (final item in node) {
          search(item);
        }
      } else if (node is Map<String, dynamic>) {
        for (final entry in node.entries) {
          if (entry.key == targetKey && entry.value is Map<String, dynamic>) {
            results.add(entry.value as Map<String, dynamic>);
          }
          search(entry.value);
        }
      } else if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == targetKey && entry.value is Map) {
            results.add(Map<String, dynamic>.from(entry.value as Map));
          }
          search(entry.value);
        }
      }
    }

    search(root);
    return results;
  }

  /// Extracts textual representation from YouTube runs, simpleText, nested flexColumn, or raw string
  static String _extractNodeText(dynamic node) {
    if (node == null) return '';
    if (node is String) return node.trim();

    if (node is List) {
      final buffer = StringBuffer();
      for (final item in node) {
        final text = _extractNodeText(item);
        if (text.isNotEmpty) {
          buffer.write(text);
        }
      }
      return buffer.toString().trim();
    }

    if (node is Map) {
      // 1. Direct simpleText
      if (node['simpleText'] is String &&
          (node['simpleText'] as String).trim().isNotEmpty) {
        return (node['simpleText'] as String).trim();
      }

      // 2. Direct runs list
      if (node['runs'] is List) {
        final buffer = StringBuffer();
        for (final r in node['runs'] as List) {
          if (r is Map && r['text'] != null) {
            buffer.write(r['text']);
          } else if (r is String) {
            buffer.write(r);
          }
        }
        final result = buffer.toString().trim();
        if (result.isNotEmpty) return result;
      }

      // 3. Nested musicResponsiveListItemFlexColumnRenderer
      if (node['musicResponsiveListItemFlexColumnRenderer'] != null) {
        final t = _extractNodeText(
          node['musicResponsiveListItemFlexColumnRenderer'],
        ).trim();
        if (t.isNotEmpty) return t;
      }

      // 4. Nested text container
      if (node['text'] != null) {
        final t = _extractNodeText(node['text']).trim();
        if (t.isNotEmpty) return t;
      }

      // 5. Nested title
      if (node['title'] != null) {
        final t = _extractNodeText(node['title']).trim();
        if (t.isNotEmpty) return t;
      }

      // 6. Nested headline
      if (node['headline'] != null) {
        final t = _extractNodeText(node['headline']).trim();
        if (t.isNotEmpty) return t;
      }

      // 7. Nested subtitle
      if (node['subtitle'] != null) {
        final t = _extractNodeText(node['subtitle']).trim();
        if (t.isNotEmpty) return t;
      }

      // 8. Formatted string
      if (node['formattedString'] != null) {
        final t = _extractNodeText(node['formattedString']).trim();
        if (t.isNotEmpty) return t;
      }

      // 9. Accessibility label fallback
      if (node['accessibility']?['accessibilityData']?['label'] is String) {
        final a11y =
            (node['accessibility']['accessibilityData']['label'] as String)
                .trim();
        if (a11y.isNotEmpty) return a11y;
      }
      if (node['accessibilityData']?['label'] is String) {
        final a11y = (node['accessibilityData']['label'] as String).trim();
        if (a11y.isNotEmpty) return a11y;
      }
    }

    return '';
  }

  /// Extracts the full metadata subtitle from a music renderer (e.g. musicTwoRowItemRenderer),
  /// including runs, straplines (episode count, like count, track count), badges, and a11y labels.
  static String _extractFullSubtitle(Map<String, dynamic> node) {
    final parts = <String>[];

    void addText(dynamic item) {
      final text = _extractNodeText(item).trim();
      if (text.isEmpty) return;
      // Split on bullet separators if present
      final segments = text.contains('•') || text.contains('·')
          ? text.split(RegExp(r'\s*[•·]\s*'))
          : [text];
      for (final s in segments) {
        final clean = s.trim();
        if (clean.isEmpty) continue;
        if (!parts.any((p) => p.toLowerCase() == clean.toLowerCase())) {
          parts.add(clean);
        }
      }
    }

    addText(node['subtitle']);
    addText(node['straplineTextOne']);
    addText(node['straplineTextTwo']);
    addText(node['subtitleCustomText']);

    // Check subtitleBadges
    final badges = node['subtitleBadges'];
    if (badges is List) {
      for (final b in badges) {
        if (b is Map) {
          final label = traverseString(b, [
            'musicInlineBadgeRenderer',
            'accessibilityData',
            'accessibilityData',
            'label',
          ]) ??
          traverseString(b, [
            'accessibilityData',
            'accessibilityData',
            'label',
          ]);
          if (label != null && label.trim().isNotEmpty) {
            addText(label);
          }
        }
      }
    }

    // Inspect accessibility label for extra metadata like episodes or likes
    final a11yLabel = traverseString(node, [
      'accessibility',
      'accessibilityData',
      'label',
    ]) ??
    traverseString(node, [
      'accessibilityData',
      'accessibilityData',
      'label',
    ]);
    if (a11yLabel != null && a11yLabel.trim().isNotEmpty) {
      final episodeMatch = RegExp(
        r'\b\d[\d,\.]*\s*(?:episodes?|eps?)\b',
        caseSensitive: false,
      ).firstMatch(a11yLabel);
      if (episodeMatch != null) {
        addText(episodeMatch.group(0)!);
      }
      final likesMatch = RegExp(
        r'\b\d[\d,\.]*\s*[KMBkmb]?\s*likes?\b',
        caseSensitive: false,
      ).firstMatch(a11yLabel);
      if (likesMatch != null) {
        addText(likesMatch.group(0)!);
      }
      final songsMatch = RegExp(
        r'\b\d[\d,\.]*\s*(?:songs?|tracks?)\b',
        caseSensitive: false,
      ).firstMatch(a11yLabel);
      if (songsMatch != null) {
        addText(songsMatch.group(0)!);
      }
    }

    return parts.join(' • ');
  }

  /// Extracts the highest resolution photo from an account renderer
  static String? _extractNodePhoto(Map<String, dynamic> item) {
    var photoObj = item['accountPhoto'] ?? item['thumbnail'];
    if (photoObj == null && item['thumbnailRenderer'] is Map) {
      photoObj =
          item['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail'];
    }
    if (photoObj is Map) {
      final thumbnails = photoObj['thumbnails'];
      if (thumbnails is List && thumbnails.isNotEmpty) {
        final last = thumbnails.last;
        if (last is Map && last['url'] != null) {
          String url = last['url'].toString();
          if (url.startsWith('//')) url = 'https:$url';
          // Upgrade thumbnail to higher resolution (256x256)
          if (url.contains('=s88') ||
              url.contains('=s64') ||
              url.contains('=s32')) {
            url = url.replaceAll(RegExp(r'=s\d+'), '=s256');
          }
          return url;
        }
      }
    }
    return null;
  }

  /// Parses YouTube Music account menu response to extract verified Google profile info
  static ({String displayName, String email, String? avatarUrl})?
  parseAccountMenu(dynamic data) {
    if (data == null) return null;

    final activeHeaders = _collectRenderers(
      data,
      'activeAccountHeaderRenderer',
    );
    if (activeHeaders.isNotEmpty) {
      final header = activeHeaders.first;
      final name = _extractNodeText(header['accountName']).trim();
      var email = _extractNodeText(header['email']).trim();
      if (email.isEmpty) {
        email = _extractNodeText(header['channelHandle']).trim();
      }
      final avatar = _extractNodePhoto(header);

      if (name.isNotEmpty || email.isNotEmpty) {
        return (
          displayName: name.isNotEmpty ? name : 'YouTube Music User',
          email: email,
          avatarUrl: avatar ?? _findAvatarInJson(data),
        );
      }
    }

    final accountItems = _collectRenderers(data, 'accountItem');
    if (accountItems.isNotEmpty) {
      final item = accountItems.first;
      final name = _extractNodeText(item['accountName']).trim();
      var email = _extractNodeText(item['email']).trim();
      if (email.isEmpty) {
        email = _extractNodeText(item['channelHandle']).trim();
      }
      if (email.isEmpty) {
        email = _extractNodeText(item['accountByline']).trim();
      }
      final avatar = _extractNodePhoto(item);

      if (name.isNotEmpty || email.isNotEmpty) {
        return (
          displayName: name.isNotEmpty ? name : 'YouTube Music User',
          email: email,
          avatarUrl: avatar ?? _findAvatarInJson(data),
        );
      }
    }

    // Fallback: If no structured header matched, search for user avatar URL in raw JSON
    final foundAvatar = _findAvatarInJson(data);
    if (foundAvatar != null) {
      return (
        displayName: 'YouTube Music User',
        email: '',
        avatarUrl: foundAvatar,
      );
    }

    return null;
  }

  /// Extracts Google avatar URL directly from JSON string as fallback
  static String? _findAvatarInJson(dynamic data) {
    if (data == null) return null;
    try {
      final raw = jsonEncode(data);
      final regex = RegExp(
        r'https:\/\/[a-zA-Z0-9_\-\.]+\.(googleusercontent\.com|ggpht\.com)\/[a-zA-Z0-9_\-=\/]+',
      );
      final matches = regex.allMatches(raw);
      for (final m in matches) {
        final u = m.group(0);
        if (u != null &&
            (u.contains('/yti/') ||
                u.contains('/a/') ||
                u.contains('=s') ||
                u.contains('/a-/'))) {
          return u;
        }
      }
      if (matches.isNotEmpty) {
        return matches.first.group(0);
      }
    } catch (_) {}
    return null;
  }

  /// Connects to YouTube Music InnerTube account_menu endpoint using authentic
  /// session cookies and SAPISIDHASH to retrieve the user's verified profile.
  /// Falls back to getAccountSwitcherEndpoint as in BitChord if needed.
  Future<({String displayName, String email, String? avatarUrl})?>
  fetchAccountProfile({
    required String cookies,
    String? dataSyncId,
    String? pageId,
    String? authUser,
    String? visitorData,
    String? clientVersion,
  }) async {
    final sapisid = extractSapisid(cookies);
    if (sapisid == null || sapisid.isEmpty) {
      debugPrint('fetchAccountProfile: No SAPISID found in cookies');
      return null;
    }

    final cleanCookies = sanitizeCookieStringForYouTube(cookies);
    final sapisidHash = computeSapisidHash(sapisid);
    final version = clientVersion ?? '1.20250101.01.00';
    final normalizedDataSync = UserAccount.normalizeDataSyncId(dataSyncId);

    // 1. Try InnerTube account/account_menu endpoint (as in BitChord)
    try {
      final uri = Uri.parse(
        'https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&hl=en',
      );
      final userContext = <String, dynamic>{'lockedSafetyMode': false};
      if (normalizedDataSync != null && normalizedDataSync.isNotEmpty) {
        userContext['onBehalfOfUser'] = normalizedDataSync;
      }

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': version,
            'hl': 'en',
            'gl': 'US',
            if (visitorData != null && visitorData.isNotEmpty)
              'visitorData': visitorData,
          },
          'user': userContext,
          'request': {'useSsl': true},
        },
      });

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      );
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set('X-Origin', 'https://music.youtube.com');
      request.headers.set('Origin', 'https://music.youtube.com');
      request.headers.set('Referer', 'https://music.youtube.com/');
      request.headers.set('X-YouTube-Client-Name', '67');
      request.headers.set('X-YouTube-Client-Version', version);
      request.headers.set('Cookie', cleanCookies);
      request.headers.set('Authorization', sapisidHash);
      request.headers.set('X-Goog-AuthUser', authUser ?? '0');
      if (pageId != null && pageId.isNotEmpty) {
        request.headers.set('X-Goog-PageId', pageId);
      }
      if (visitorData != null && visitorData.isNotEmpty) {
        request.headers.set('X-Goog-Visitor-Id', visitorData);
      }

      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        final responseBody = await utf8.decoder.bind(response).join();
        final data = jsonDecode(responseBody);
        final parsed = parseAccountMenu(data);
        if (parsed != null &&
            (parsed.displayName.isNotEmpty || parsed.avatarUrl != null)) {
          return (
            displayName: parsed.displayName,
            email: parsed.email,
            avatarUrl: UserAccount.cleanAvatarUrl(parsed.avatarUrl),
          );
        }
      } else {
        await response.drain();
        // If onBehalfOfUser was rejected, retry without it
        if (userContext.containsKey('onBehalfOfUser')) {
          userContext.remove('onBehalfOfUser');
          final retryBody = jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': version,
                'hl': 'en',
                'gl': 'US',
                if (visitorData != null && visitorData.isNotEmpty)
                  'visitorData': visitorData,
              },
              'user': userContext,
              'request': {'useSsl': true},
            },
          });
          final retryReq = await client.postUrl(uri);
          retryReq.headers.contentType = ContentType.json;
          retryReq.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
          );
          retryReq.headers.set('Accept-Language', 'en-US,en;q=0.9');
          retryReq.headers.set('X-Origin', 'https://music.youtube.com');
          retryReq.headers.set('Origin', 'https://music.youtube.com');
          retryReq.headers.set('Referer', 'https://music.youtube.com/');
          retryReq.headers.set('X-YouTube-Client-Name', '67');
          retryReq.headers.set('X-YouTube-Client-Version', version);
          retryReq.headers.set('Cookie', cookies);
          retryReq.headers.set('Authorization', sapisidHash);
          retryReq.headers.set('X-Goog-AuthUser', authUser ?? '0');
          retryReq.write(retryBody);
          final retryRes = await retryReq.close().timeout(
            const Duration(seconds: 8),
          );
          if (retryRes.statusCode == 200) {
            final retryStr = await utf8.decoder.bind(retryRes).join();
            final retryData = jsonDecode(retryStr);
            final parsedRetry = parseAccountMenu(retryData);
            if (parsedRetry != null &&
                (parsedRetry.displayName.isNotEmpty ||
                    parsedRetry.avatarUrl != null)) {
              return (
                displayName: parsedRetry.displayName,
                email: parsedRetry.email,
                avatarUrl: UserAccount.cleanAvatarUrl(parsedRetry.avatarUrl),
              );
            }
          } else {
            await retryRes.drain();
          }
        }
      }
      client.close(force: true);
    } catch (e) {
      debugPrint('fetchAccountProfile account_menu error: $e');
    }

    // 2. Fallback: Query getAccountSwitcherEndpoint on youtube.com (as in BitChord)
    try {
      final ytOrigin = 'https://www.youtube.com';
      final ytHash = computeSapisidHash(sapisid, origin: ytOrigin);
      final uri = Uri.parse('$ytOrigin/getAccountSwitcherEndpoint');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      );
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set('X-Origin', ytOrigin);
      request.headers.set('Referer', '$ytOrigin/');
      request.headers.set('Cookie', cleanCookies);
      request.headers.set('Authorization', ytHash);
      request.headers.set('X-Goog-AuthUser', authUser ?? '0');

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        var responseBody = await utf8.decoder.bind(response).join();
        if (responseBody.contains(")]}'")) {
          responseBody = responseBody
              .substring(responseBody.indexOf(")]}'") + 4)
              .trim();
        }
        final data = jsonDecode(responseBody);
        final parsed = parseAccountMenu(data);
        if (parsed != null &&
            (parsed.displayName.isNotEmpty || parsed.avatarUrl != null)) {
          return (
            displayName: parsed.displayName,
            email: parsed.email,
            avatarUrl: UserAccount.cleanAvatarUrl(parsed.avatarUrl),
          );
        }
      } else {
        await response.drain();
      }
      client.close(force: true);
    } catch (e) {
      debugPrint('fetchAccountProfile getAccountSwitcherEndpoint error: $e');
    }

    return null;
  }

  /// Parses standard duration strings ("MM:SS", "HH:MM:SS", embedded durations
  /// like "Song • 3:42", or accessibility labels like "3 minutes, 42 seconds")
  /// into total seconds. Returns `null` when no valid duration is found.
  static int? parseDurationString(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final trimmed = text.trim();

    // Match H:MM:SS or M:SS anywhere (handles "3:42", "03:42", "Song • 3:42")
    final clockMatch = RegExp(
      r'(?:^|\s|•|·|\()(\d{1,2}):(\d{2})(?::(\d{2}))?(?:$|\s|•|·|\))',
    ).firstMatch(trimmed);
    if (clockMatch != null) {
      final first = int.tryParse(clockMatch.group(1)!);
      final second = int.tryParse(clockMatch.group(2)!);
      final third = clockMatch.group(3) != null
          ? int.tryParse(clockMatch.group(3)!)
          : null;
      if (first != null && second != null && second < 60) {
        if (third != null && third < 60) {
          return (first * 3600) + (second * 60) + third;
        }
        if (clockMatch.group(3) == null) {
          return (first * 60) + second;
        }
      }
    }

    // Match verbose accessibility labels like "3 minutes, 42 seconds" or "1 hour, 2 minutes"
    final hMatch = RegExp(r'(\d+)\s*hours?').firstMatch(trimmed);
    final mMatch = RegExp(r'(\d+)\s*minutes?').firstMatch(trimmed);
    final sMatch = RegExp(r'(\d+)\s*seconds?').firstMatch(trimmed);
    if (hMatch != null || mMatch != null || sMatch != null) {
      final h = hMatch != null ? (int.tryParse(hMatch.group(1)!) ?? 0) : 0;
      final m = mMatch != null ? (int.tryParse(mMatch.group(1)!) ?? 0) : 0;
      final s = sMatch != null ? (int.tryParse(sMatch.group(1)!) ?? 0) : 0;
      final total = (h * 3600) + (m * 60) + s;
      return total > 0 ? total : null;
    }

    return null;
  }

  /// Extracts continuation token from browse / playlist response (BitChord style)
  static String? extractContinuationToken(dynamic root) {
    if (root == null) return null;
    final itemRenderers = _collectRenderers(root, 'continuationItemRenderer');
    for (final item in itemRenderers) {
      final endpoint = item['continuationEndpoint'];
      if (endpoint is Map) {
        final token = endpoint['continuationCommand']?['token'];
        if (token != null && token.toString().isNotEmpty) {
          return token.toString();
        }
        final commands = endpoint['commandExecutorCommand']?['commands'];
        if (commands is List && commands.isNotEmpty && commands.first is Map) {
          final subToken = commands.first['continuationCommand']?['token'];
          if (subToken != null && subToken.toString().isNotEmpty) {
            return subToken.toString();
          }
        }
      }
    }
    final nextCont = _collectRenderers(root, 'nextContinuationData');
    if (nextCont.isNotEmpty && nextCont.first['continuation'] != null) {
      return nextCont.first['continuation'].toString();
    }
    return null;
  }

  /// Extracts track duration in seconds from any InnerTube list-item renderer
  /// by inspecting `fixedColumns`, all `flexColumns`, `subtitle`, and accessibility labels.
  static int? extractDurationFromRenderer(Map<String, dynamic> item) {
    final fixedCols = item['fixedColumns'] as List? ?? [];
    for (final col in fixedCols) {
      if (col is! Map) continue;
      final fixedText = _extractNodeText(col);
      final parsed = parseDurationString(fixedText);
      if (parsed != null && parsed > 0) return parsed;

      final a11yLabel = traverseString(col, [
        'musicResponsiveListItemFixedColumnRenderer',
        'text',
        'accessibility',
        'accessibilityData',
        'label',
      ]);
      final a11yParsed = parseDurationString(a11yLabel);
      if (a11yParsed != null && a11yParsed > 0) return a11yParsed;
    }

    final flexCols = item['flexColumns'] as List? ?? [];
    for (var i = flexCols.length - 1; i >= 0; i--) {
      final col = flexCols[i];
      if (col is! Map) continue;
      final runs = traverseList(col, [
        'musicResponsiveListItemFlexColumnRenderer',
        'text',
        'runs',
      ]);
      for (var rIdx = runs.length - 1; rIdx >= 0; rIdx--) {
        final run = runs[rIdx];
        if (run is Map && run['text'] != null) {
          final parsed = parseDurationString(run['text'].toString());
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      final colText = _extractNodeText(col);
      final parsed = parseDurationString(colText);
      if (parsed != null && parsed > 0) return parsed;
    }

    final subParsed = parseDurationString(_extractNodeText(item['subtitle']));
    if (subParsed != null && subParsed > 0) return subParsed;

    final itemA11y = traverseString(item, [
      'accessibility',
      'accessibilityData',
      'label',
    ]);
    final itemA11yParsed = parseDurationString(itemA11y);
    if (itemA11yParsed != null && itemA11yParsed > 0) return itemA11yParsed;

    return null;
  }

  /// Parses a SongItem from a YouTube Music InnerTube musicResponsiveListItemRenderer
  static SongItem? parseSongFromRenderer(Map<String, dynamic> item) {
    final videoId =
        item['playlistItemData']?['videoId']?.toString() ??
        traverseString(item, [
          'overlay',
          'musicItemThumbnailOverlayRenderer',
          'content',
          'musicPlayButtonRenderer',
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]) ??
        traverseString(item, [
          'navigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]) ??
        traverseString(item, [
          'doubleTapCommand',
          'watchEndpoint',
          'videoId',
        ]) ??
        traverseString(item, [
          'menu',
          'menuRenderer',
          'topLevelButtons',
          'likeButtonRenderer',
          'target',
          'videoId',
        ]);
    if (videoId == null || videoId.isEmpty) return null;

    final flexCols = item['flexColumns'] as List? ?? [];
    String title = '';
    String artist = '';
    String? album;

    // 1. Extract song title from Column 0
    if (flexCols.isNotEmpty) {
      final t = _extractNodeText(flexCols[0]).trim();
      if (t.isNotEmpty && t.toLowerCase() != 'untitled') {
        title = t;
      }
    }

    // 2. Fallbacks for title if still missing or untitled
    if (title.isEmpty || title.toLowerCase() == 'untitled') {
      final travTitle = traverseString(item, [
        'flexColumns',
        'musicResponsiveListItemFlexColumnRenderer',
        'text',
        'runs',
        'text',
      ]);
      if (travTitle != null &&
          travTitle.trim().isNotEmpty &&
          travTitle.trim().toLowerCase() != 'untitled') {
        title = travTitle.trim();
      }
    }

    if (title.isEmpty || title.toLowerCase() == 'untitled') {
      final itemTitle = _extractNodeText(item['title']).trim();
      if (itemTitle.isNotEmpty && itemTitle.toLowerCase() != 'untitled') {
        title = itemTitle;
      }
    }

    if (title.isEmpty || title.toLowerCase() == 'untitled') {
      final a11y =
          traverseString(item, [
            'overlay',
            'musicItemThumbnailOverlayRenderer',
            'content',
            'musicPlayButtonRenderer',
            'accessibilityPlayData',
            'accessibilityData',
            'label',
          ]) ??
          traverseString(item, [
            'accessibility',
            'accessibilityData',
            'label',
          ]) ??
          traverseString(item, ['accessibilityData', 'label']);
      if (a11y != null && a11y.trim().isNotEmpty) {
        var clean = a11y.trim().replaceFirst(
          RegExp(r'^Play\s+', caseSensitive: false),
          '',
        );
        if (clean.contains(' by ')) {
          final parts = clean.split(' by ');
          title = parts[0].trim();
          if (artist.isEmpty) {
            artist = parts[1].split(' • ')[0].split(' · ')[0].trim();
          }
        } else if (clean.contains(' • ')) {
          title = clean.split(' • ')[0].trim();
        } else if (clean.toLowerCase() != 'untitled') {
          title = clean;
        }
      }
    }

    // Discard item if no title was available so it never appears as 'Untitled' in the UI
    if (title.isEmpty || title.toLowerCase() == 'untitled') {
      return null;
    }

    // 3. Extract artist and album from Column 1
    if (flexCols.length > 1) {
      final col1 = flexCols[1];
      final runs = traverseList(col1, [
        'musicResponsiveListItemFlexColumnRenderer',
        'text',
        'runs',
      ]);
      if (runs.isNotEmpty) {
        final artistParts = <String>[];
        final albumParts = <String>[];
        int separatorCount = 0;

        for (final r in runs) {
          if (r is! Map) continue;
          final runText = (r['text'] ?? '').toString();
          if (runText.contains('•') || runText.contains('·')) {
            separatorCount++;
            continue;
          }
          if (separatorCount == 0) {
            artistParts.add(runText);
          } else if (separatorCount == 1) {
            if (parseDurationString(runText) == null) {
              albumParts.add(runText);
            }
          }
        }

        final combinedArtist = artistParts.join().trim();
        if (combinedArtist.isNotEmpty) {
          artist = combinedArtist;
        }
        final combinedAlbum = albumParts.join().trim();
        if (combinedAlbum.isNotEmpty) {
          album = combinedAlbum;
        }
      }

      if (artist.isEmpty || artist == 'Unknown Artist') {
        final fallbackArtist = _extractNodeText(col1).trim();
        if (fallbackArtist.isNotEmpty) {
          artist = fallbackArtist.split('•')[0].split('·')[0].trim();
        }
      }
    }

    if (artist.isEmpty) {
      final sub = _extractNodeText(item['subtitle']).trim();
      if (sub.isNotEmpty) {
        artist = sub.split('•')[0].split('·')[0].trim();
      }
    }

    final int? duration = extractDurationFromRenderer(item);

    String? thumb;
    final itemThumbs = traverseList(item, [
      'thumbnail',
      'musicThumbnailRenderer',
      'thumbnail',
      'thumbnails',
    ]);
    if (itemThumbs.isNotEmpty &&
        itemThumbs.last is Map &&
        itemThumbs.last['url'] != null) {
      thumb = SongItem.upgradeThumbnail(itemThumbs.last['url'].toString());
    }

    final sanitizedArtist = SongItem.sanitizeArtist(artist);
    final sanitizedTitle = SongItem.sanitizeTitle(title, sanitizedArtist);

    return SongItem(
      id: videoId,
      title: sanitizedTitle,
      artist: sanitizedArtist,
      thumbnailUrl: thumb,
      album: album,
      durationSeconds: duration,
    );
  }

  /// Sends an authenticated InnerTube POST request using session cookies and SAPISIDHASH
  Future<dynamic> postInnerTube(
    String endpoint, {
    Map<String, dynamic>? bodyExtras,
    Map<String, String>? queryParams,
  }) async {
    final account = _currentAccount;
    final isAuthenticated =
        account != null &&
        account.sapisid != null &&
        account.sapisid!.isNotEmpty;

    final version = '1.20250101.01.00';
    final query = <String, String>{
      'prettyPrint': 'false',
      'hl': 'en',
      ...?queryParams,
    };
    final uri = Uri.parse('https://music.youtube.com/youtubei/v1/$endpoint')
        .replace(queryParameters: query);

    final normalizedDataSync = account != null
        ? UserAccount.normalizeDataSyncId(account.dataSyncId)
        : null;
    final userContext = <String, dynamic>{'lockedSafetyMode': false};
    if (normalizedDataSync != null && normalizedDataSync.isNotEmpty) {
      userContext['onBehalfOfUser'] = normalizedDataSync;
    }

    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': version,
          'hl': 'en',
          'gl': 'US',
          if (account?.visitorData != null && account!.visitorData!.isNotEmpty)
            'visitorData': account.visitorData,
        },
        'user': userContext,
        'request': {'useSsl': true},
      },
      ...?bodyExtras,
    };

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      );
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set('X-Origin', 'https://music.youtube.com');
      request.headers.set('Origin', 'https://music.youtube.com');
      request.headers.set('Referer', 'https://music.youtube.com/');
      request.headers.set('X-YouTube-Client-Name', '67');
      request.headers.set('X-YouTube-Client-Version', version);

      if (isAuthenticated) {
        final sapisidHash = computeSapisidHash(account.sapisid!);
        request.headers.set('Cookie', account.cookies);
        request.headers.set('Authorization', sapisidHash);
        request.headers.set('X-Goog-AuthUser', account.authUser ?? '0');
        if (account.pageId != null && account.pageId!.isNotEmpty) {
          request.headers.set('X-Goog-PageId', account.pageId!);
        }
        if (account.visitorData != null && account.visitorData!.isNotEmpty) {
          request.headers.set('X-Goog-Visitor-Id', account.visitorData!);
        }
      }

      request.write(jsonEncode(payload));

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        debugPrint('postInnerTube ($endpoint) returned ${response.statusCode}');
        await response.drain();
        return null;
      }

      final responseBody = await utf8.decoder.bind(response).join();
      return jsonDecode(responseBody);
    } catch (e) {
      debugPrint('postInnerTube error ($endpoint): $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Paginates InnerTube browse endpoint using continuation token
  Future<dynamic> browseContinuation(String token) async {
    return postInnerTube(
      'browse',
      queryParams: {'ctoken': token, 'continuation': token, 'type': 'next'},
      bodyExtras: {'continuation': token},
    );
  }

  // Cached streams to prevent duplicate Innertube player requests (5 min TTL)
  final Map<String, ({AudioStreamInfo info, DateTime timestamp})> _streamCache =
      {};

  // Cached artist details to prevent repeated parsing and provide instant loads (15 min TTL)
  final Map<String, ({ArtistDetails details, DateTime timestamp})>
  _artistDetailsCache = {};

  // Cached home feed data
  HomeData? _cachedHomeData;

  // Client tiers ordered by reliability and lack of PoToken/throttling barriers
  static const List<_InnerTubeClientConfig> _clientTiers = [
    // Tier 1: VISIONOS - Does not require BotGuard/PoToken, provides full AAC streams,
    // and serves unthrottled media without 403 dropoffs.
    _InnerTubeClientConfig(
      clientName: 'VISIONOS',
      clientVersion: '1.02',
      userAgent:
          'com.google.visionos.youtube/1.02 (Apple Vision; visionOS 1.0)',
    ),
    // Tier 2: ANDROID_VR - Oculus/Meta Quest client, direct streamingData
    _InnerTubeClientConfig(
      clientName: 'ANDROID_VR',
      clientVersion: '1.65.10',
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; Build/SQ3A.220605.009.A1) gzip',
    ),
    // Tier 3: ANDROID - Native YouTube Android client
    _InnerTubeClientConfig(
      clientName: 'ANDROID',
      clientVersion: '20.10.38',
      userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US; Pixel 7 Pro) gzip',
    ),
    // Tier 4: IOS - Native iOS client
    _InnerTubeClientConfig(
      clientName: 'IOS',
      clientVersion: '20.10.4',
      userAgent: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    ),
  ];

  /// Initializes the YouTube Music API client.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _ytMusic.initialize();
    _isInitialized = true;
  }

  /// Gathers all information for the home screen matching Apple Music layout:
  /// - Top picks hero cards
  /// - Recents / Listen again (4-row column batches)
  /// - Find Your Mood
  /// - Albums & singles
  /// - Music videos (16:9 widescreen)
  /// - Quick picks (4-row column batches)
  /// - Your daily discover
  /// - Trending songs for you
  Future<HomeData> getHomeData({bool refresh = false}) async {
    if (!refresh) {
      if (_cachedHomeData != null) {
        return _cachedHomeData!;
      }
      final diskCached = await HomeCacheService.instance.loadHomeData();
      if (diskCached != null && !diskCached.isEmpty) {
        _cachedHomeData = diskCached;
        SongMetricsCacheService.instance.precacheTracks([
          ...diskCached.recents.take(3),
          ...diskCached.quickPicks.take(3),
        ], this);
        return diskCached;
      }
    }

    if (!_isInitialized) {
      await initialize();
    }

    // When signed in with a Google YouTube Music account and personalization is enabled,
    // fetch recommendations and mixes specific to that user's account.
    if (_currentAccount != null && _currentAccount!.isPersonalizedEnabled) {
      final personalData = await _fetchPersonalizedHomeData();
      if (personalData != null && !personalData.isEmpty) {
        _cachedHomeData = personalData;
        await HomeCacheService.instance.saveHomeData(personalData);
        ArtworkCacheService.instance.prefetchArtworks(personalData.recents);
        SongMetricsCacheService.instance.precacheTracks([
          ...personalData.recents.take(3),
          ...personalData.quickPicks.take(3),
        ], this);
        return personalData;
      }
    }

    // Always fetch raw, dynamic data from YouTube Music API (no hardcoded data)
    final homeData = await _fetchRawYouTubeHomeData();

    _cachedHomeData = homeData;
    await HomeCacheService.instance.saveHomeData(homeData);
    ArtworkCacheService.instance.prefetchArtworks(homeData.recents);
    SongMetricsCacheService.instance.precacheTracks([
      ...homeData.recents.take(3),
      ...homeData.quickPicks.take(3),
    ], this);
    return homeData;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ITEM EXTRACTORS  (musicTwoRowItemRenderer → PlaylistItem / AlbumItem / ArtistItem)
  // ─────────────────────────────────────────────────────────────────────────

  /// Parses a PlaylistItem from a musicTwoRowItemRenderer node.
  static PlaylistItem? _parseTwoRowPlaylist(Map<String, dynamic> twoRow) {
    final title = _extractNodeText(twoRow['title']).trim();
    if (title.isEmpty) return null;
    final fullSubtitle = _extractFullSubtitle(twoRow);
    final thumb = _extractNodePhoto(twoRow);
    final browseId = traverseString(twoRow, [
      'navigationEndpoint',
      'browseEndpoint',
      'browseId',
    ]);
    if (browseId == null || browseId.isEmpty) return null;

    int? trackCount;
    final trackMatch = RegExp(r'\b(\d+)\s*(?:songs?|tracks?)\b', caseSensitive: false)
        .firstMatch(fullSubtitle);
    if (trackMatch != null) {
      trackCount = int.tryParse(trackMatch.group(1)!);
    }

    return PlaylistItem(
      id: browseId,
      title: title,
      author: fullSubtitle.isNotEmpty ? fullSubtitle : 'Playlist',
      thumbnailUrl: thumb,
      trackCount: trackCount,
    );
  }

  /// Parses an AlbumItem from a musicTwoRowItemRenderer node.
  static AlbumItem? _parseTwoRowAlbum(
    Map<String, dynamic> twoRow, {
    String type = 'Album',
  }) {
    final title = _extractNodeText(twoRow['title']).trim();
    if (title.isEmpty) return null;
    final fullSubtitle = _extractFullSubtitle(twoRow);
    final thumb = _extractNodePhoto(twoRow);
    final browseId = traverseString(twoRow, [
      'navigationEndpoint',
      'browseEndpoint',
      'browseId',
    ]);
    if (browseId == null || browseId.isEmpty) return null;

    // Extract year from fullSubtitle (e.g. "2024 • Single")
    int? year;
    final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(fullSubtitle);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(0)!);
    }

    // Determine album type from fullSubtitle
    String resolvedType = type;
    final subtitleLower = fullSubtitle.toLowerCase();
    if (subtitleLower.contains('single')) {
      resolvedType = 'Single';
    } else if (subtitleLower.contains('ep')) {
      resolvedType = 'EP';
    } else if (subtitleLower.contains('album')) {
      resolvedType = 'Album';
    } else if (subtitleLower.contains('podcast')) {
      resolvedType = 'Podcast';
    }

    // Extract track count if present (e.g. "12 tracks" or "48 episodes")
    int? trackCount;
    final trackMatch = RegExp(r'\b(\d+)\s*(?:songs?|tracks?|episodes?|eps?)\b', caseSensitive: false)
        .firstMatch(fullSubtitle);
    if (trackMatch != null) {
      trackCount = int.tryParse(trackMatch.group(1)!);
    }

    // Artist name is usually in the first non-type part of the subtitle
    final parts = fullSubtitle.split('•').map((s) => s.trim()).toList();
    String artistName = '';
    for (final p in parts) {
      final pLower = p.toLowerCase();
      if (pLower == 'album' ||
          pLower == 'single' ||
          pLower == 'ep' ||
          pLower == 'podcast' ||
          pLower == 'playlist') {
        continue;
      }
      if (RegExp(r'^\d{4}$').hasMatch(p)) continue;
      if (RegExp(r'^\d+\s*(?:episodes?|songs?|tracks?|likes?)', caseSensitive: false).hasMatch(p)) continue;
      artistName = p;
      break;
    }
    if (artistName.isEmpty && parts.isNotEmpty) {
      artistName = parts.first;
    }

    return AlbumItem(
      id: browseId,
      title: title,
      artist: artistName.isNotEmpty ? artistName : 'Unknown Artist',
      thumbnailUrl: thumb,
      type: resolvedType,
      year: year,
      description: fullSubtitle.isNotEmpty ? fullSubtitle : null,
      trackCount: trackCount,
      isCustom: false,
    );
  }

  /// Parses an ArtistItem from a musicTwoRowItemRenderer node.
  static ArtistItem? _parseTwoRowArtist(Map<String, dynamic> twoRow) {
    final title = _extractNodeText(twoRow['title']).trim();
    if (title.isEmpty) return null;
    final fullSubtitle = _extractFullSubtitle(twoRow);
    final thumb = _extractNodePhoto(twoRow);
    final browseId = traverseString(twoRow, [
      'navigationEndpoint',
      'browseEndpoint',
      'browseId',
    ]);
    final id = browseId ?? 'artist_${title.hashCode}';

    return ArtistItem(
      id: id,
      name: title,
      thumbnailUrl: thumb,
      subscribers: fullSubtitle.isNotEmpty ? fullSubtitle : null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERSONALIZED HOME DATA FETCHER
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches a fully personalized home feed using the authenticated user's
  /// YouTube Music account.
  ///
  /// Preserves every single real shelf from `FEmusic_home` in authentic order
  /// inside [HomeData.dynamicSections], with their exact titles, subtitles, and
  /// appropriate layout (4-item song columns, square cards, 16:9 widescreen videos),
  /// matching the BitChord experience.
  ///
  /// Top Picks Hero Cards are assembled in the exact 8-slot canonical order:
  ///   1. New from followed artist (Single / Album)
  ///   2. Featuring [Artist]
  ///   3. Discovery Station (radial pattern + 3-wave logo)
  ///   4. Featuring [Artist] & Similar Artists (3 circular avatars on magenta background)
  ///   5. A Mood for You (neon green with lightning bolt)
  ///   6. Another Featuring [Artist] & Similar Artists (orange background)
  ///   7. New Release Mix
  ///   8. [User]'s Station
  Future<HomeData?> _fetchPersonalizedHomeData() async {
    final userName = _currentAccount?.displayName ?? 'You';

    // Buckets ─────────────────────────────────────────────────────────────
    final dynamicSections = <HomeSectionData>[];
    final recents = <SongItem>[];
    final quickPicks = <SongItem>[];
    final albumsAndSingles = <AlbumItem>[];
    final musicVideos = <VideoItem>[];
    final trendingSongs = <SongItem>[];
    final dailyDiscover = <SongItem>[];
    final followedArtistNewReleases = <AlbumItem>[];
    final featuredArtists = <ArtistItem>[];
    final featuredPlaylists = <PlaylistItem>[];
    final mixedForYou = <PlaylistItem>[];
    final myMixes = <PlaylistItem>[];
    final seenSongIds = <String>{};
    PlaylistItem? userStation;
    PlaylistItem? newReleaseMix;
    SongItem? discoveryStation;

    // ─── Helper: deduplicated song add ───────────────────────────────────
    void addSong(List<SongItem> bucket, SongItem song) {
      if (seenSongIds.add(song.id)) {
        bucket.add(song);
      }
    }

    try {
      // ═══════════════════════════════════════════════════════════════════
      // STEP 1 — FEmusic_history: authentic recent listens
      // ═══════════════════════════════════════════════════════════════════
      try {
        final historyJson = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': 'FEmusic_history'},
        );
        if (historyJson != null) {
          for (final r in _collectRenderers(
            historyJson,
            'musicResponsiveListItemRenderer',
          )) {
            final s = parseSongFromRenderer(r);
            if (s != null) {
              addSong(recents, s);
            }
          }
        }
      } catch (e) {
        debugPrint('_fetchPersonalized: FEmusic_history error: $e');
      }

      // ═══════════════════════════════════════════════════════════════════
      // STEP 2 — FEmusic_home: parse ALL live shelves dynamically (with continuations)
      // ═══════════════════════════════════════════════════════════════════
      try {
        final allHomeResponses = <dynamic>[];
        final homeJson = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': 'FEmusic_home'},
        );
        if (homeJson != null) {
          allHomeResponses.add(homeJson);
          var continuationToken = extractContinuationToken(homeJson) ??
              traverseString(homeJson, ['continuation']);
          int continuationCount = 0;
          while (continuationToken != null &&
              continuationToken.isNotEmpty &&
              continuationCount < 5) {
            continuationCount++;
            try {
              final nextJson = await postInnerTube(
                'browse',
                queryParams: {'continuation': continuationToken},
                bodyExtras: {'continuation': continuationToken},
              );
              if (nextJson == null) break;
              allHomeResponses.add(nextJson);
              continuationToken = extractContinuationToken(nextJson) ??
                  traverseString(nextJson, ['continuation']);
            } catch (_) {
              break;
            }
          }
        }

        final shelves = <Map<String, dynamic>>[];
        for (final resp in allHomeResponses) {
          shelves.addAll(_collectRenderers(resp, 'musicCarouselShelfRenderer'));
          shelves.addAll(_collectRenderers(resp, 'musicShelfRenderer'));
        }

        final seenShelfTitles = <String>{};

        for (final shelf in shelves) {
          String rawTitle = '';
          String rawSubtitle = '';

          if (shelf['header']?['musicCarouselShelfBasicHeaderRenderer'] is Map) {
            final header =
                shelf['header']['musicCarouselShelfBasicHeaderRenderer'];
            rawTitle = _extractNodeText(header['title']).trim();
            final strapline = _extractNodeText(header['strapline']).trim();
            final sub = _extractNodeText(header['subtitle']).trim();
            rawSubtitle = strapline.isNotEmpty ? strapline : sub;
          } else if (shelf['header']?['musicShelfBasicHeaderRenderer'] is Map) {
            final header = shelf['header']['musicShelfBasicHeaderRenderer'];
            rawTitle = _extractNodeText(header['title']).trim();
            final strapline = _extractNodeText(header['strapline']).trim();
            final sub = _extractNodeText(header['subtitle']).trim();
            rawSubtitle = strapline.isNotEmpty ? strapline : sub;
          } else if (shelf['title'] != null) {
            rawTitle = _extractNodeText(shelf['title']).trim();
            if (shelf['subtitle'] != null) {
              rawSubtitle = _extractNodeText(shelf['subtitle']).trim();
            }
          }

          if (rawTitle.isEmpty) continue;
          final titleLower = rawTitle.toLowerCase();
          if (!seenShelfTitles.add(titleLower)) continue;
            final items = (shelf['contents'] as List?) ?? const [];

            final shelfSongsList = <SongItem>[];
            final shelfAlbumsList = <AlbumItem>[];
            final shelfPlaylistsList = <PlaylistItem>[];
            final shelfVideosList = <VideoItem>[];

            for (final it in items) {
              if (it is! Map) continue;
              if (it['musicResponsiveListItemRenderer'] is Map) {
                final s = parseSongFromRenderer(
                  it['musicResponsiveListItemRenderer'] as Map<String, dynamic>,
                );
                if (s != null) {
                  shelfSongsList.add(s);
                }
              } else if (it['musicTwoRowItemRenderer'] is Map) {
                final twoRow =
                    it['musicTwoRowItemRenderer'] as Map<String, dynamic>;
                final videoId = traverseString(
                  twoRow,
                  ['navigationEndpoint', 'watchEndpoint', 'videoId'],
                );
                final browseId = traverseString(
                  twoRow,
                  ['navigationEndpoint', 'browseEndpoint', 'browseId'],
                );
                final itemTitle = _extractNodeText(twoRow['title']).trim();
                final itemSubtitle =
                    _extractNodeText(twoRow['subtitle']).trim();
                final thumb = _extractNodePhoto(twoRow);

                final isVideo = titleLower.contains('video') ||
                    titleLower.contains('performance') ||
                    (videoId != null && videoId.isNotEmpty && browseId == null);

                if (isVideo &&
                    videoId != null &&
                    videoId.isNotEmpty &&
                    itemTitle.isNotEmpty) {
                  shelfVideosList.add(VideoItem(
                    id: videoId,
                    title: itemTitle,
                    artist: itemSubtitle.isNotEmpty
                        ? itemSubtitle
                        : 'Unknown Artist',
                    thumbnailUrl: thumb,
                  ));
                } else if (browseId != null && browseId.isNotEmpty) {
                  if (browseId.startsWith('MPREb') ||
                      browseId.contains('album') ||
                      titleLower.contains('album') ||
                      titleLower.contains('single') ||
                      titleLower.contains('release')) {
                    final alb = _parseTwoRowAlbum(twoRow);
                    if (alb != null) {
                      shelfAlbumsList.add(alb);
                    }
                  } else {
                    final pl = _parseTwoRowPlaylist(twoRow);
                    if (pl != null) {
                      shelfPlaylistsList.add(pl);
                    }
                  }
                } else if (videoId != null &&
                    videoId.isNotEmpty &&
                    itemTitle.isNotEmpty) {
                  final cleanArt = SongItem.sanitizeArtist(itemSubtitle);
                  final s = SongItem(
                    id: videoId,
                    title: SongItem.sanitizeTitle(itemTitle, cleanArt),
                    artist: cleanArt.isNotEmpty ? cleanArt : 'YouTube Music',
                    thumbnailUrl: thumb,
                  );
                  shelfSongsList.add(s);
                }

                // Also inspect artist cards
                final artist = _parseTwoRowArtist(twoRow);
                if (artist != null &&
                    !featuredArtists.any((a) => a.id == artist.id)) {
                  featuredArtists.add(artist);
                }
              }
            }

            // Route items into section layouts
            if (shelfSongsList.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_${dynamicSections.length}',
                title: rawTitle,
                subtitle: rawSubtitle.isNotEmpty ? rawSubtitle : null,
                layout: HomeSectionLayout.songColumns,
                songs: shelfSongsList,
              ));

              for (final s in shelfSongsList) {
                if (titleLower.contains('recent') ||
                    titleLower.contains('listen again')) {
                  addSong(recents, s);
                } else if (titleLower.contains('trend')) {
                  addSong(trendingSongs, s);
                } else if (titleLower.contains('discover') ||
                    titleLower.contains('community')) {
                  addSong(dailyDiscover, s);
                  discoveryStation ??= s;
                } else {
                  addSong(quickPicks, s);
                }
              }
            } else if (shelfVideosList.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_${dynamicSections.length}',
                title: rawTitle,
                subtitle: rawSubtitle.isNotEmpty ? rawSubtitle : null,
                layout: HomeSectionLayout.videoCards,
                videos: shelfVideosList,
              ));
              musicVideos.addAll(shelfVideosList);
            } else if (shelfAlbumsList.isNotEmpty ||
                shelfPlaylistsList.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_${dynamicSections.length}',
                title: rawTitle,
                subtitle: rawSubtitle.isNotEmpty ? rawSubtitle : null,
                layout: HomeSectionLayout.squareCards,
                albums: shelfAlbumsList,
                playlists: shelfPlaylistsList,
              ));
              albumsAndSingles.addAll(shelfAlbumsList);
              if (titleLower.contains('new from') ||
                  titleLower.contains('new release') ||
                  titleLower.contains('new album') ||
                  titleLower.contains('new single')) {
                followedArtistNewReleases.addAll(shelfAlbumsList);
              }
              if (titleLower.contains('supermix') ||
                  titleLower.contains('mixed for you')) {
                mixedForYou.addAll(shelfPlaylistsList);
              } else if (titleLower.contains('my mix')) {
                myMixes.addAll(shelfPlaylistsList);
              } else if (titleLower.contains('featured playlist')) {
                featuredPlaylists.addAll(shelfPlaylistsList);
              }

              for (final pl in shelfPlaylistsList) {
                final plLower = pl.title.toLowerCase();
                if (plLower.contains('new release mix')) {
                  newReleaseMix ??= pl;
                } else if (plLower.contains('station') &&
                    !plLower.contains('discover')) {
                  userStation ??= pl;
                }
              }
            }
          }
        } catch (e) {
        debugPrint('_fetchPersonalized: FEmusic_home error: $e');
      }

      // Ensure "Recents" is at the top of dynamicSections if available from history
      if (recents.isNotEmpty &&
          !dynamicSections.any(
            (s) =>
                s.title.toLowerCase().contains('recent') ||
                s.title.toLowerCase().contains('listen again'),
          )) {
        dynamicSections.insert(
          0,
          HomeSectionData(
            id: 'shelf_recents',
            title: 'Recents',
            layout: HomeSectionLayout.songColumns,
            songs: recents,
          ),
        );
      }

      // ═══════════════════════════════════════════════════════════════════
      // STEP 3 — getHomeSections() as supplementary fallback if empty
      // ═══════════════════════════════════════════════════════════════════
      if (dynamicSections.isEmpty) {
        try {
          final sections = await _ytMusic.getHomeSections();
          for (final section in sections) {
            final title = section.title.trim();
            if (title.isEmpty) continue;
            final songs = _extractSongsFromHomeSection(section);
            final albs = _extractAlbumsFromHomeSection(section);
            final vids = _extractVideosFromHomeSection(section);
            final pls = _extractPlaylistsFromHomeSection(section);

            if (songs.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_fallback_${dynamicSections.length}',
                title: title,
                layout: HomeSectionLayout.songColumns,
                songs: songs,
              ));
              for (final s in songs) {
                addSong(quickPicks, s);
              }
            } else if (vids.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_fallback_${dynamicSections.length}',
                title: title,
                layout: HomeSectionLayout.videoCards,
                videos: vids,
              ));
              musicVideos.addAll(vids);
            } else if (albs.isNotEmpty || pls.isNotEmpty) {
              dynamicSections.add(HomeSectionData(
                id: 'shelf_fallback_${dynamicSections.length}',
                title: title,
                layout: HomeSectionLayout.squareCards,
                albums: albs,
                playlists: pls,
              ));
              albumsAndSingles.addAll(albs);
              featuredPlaylists.addAll(pls);
            }
          }
        } catch (e) {
          debugPrint('_fetchPersonalized: getHomeSections error: $e');
        }
      }

      // ═══════════════════════════════════════════════════════════════════
      // STEP 4 — Compose the exact 8 Top Picks Hero Cards (matching video)
      // ═══════════════════════════════════════════════════════════════════
      final orderedHeroCards = <HeroCardItem>[];
      final cleanFollowed = followedArtistNewReleases
          .where((a) => !a.title.toLowerCase().contains('liked music'))
          .toList();
      final cleanAlbums = albumsAndSingles
          .where((a) => !a.title.toLowerCase().contains('liked music'))
          .toList();

      // 1. New from followed artist (Single / Album)
      final followedRel = cleanFollowed.isNotEmpty
          ? cleanFollowed.first
          : (cleanAlbums.isNotEmpty ? cleanAlbums.first : null);
      if (followedRel != null) {
        orderedHeroCards.add(HeroCardItem(
          id: 'hero_new_${followedRel.id}',
          title: followedRel.title,
          subtitle: 'New from ${followedRel.artist}',
          caption:
              '${followedRel.type} • ${followedRel.year ?? DateTime.now().year}',
          imageUrl: followedRel.thumbnailUrl,
          primaryColor: 0xFF141414,
          style: 'fullBleed',
        ));
      }

      // 2. Featuring [Artist Name]
      final primaryArtist = featuredArtists.isNotEmpty
          ? featuredArtists.first
          : (recents.isNotEmpty
              ? ArtistItem(
                  id: 'art_${recents.first.artist}',
                  name: recents.first.artist,
                  thumbnailUrl: recents.first.thumbnailUrl,
                  subscribers: 'Monthly audience',
                )
              : null);
      if (primaryArtist != null) {
        orderedHeroCards.add(HeroCardItem(
          id: 'hero_featuring_${primaryArtist.id}',
          title: primaryArtist.name,
          subtitle: 'Featuring ${primaryArtist.name}',
          caption: primaryArtist.subscribers ?? '197K monthly audience',
          imageUrl: primaryArtist.thumbnailUrl,
          primaryColor: 0xFF1A1A24,
          style: 'artistPortrait',
        ));
      }

      // 3. Made for You / Discovery Station (Radial pattern + 3-wave logo)
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_discovery_station',
        title: 'Discovery Station',
        subtitle: 'Made for You',
        caption: 'YouTube Music • Mix',
        primaryColor: 0xFF2A1B6D,
        style: 'discoveryStation',
        playTrack:
            discoveryStation ?? (recents.isNotEmpty ? recents.first : null),
      ));

      // 4. Featuring [Artist] & Similar Artists (3 circular avatars on magenta background)
      final similarAvatars = <String>[];
      for (final a in featuredArtists.take(3)) {
        if (a.thumbnailUrl != null) similarAvatars.add(a.thumbnailUrl!);
      }
      if (similarAvatars.isEmpty) {
        for (final s in recents.take(3)) {
          if (s.thumbnailUrl != null) similarAvatars.add(s.thumbnailUrl!);
        }
      }
      final leadSimilarArtist = featuredArtists.length > 1
          ? featuredArtists[1].name
          : (recents.isNotEmpty ? recents.first.artist : 'Your Favorites');
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_similar_1',
        title: '$leadSimilarArtist & Similar Artists',
        subtitle: 'Featuring $leadSimilarArtist',
        caption: 'YouTube Music • Radio',
        primaryColor: 0xFFD81B60, // vibrant magenta
        style: 'similarArtists',
        artistAvatars: similarAvatars,
        playTrack: recents.isNotEmpty ? recents.first : null,
      ));

      // 5. A Mood for You (Neon green with lightning bolt)
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_mood_energy',
        title: 'Energy',
        subtitle: 'A Mood for You',
        caption: 'For $userName',
        primaryColor: 0xFF00D26A, // neon green
        style: 'moodForYou',
        iconType: 'lightning',
      ));

      // 6. Another Featuring [Artist] & Similar Artists (Orange background)
      final secondSimilarArtist = featuredArtists.length > 2
          ? featuredArtists[2].name
          : (recents.length > 3 ? recents[3].artist : 'Featured');
      final secondAvatars = <String>[];
      for (final a in featuredArtists.skip(2).take(3)) {
        if (a.thumbnailUrl != null) secondAvatars.add(a.thumbnailUrl!);
      }
      if (secondAvatars.isEmpty && recents.length > 3) {
        for (final s in recents.skip(3).take(3)) {
          if (s.thumbnailUrl != null) secondAvatars.add(s.thumbnailUrl!);
        }
      }
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_similar_2',
        title: '$secondSimilarArtist & Similar Artists',
        subtitle: 'Featuring $secondSimilarArtist',
        caption: 'YouTube Music • Radio',
        primaryColor: 0xFFFF6D00, // vibrant deep orange
        style: 'similarArtists',
        artistAvatars: secondAvatars,
        playTrack: recents.length > 3 ? recents[3] : null,
      ));

      // 7. Made for You / New Release Mix
      final releaseMixSubtitle =
          recents.take(4).map((e) => e.artist).toSet().join(', ');
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_new_release_mix',
        title: 'New Release Mix',
        subtitle: 'Made for You',
        caption: (newReleaseMix != null &&
                newReleaseMix.author.isNotEmpty &&
                newReleaseMix.author != 'YouTube Music')
            ? newReleaseMix.author
            : (releaseMixSubtitle.isNotEmpty
                ? releaseMixSubtitle
                : 'New releases you\'ll love'),
        imageUrl: newReleaseMix?.thumbnailUrl ??
            (albumsAndSingles.isNotEmpty
                ? albumsAndSingles.first.thumbnailUrl
                : null),
        primaryColor: 0xFFC2185B,
        style: 'mixWithBadge',
      ));

      // 8. Made for You / [UserName]'s Station (Radiant pink-orange gradient)
      orderedHeroCards.add(HeroCardItem(
        id: 'hero_user_station',
        title: '$userName\'s Station',
        subtitle: 'Made for You',
        caption: 'Your personal station',
        primaryColor: 0xFFFF5722, // coral-pink gradient
        style: 'userStation',
        playTrack: recents.isNotEmpty ? recents.first : null,
      ));

      // Never show "Liked Music" in Top Picks for You
      orderedHeroCards.removeWhere((c) {
        final t = c.title.toLowerCase();
        final s = c.subtitle.toLowerCase();
        final cap = c.caption.toLowerCase();
        return t.contains('liked music') ||
            t.contains('your likes') ||
            s.contains('liked music') ||
            cap.contains('liked music');
      });

      // ═══════════════════════════════════════════════════════════════════
      // STEP 5 — Gate: only return personalized data if we got meaningful content
      // ═══════════════════════════════════════════════════════════════════
      final hasPersonalContent =
          dynamicSections.isNotEmpty ||
          recents.isNotEmpty ||
          quickPicks.isNotEmpty ||
          albumsAndSingles.isNotEmpty;

      if (!hasPersonalContent) return null;

      final defaultCategories = await _fetchMoodsAndGenres();

      return HomeData(
        heroCards: orderedHeroCards,
        recents: recents,
        quickPicks: quickPicks,
        moods: defaultCategories.moods,
        genres: defaultCategories.genres,
        albumsAndSingles: albumsAndSingles,
        musicVideos: musicVideos,
        dailyDiscover: dailyDiscover,
        trendingSongs: trendingSongs,
        dynamicSections: dynamicSections,
        // Personalized fields
        featuredPlaylists: featuredPlaylists,
        mixedForYou: mixedForYou,
        myMixes: myMixes,
        followedArtistNewReleases: followedArtistNewReleases,
        featuredArtists: featuredArtists,
        userStation: userStation,
        newReleaseMix: newReleaseMix,
        discoveryStation: discoveryStation,
      );
    } catch (e) {
      debugPrint('_fetchPersonalizedHomeData: top-level error: $e');
      return null;
    }
  }

  List<SongItem> _extractSongsFromHomeSection(HomeSection section) {
    final list = <SongItem>[];
    for (final item in section.contents) {
      if (item is SongDetailed && item.videoId.isNotEmpty) {
        final title = item.name.trim();
        if (title.isEmpty || title.toLowerCase() == 'untitled') {
          continue;
        }
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          SongItem(
            id: item.videoId,
            title: title,
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            durationSeconds: item.duration,
            album: item.album?.name,
          ),
        );
      }
    }
    return list;
  }

  List<AlbumItem> _extractAlbumsFromHomeSection(HomeSection section) {
    final list = <AlbumItem>[];
    for (final item in section.contents) {
      if (item is AlbumDetailed && item.albumId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          AlbumItem(
            id: item.albumId,
            title: item.name.isNotEmpty ? item.name : 'Untitled Album',
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            type: item.type.isNotEmpty ? item.type : 'Album',
            year: item.year,
          ),
        );
      }
    }
    return list;
  }

  /// Extracts PlaylistItems from a HomeSection whose contents may contain
  /// PlaylistDetailed or AlbumDetailed items (used for Supermix / My Mix shelves).
  List<PlaylistItem> _extractPlaylistsFromHomeSection(HomeSection section) {
    final list = <PlaylistItem>[];
    for (final item in section.contents) {
      if (item is PlaylistDetailed && item.playlistId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(PlaylistItem(
          id: item.playlistId,
          title: item.name.isNotEmpty ? item.name : 'Mix',
          author: item.artist.name.isNotEmpty
              ? item.artist.name
              : 'YouTube Music',
          thumbnailUrl: thumb,
        ));
      } else if (item is AlbumDetailed && item.albumId.isNotEmpty) {
        // Some mixes surface as albums — wrap them as playlists
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(PlaylistItem(
          id: item.albumId,
          title: item.name.isNotEmpty ? item.name : 'Mix',
          author: item.artist.name.isNotEmpty
              ? item.artist.name
              : 'YouTube Music',
          thumbnailUrl: thumb,
        ));
      }
    }
    return list;
  }

  List<VideoItem> _extractVideosFromHomeSection(HomeSection section) {
    final list = <VideoItem>[];
    for (final item in section.contents) {
      if (item is VideoDetailed && item.videoId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          VideoItem(
            id: item.videoId,
            title: item.name.isNotEmpty ? item.name : 'Untitled Video',
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            durationSeconds: item.duration,
          ),
        );
      }
    }
    return list;
  }

  /// Fetches raw home feed sections from YouTube Music API without any hardcoded data.
  Future<HomeData> _fetchRawYouTubeHomeData() async {
    final heroCards = <HeroCardItem>[];
    final recents = <SongItem>[];
    final quickPicks = <SongItem>[];
    final albums = <AlbumItem>[];
    final videos = <VideoItem>[];
    final dailyDiscover = <SongItem>[];
    final trendingSongs = <SongItem>[];

    // 1. Fetch live YouTube Music shelves via InnerTube browse (FEmusic_explore, FEmusic_home)
    try {
      final browseIds = ['FEmusic_explore', 'FEmusic_home'];
      for (final bId in browseIds) {
        final browseJson = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': bId},
        );
        if (browseJson != null) {
          final shelves = _collectRenderers(
            browseJson,
            'musicCarouselShelfRenderer',
          );
          for (final shelf in shelves) {
            final header =
                shelf['header']?['musicCarouselShelfBasicHeaderRenderer'];
            final sectionTitle = _extractNodeText(header?['title']);
            final titleLower = sectionTitle.toLowerCase();
            final items = shelf['contents'] as List? ?? [];
            final songs = <SongItem>[];
            final shelfAlbums = <AlbumItem>[];
            final shelfVideos = <VideoItem>[];

            for (final it in items) {
              if (it is Map) {
                if (it['musicResponsiveListItemRenderer'] is Map) {
                  final s = parseSongFromRenderer(
                    it['musicResponsiveListItemRenderer']
                        as Map<String, dynamic>,
                  );
                  if (s != null) songs.add(s);
                } else if (it['musicTwoRowItemRenderer'] is Map) {
                  final twoRow =
                      it['musicTwoRowItemRenderer'] as Map<String, dynamic>;
                  final title = _extractNodeText(twoRow['title']);
                  final subtitle = _extractNodeText(twoRow['subtitle']);
                  final thumb = _extractNodePhoto(twoRow);
                  final browseId = traverseString(twoRow, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  final videoId = traverseString(twoRow, [
                    'navigationEndpoint',
                    'watchEndpoint',
                    'videoId',
                  ]);

                  if (videoId != null && videoId.isNotEmpty) {
                    var songTitle = title.trim();
                    if (songTitle.isEmpty ||
                        songTitle.toLowerCase() == 'untitled' ||
                        songTitle.toLowerCase() == 'track') {
                      final a11y =
                          traverseString(twoRow, [
                            'title',
                            'runs',
                            'navigationEndpoint',
                            'watchEndpoint',
                            'title',
                          ]) ??
                          traverseString(twoRow, [
                            'accessibilityData',
                            'accessibilityData',
                            'label',
                          ]);
                      if (a11y != null && a11y.trim().isNotEmpty) {
                        songTitle = a11y.trim();
                      }
                    }
                    if (songTitle.isNotEmpty &&
                        songTitle.toLowerCase() != 'untitled' &&
                        songTitle.toLowerCase() != 'track') {
                      final cleanArt = SongItem.sanitizeArtist(subtitle);
                      final cleanTit = SongItem.sanitizeTitle(songTitle, cleanArt);
                      final song = SongItem(
                        id: videoId,
                        title: cleanTit,
                        artist: cleanArt.isNotEmpty ? cleanArt : 'YouTube Music',
                        thumbnailUrl: thumb,
                      );
                      songs.add(song);
                      if (titleLower.contains('video')) {
                        shelfVideos.add(
                          VideoItem(
                            id: videoId,
                            title: songTitle,
                            artist: subtitle.isNotEmpty ? subtitle : 'Artist',
                            thumbnailUrl: thumb,
                          ),
                        );
                      }
                    }
                  } else if (browseId != null && browseId.isNotEmpty) {
                    final alb = _parseTwoRowAlbum(
                          twoRow,
                          type: titleLower.contains('single') ? 'Single' : 'Album',
                        ) ??
                        AlbumItem(
                          id: browseId,
                          title: title.isNotEmpty ? title : 'Album',
                          artist: subtitle.isNotEmpty ? subtitle : 'Artist',
                          thumbnailUrl: thumb,
                          type: titleLower.contains('single') ? 'Single' : 'Album',
                          description: _extractFullSubtitle(twoRow),
                          isCustom: false,
                        );
                    shelfAlbums.add(alb);
                  }
                }
              }
            }

            if (titleLower.contains('trend') ||
                titleLower.contains('chart') ||
                titleLower.contains('hit') ||
                titleLower.contains('popular')) {
              trendingSongs.addAll(songs);
              quickPicks.addAll(songs);
            } else if (titleLower.contains('video')) {
              videos.addAll(shelfVideos);
            } else if (titleLower.contains('album') ||
                titleLower.contains('single') ||
                titleLower.contains('release')) {
              albums.addAll(shelfAlbums);
            } else if (titleLower.contains('nostalgic') ||
                titleLower.contains('playlist') ||
                titleLower.contains('mix') ||
                titleLower.contains('discover') ||
                titleLower.contains('for you') ||
                titleLower.contains('listen again')) {
              dailyDiscover.addAll(songs);
              recents.addAll(songs);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_fetchRawYouTubeHomeData InnerTube error: $e');
    }

    // 2. Supplement from _ytMusic.getHomeSections() if still needing data
    if (trendingSongs.isEmpty || albums.isEmpty || videos.isEmpty) {
      try {
        final sections = await _ytMusic.getHomeSections();
        for (final section in sections) {
          final title = section.title.trim();
          final titleLower = title.toLowerCase();
          final songs = _extractSongsFromHomeSection(section);
          final sectionAlbums = _extractAlbumsFromHomeSection(section);
          final sectionVideos = _extractVideosFromHomeSection(section);

          if (titleLower.contains('quick pick') ||
              titleLower.contains('picks')) {
            quickPicks.addAll(songs);
          } else if (titleLower.contains('listen again') ||
              titleLower.contains('recent')) {
            recents.addAll(songs);
          } else if (titleLower.contains('trend') ||
              titleLower.contains('chart')) {
            trendingSongs.addAll(songs);
          } else if (titleLower.contains('discover') ||
              titleLower.contains('mix')) {
            dailyDiscover.addAll(songs);
          }
          if (sectionAlbums.isNotEmpty) albums.addAll(sectionAlbums);
          if (sectionVideos.isNotEmpty) videos.addAll(sectionVideos);
        }
      } catch (e) {
        debugPrint('_fetchRawYouTubeHomeData getHomeSections error: $e');
      }
    }

    // 3. Assemble dynamic Top Picks Hero Cards (New releases, featuring artists, and mixes)
    for (final album in albums.take(3)) {
      heroCards.add(
        HeroCardItem(
          id: 'hero_album_${album.id}',
          title: album.title,
          subtitle: 'New from ${album.artist}',
          caption: '${album.type} • ${album.year ?? DateTime.now().year}',
          imageUrl: album.thumbnailUrl,
          primaryColor: 0xFF141414,
        ),
      );
    }
    for (final song in trendingSongs.take(2)) {
      heroCards.add(
        HeroCardItem(
          id: 'hero_artist_${song.id}',
          title: '${song.artist} & Similar Artists',
          subtitle: 'Featuring ${song.artist}',
          caption: 'YouTube Music • Radio',
          imageUrl: song.thumbnailUrl,
          primaryColor: 0xFF141414,
          playTrack: song,
        ),
      );
    }
    if (dailyDiscover.isNotEmpty && heroCards.length < 5) {
      final lead = dailyDiscover.first;
      heroCards.add(
        HeroCardItem(
          id: 'hero_station_${lead.id}',
          title: 'Discovery Station',
          subtitle: 'Made for You',
          caption: 'YouTube Music • Mix',
          imageUrl: lead.thumbnailUrl,
          primaryColor: 0xFF141414,
          playTrack: lead,
        ),
      );
    }

    // 2. Fetch real moods and genres from YouTube Music browse API
    final categories = await _fetchMoodsAndGenres();

    // 3. Fallbacks using raw search if specific categories were not in home sections
    if (quickPicks.isEmpty) {
      final results = await searchSongs('Top Hits');
      quickPicks.addAll(results);
    }

    if (recents.isEmpty) {
      if (dailyDiscover.isNotEmpty) {
        recents.addAll(dailyDiscover);
      } else if (quickPicks.isNotEmpty) {
        recents.addAll(quickPicks.skip(quickPicks.length > 4 ? 4 : 0));
      }
    }

    if (trendingSongs.isEmpty) {
      if (quickPicks.isNotEmpty) {
        trendingSongs.addAll(quickPicks);
      }
    }

    if (dailyDiscover.isEmpty) {
      if (trendingSongs.isNotEmpty) {
        dailyDiscover.addAll(trendingSongs);
      } else if (quickPicks.isNotEmpty) {
        dailyDiscover.addAll(quickPicks);
      }
    }

    if (albums.isEmpty) {
      try {
        final tasteArtists = <String>{};
        for (final song in [...recents, ...quickPicks]) {
          if (song.artist.isNotEmpty && !song.artist.toLowerCase().contains('various')) {
            final artist = song.artist.split(RegExp(r'[,&•/]')).first.trim();
            if (artist.isNotEmpty && artist.length > 2) tasteArtists.add(artist);
          }
        }
        for (final artist in tasteArtists.take(3)) {
          try {
            final artistAlbums = await searchAlbums(artist);
            for (final alb in artistAlbums) {
              if (!albums.any((existing) => existing.id == alb.id || existing.title.toLowerCase() == alb.title.toLowerCase())) {
                albums.add(alb);
              }
            }
          } catch (_) {}
        }
        if (albums.isEmpty) {
          final rawAlbums = await searchAlbums('Top Albums');
          albums.addAll(rawAlbums);
        }
      } catch (_) {}
    }

    if (videos.isEmpty) {
      try {
        final rawVideos = await searchVideos('Official Music Videos');
        videos.addAll(rawVideos);
      } catch (_) {}
    }

    // Ensure heroCards has real items from the top songs
    if (heroCards.isEmpty) {
      final pool = [...quickPicks, ...recents, ...trendingSongs];
      for (int i = 0; i < pool.length && heroCards.length < 3; i++) {
        final track = pool[i];
        heroCards.add(
          HeroCardItem(
            id: 'hero_track_${track.id}_$i',
            title: track.title,
            subtitle: track.artist,
            caption: 'YouTube Music • Featured',
            imageUrl: track.thumbnailUrl,
            primaryColor: 0xFF1C1C1E,
            playTrack: track,
          ),
        );
      }
    }

    return HomeData(
      heroCards: heroCards,
      recents: recents,
      quickPicks: quickPicks,
      moods: categories.moods,
      genres: categories.genres,
      albumsAndSingles: albums,
      musicVideos: videos,
      dailyDiscover: dailyDiscover,
      trendingSongs: trendingSongs,
      // No personalized fields in raw (unauthenticated) feed
    );
  }

  Future<List<AlbumItem>> searchAlbums(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchAlbums(trimmedQuery);
      return results.where((a) => a.albumId.isNotEmpty).map((a) {
        String? thumb;
        if (a.thumbnails.isNotEmpty) {
          final raw = a.thumbnails.last.url;
          thumb = SongItem.upgradeThumbnail(
            raw.startsWith('//') ? 'https:$raw' : raw,
          );
        }
        if (thumb != null && thumb.isNotEmpty) {
          _albumArtworkCache[a.albumId] = thumb;
        }
        return AlbumItem(
          id: a.albumId,
          title: a.name.isNotEmpty ? a.name : 'Untitled Album',
          artist: a.artist.name.isNotEmpty ? a.artist.name : 'Unknown Artist',
          thumbnailUrl: thumb,
          type: a.type.isNotEmpty ? a.type : 'Album',
          year: a.year,
        );
      }).toList();
    } catch (e) {
      debugPrint('searchAlbums error: $e');
      return [];
    }
  }

  /// Resolves the real cover artwork URL for a specific album by ID, title, or artist.
  /// If the album has no image or if loading failed, this grabs the real image from YouTube Music.
  Future<String?> getAlbumArtwork(
    String albumId, {
    String? title,
    String? artist,
  }) async {
    final cleanId = albumId.trim();
    if (cleanId.isNotEmpty && _albumArtworkCache.containsKey(cleanId)) {
      return _albumArtworkCache[cleanId];
    }

    if (!_isInitialized) {
      await initialize();
    }

    // 1. Try querying the album directly
    if (cleanId.isNotEmpty) {
      try {
        final albumFull = await _ytMusic.getAlbum(cleanId);
        if (albumFull.thumbnails.isNotEmpty) {
          final raw = albumFull.thumbnails.last.url;
          final url = SongItem.upgradeThumbnail(
            raw.startsWith('//') ? 'https:$raw' : raw,
          );
          if (url != null && url.isNotEmpty) {
            _albumArtworkCache[cleanId] = url;
            return url;
          }
        }
        if (albumFull.songs.isNotEmpty) {
          for (final song in albumFull.songs) {
            if (song.thumbnails.isNotEmpty) {
              final raw = song.thumbnails.last.url;
              final url = SongItem.upgradeThumbnail(
                raw.startsWith('//') ? 'https:$raw' : raw,
              );
              if (url != null && url.isNotEmpty) {
                _albumArtworkCache[cleanId] = url;
                return url;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('getAlbumArtwork getAlbum error for $cleanId: $e');
      }
    }

    // 2. Try searching YouTube Music for this specific album
    final query = '${title ?? ''} ${artist ?? ''}'.trim();
    if (query.isNotEmpty) {
      try {
        final searchResults = await _ytMusic.searchAlbums(query);
        if (searchResults.isNotEmpty) {
          final first = searchResults.first;
          if (first.thumbnails.isNotEmpty) {
            final raw = first.thumbnails.last.url;
            final url = SongItem.upgradeThumbnail(
              raw.startsWith('//') ? 'https:$raw' : raw,
            );
            if (url != null && url.isNotEmpty) {
              if (cleanId.isNotEmpty) _albumArtworkCache[cleanId] = url;
              return url;
            }
          }
        }
      } catch (e) {
        debugPrint('getAlbumArtwork searchAlbums error for $query: $e');
      }

      // 3. Fallback search songs for dedicated album artwork (never YouTube video stills)
      try {
        final songs = await _ytMusic.searchSongs(query);
        for (final s in songs) {
          if (s.thumbnails.isNotEmpty) {
            final raw = s.thumbnails.last.url;
            final url = SongItem.upgradeThumbnail(
              raw.startsWith('//') ? 'https:$raw' : raw,
            );
            if (url != null &&
                url.isNotEmpty &&
                !url.contains('i.ytimg.com') &&
                !url.contains('img.youtube.com')) {
              if (cleanId.isNotEmpty) _albumArtworkCache[cleanId] = url;
              return url;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Resolves animated looping artwork or crisp HD video stream for the song or its album from YouTube.
  /// 1. Searches YouTube for the official music video / moving visualizer to retrieve its HD stream (1080p/720p).
  /// 2. If video is found, extracts its hardware-accelerated video stream and headers.
  /// 3. If HD video unavailable, checks for moving WebP thumbnail.
  /// 4. Falls back to album search or direct track ID video.
  Future<AnimatedArtworkData?> getAnimatedArtworkData(SongItem song) async {
    // If song already has an animated artwork URL specified, return it
    if (song.animatedArtworkUrl != null &&
        song.animatedArtworkUrl!.isNotEmpty) {
      final isVideo = isVideoMediaUrl(song.animatedArtworkUrl);
      return AnimatedArtworkData(
        url: song.animatedArtworkUrl!,
        isVideo: isVideo,
      );
    }

    final cacheKey = song.id.isNotEmpty
        ? song.id
        : '${song.title}_${song.artist}';
    if (_animatedArtworkDataCache.containsKey(cacheKey)) {
      return _animatedArtworkDataCache[cacheKey];
    }

    try {
      // 1. Search YouTube for official music video / moving visualizer first
      final searchResult = await _searchOfficialVideoOrThumbnail(
        '${song.title} ${song.artist}',
      );
      if (searchResult != null) {
        if (searchResult.videoId != null) {
          final officialVideo = await resolveVideoStream(searchResult.videoId!);
          if (officialVideo != null && officialVideo.height >= 480) {
            final data = AnimatedArtworkData(
              url: officialVideo.url,
              headers: officialVideo.headers,
              isVideo: true,
              width: officialVideo.width,
              height: officialVideo.height,
            );
            _animatedArtworkDataCache[cacheKey] = data;
            _animatedArtworkCache[cacheKey] = data.url;
            return data;
          }
        }
        if (searchResult.thumbnailUrl != null) {
          final data = AnimatedArtworkData(
            url: searchResult.thumbnailUrl!,
            isVideo: false,
          );
          _animatedArtworkDataCache[cacheKey] = data;
          _animatedArtworkCache[cacheKey] = data.url;
          return data;
        }
      }

      // 2. Fallback to album search if song belongs to an album
      if (song.album != null &&
          song.album!.isNotEmpty &&
          song.album != song.title) {
        final albumResult = await _searchOfficialVideoOrThumbnail(
          '${song.album} ${song.artist}',
        );
        if (albumResult != null) {
          if (albumResult.videoId != null) {
            final officialVideo = await resolveVideoStream(
              albumResult.videoId!,
            );
            if (officialVideo != null && officialVideo.height >= 480) {
              final data = AnimatedArtworkData(
                url: officialVideo.url,
                headers: officialVideo.headers,
                isVideo: true,
                width: officialVideo.width,
                height: officialVideo.height,
              );
              _animatedArtworkDataCache[cacheKey] = data;
              _animatedArtworkCache[cacheKey] = data.url;
              return data;
            }
          }
          if (albumResult.thumbnailUrl != null) {
            final data = AnimatedArtworkData(
              url: albumResult.thumbnailUrl!,
              isVideo: false,
            );
            _animatedArtworkDataCache[cacheKey] = data;
            _animatedArtworkCache[cacheKey] = data.url;
            return data;
          }
        }
      }

      // 3. Direct video resolution from track ID as final fallback
      if (song.id.isNotEmpty) {
        final directVideo = await resolveVideoStream(song.id);
        if (directVideo != null && directVideo.height >= 480) {
          final data = AnimatedArtworkData(
            url: directVideo.url,
            headers: directVideo.headers,
            isVideo: true,
            width: directVideo.width,
            height: directVideo.height,
          );
          _animatedArtworkDataCache[cacheKey] = data;
          _animatedArtworkCache[cacheKey] = data.url;
          return data;
        }
      }

      _animatedArtworkDataCache[cacheKey] = null;
      _animatedArtworkCache[cacheKey] = null;
      return null;
    } catch (e) {
      debugPrint('getAnimatedArtworkData error for ${song.title}: $e');
      _animatedArtworkDataCache[cacheKey] = null;
      _animatedArtworkCache[cacheKey] = null;
      return null;
    }
  }

  /// Determines whether the given URL represents a playable video stream.
  static bool isVideoMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('googlevideo.com') ||
        lower.contains('/videoplayback') ||
        lower.contains('.m3u8');
  }

  /// Resolves an animated looping artwork or crisp HD video stream for the song or its album from YouTube.
  Future<String?> getAnimatedArtwork(SongItem song) async {
    final data = await getAnimatedArtworkData(song);
    return data?.url;
  }

  /// Internal helper to perform a lightweight search for the official video ID and moving thumbnail.
  Future<({String? videoId, String? thumbnailUrl})?>
  _searchOfficialVideoOrThumbnail(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    HttpClient? client;
    try {
      final uri = Uri.parse(
        'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
      );
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20231018.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': cleanQuery,
      });

      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }

      final responseBody = await utf8.decoder.bind(response).join();
      final data = jsonDecode(responseBody);

      String? matchedVideoId;
      String? matchedThumbnailUrl;

      void walk(dynamic node) {
        if (matchedVideoId != null && matchedThumbnailUrl != null) return;
        if (node is Map) {
          if (node.containsKey('videoRenderer')) {
            final vr = node['videoRenderer'];
            if (vr is Map) {
              matchedVideoId ??= vr['videoId'] as String?;
              final moving =
                  vr['richThumbnail']?['movingThumbnailRenderer'] ??
                  vr['movingThumbnailRenderer'];
              if (moving is Map && matchedThumbnailUrl == null) {
                final thumbs =
                    moving['movingThumbnailDetails']?['thumbnails'] as List?;
                if (thumbs != null && thumbs.isNotEmpty) {
                  final raw = thumbs.first['url'] as String?;
                  if (raw != null && raw.isNotEmpty) {
                    matchedThumbnailUrl = raw.startsWith('//')
                        ? 'https:$raw'
                        : raw;
                  }
                }
              }
              if (matchedVideoId != null && matchedThumbnailUrl != null) return;
            }
          }
          for (final value in node.values) {
            walk(value);
            if (matchedVideoId != null && matchedThumbnailUrl != null) return;
          }
        } else if (node is List) {
          for (final item in node) {
            walk(item);
            if (matchedVideoId != null && matchedThumbnailUrl != null) return;
          }
        }
      }

      walk(data);
      if (matchedVideoId != null || matchedThumbnailUrl != null) {
        return (videoId: matchedVideoId, thumbnailUrl: matchedThumbnailUrl);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Fetches track listings for an album or single.
  /// First queries `_ytMusic.getAlbum(albumId)`. If no tracks are parsed or if it fails,
  /// gracefully falls back to searching songs with [queryFallback].
  Future<List<SongItem>> getAlbumSongs(
    String albumId, {
    String? queryFallback,
  }) async {
    final cleanId = albumId.trim();

    // If requesting Liked Music collection, resolve full liked tracks from user's account
    if (cleanId == 'LM' || cleanId == 'liked_music' || cleanId == 'VLLM') {
      return getLikedSongs();
    }

    if (cleanId.startsWith('PL') || cleanId.startsWith('VL')) {
      try {
        final playlistTracks = await getPlaylistTracks(cleanId);
        if (playlistTracks.isNotEmpty) {
          return playlistTracks;
        }
      } catch (e) {
        debugPrint('getAlbumSongs playlist error for $cleanId: $e');
      }
    }

    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      try {
        final albumFull = await _ytMusic.getAlbum(cleanId);
        if (albumFull.songs.isNotEmpty) {
          final albumThumb = albumFull.thumbnails.isNotEmpty
              ? albumFull.thumbnails.last.url
              : null;
          final albumArtist = albumFull.artist.name.isNotEmpty
              ? albumFull.artist.name
              : 'Unknown Artist';

          var tracks = albumFull.songs.where((s) => s.videoId.isNotEmpty).map((
            s,
          ) {
            final artistName = s.artist.name.isNotEmpty
                ? s.artist.name
                : albumArtist;
            final rawThumb = s.thumbnails.isNotEmpty
                ? s.thumbnails.last.url
                : albumThumb;
            final thumb = SongItem.upgradeThumbnail(rawThumb);
            final cachedDuration = (s.duration != null && s.duration! > 0)
                ? s.duration
                : SongMetricsCacheService.instance
                      .getDuration(s.videoId)
                      ?.inSeconds;
            return SongItem(
              id: s.videoId,
              title: SongItem.sanitizeTitle(s.name.isNotEmpty ? s.name : 'Untitled'),
              artist: SongItem.sanitizeArtist(artistName),
              thumbnailUrl: thumb,
              durationSeconds: cachedDuration,
              album: albumFull.name.isNotEmpty ? albumFull.name : null,
            );
          }).toList();

          tracks = await _hydrateMissingAlbumDurations(cleanId, tracks);
          SongMetricsCacheService.instance.precacheTracks(tracks, this);
          return tracks;
        }
      } catch (e) {
        debugPrint('getAlbum error: $e, falling back to queryFallback');
      }
    }

    if (queryFallback != null && queryFallback.trim().isNotEmpty) {
      return searchSongs(queryFallback);
    }

    return [];
  }

  /// Resolves any missing (`null` or `<= 0`) track durations in an album by
  /// parsing raw InnerTube `browse` renderers (`fixedColumns`, `flexColumns`,
  /// accessibility labels) when `dart_ytmusic_api` skips them.
  Future<List<SongItem>> _hydrateMissingAlbumDurations(
    String browseId,
    List<SongItem> tracks,
  ) async {
    final missingTracks = tracks
        .where((t) => t.durationSeconds == null || t.durationSeconds! <= 0)
        .toList();
    if (missingTracks.isEmpty || browseId.isEmpty) return tracks;

    try {
      final browseData = await postInnerTube(
        'browse',
        bodyExtras: {'browseId': browseId},
      );
      if (browseData == null) return tracks;

      final renderers = _collectRenderers(
        browseData,
        'musicResponsiveListItemRenderer',
      );
      if (renderers.isEmpty) return tracks;

      final durationsById = <String, int>{};
      final durationsByTitle = <String, int>{};
      for (final renderer in renderers) {
        final duration = extractDurationFromRenderer(renderer);
        if (duration == null || duration <= 0) continue;

        final parsed = parseSongFromRenderer(renderer);
        if (parsed != null && parsed.id.isNotEmpty) {
          durationsById[parsed.id] = duration;
        }
        final title = (parsed?.title ??
                _extractNodeText((renderer['flexColumns'] as List?)?.first))
            .trim()
            .toLowerCase();
        if (title.isNotEmpty) {
          durationsByTitle[title] = duration;
        }
      }

      if (durationsById.isEmpty && durationsByTitle.isEmpty) return tracks;

      return tracks.map((track) {
        if (track.durationSeconds != null && track.durationSeconds! > 0) {
          return track;
        }
        final matched =
            durationsById[track.id] ??
            durationsByTitle[track.title.trim().toLowerCase()];
        if (matched != null && matched > 0) {
          return track.copyWith(durationSeconds: matched);
        }
        return track;
      }).toList();
    } catch (e) {
      debugPrint('_hydrateMissingAlbumDurations error for $browseId: $e');
      return tracks;
    }
  }

  /// Fetches complete album details including upgraded artwork, all track listings,
  /// and total calculated duration for the Album Screen.
  Future<AlbumDetails> getAlbumDetails(
    AlbumItem initialAlbum, {
    String? queryFallback,
  }) async {
    final tracks = await getAlbumSongs(
      initialAlbum.id,
      queryFallback:
          queryFallback ?? '${initialAlbum.title} ${initialAlbum.artist}',
    );

    String? artwork = initialAlbum.thumbnailUrl;
    if ((artwork == null || artwork.isEmpty) && tracks.isNotEmpty) {
      artwork = tracks.first.thumbnailUrl;
    }
    if (artwork == null || artwork.isEmpty) {
      artwork = await getAlbumArtwork(
        initialAlbum.id,
        title: initialAlbum.title,
        artist: initialAlbum.artist,
      );
    }

    final totalDuration = tracks.fold<int>(
      0,
      (sum, t) => sum + (t.durationSeconds ?? 0),
    );
    final updatedAlbum = initialAlbum.copyWith(
      thumbnailUrl: artwork,
      trackCount: tracks.length,
      durationMinutes: totalDuration > 0 ? (totalDuration ~/ 60) : null,
    );

    return AlbumDetails(
      album: updatedAlbum,
      tracks: tracks,
      totalDurationSeconds: totalDuration,
    );
  }

  /// Extracts clean playlist ID from URLs (e.g. music.youtube.com/playlist?list=... or youtube.com/playlist?list=...)
  /// or directly returns the raw input if it's already an ID.
  static String extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('list')) {
      return uri.queryParameters['list']!;
    }
    final match = RegExp(r'[?&]list=([^&#]+)').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!;
    }
    return trimmed;
  }

  /// Fetches playlist metadata (title, author, thumbnail, video count) from YouTube Music.
  Future<PlaylistItem?> fetchYouTubePlaylist(String urlOrId) async {
    final cleanId = extractPlaylistId(urlOrId);
    if (cleanId.isEmpty) return null;

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final playlistFull = await _ytMusic.getPlaylist(cleanId);
      final thumb = playlistFull.thumbnails.isNotEmpty
          ? SongItem.upgradeThumbnail(playlistFull.thumbnails.last.url)
          : null;

      final authorName = playlistFull.artist.name.isNotEmpty
          ? playlistFull.artist.name
          : 'YouTube Music';

      return PlaylistItem(
        id: cleanId,
        title: playlistFull.name.isNotEmpty
            ? playlistFull.name
            : 'YouTube Playlist',
        author: authorName,
        thumbnailUrl: thumb,
        trackCount: playlistFull.videoCount > 0
            ? playlistFull.videoCount
            : null,
        isCustom: true,
      );
    } catch (e) {
      debugPrint('fetchYouTubePlaylist error for $cleanId: $e');
      return PlaylistItem(
        id: cleanId,
        title: 'Playlist ($cleanId)',
        author: 'YouTube',
        isCustom: true,
      );
    }
  }

  /// Retrieves track listing for a YouTube playlist.
  Future<List<SongItem>> getPlaylistTracks(
    String playlistId, {
    String? queryFallback,
  }) async {
    final cleanId = extractPlaylistId(playlistId);
    if (cleanId == 'LM' || cleanId == 'liked_music' || cleanId == 'VLLM') {
      return getLikedSongs();
    }

    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      // 1. Try InnerTube browse for personal/shared/special playlists
      if (_currentAccount != null) {
        try {
          final browseId = cleanId.startsWith('VL')
              ? cleanId
              : (cleanId.startsWith('PL') ? 'VL$cleanId' : cleanId);
          final data = await postInnerTube(
            'browse',
            bodyExtras: {'browseId': browseId},
          );
          if (data != null) {
            final renderers = _collectRenderers(
              data,
              'musicResponsiveListItemRenderer',
            );
            final parsed = <SongItem>[];
            for (final r in renderers) {
              final song = parseSongFromRenderer(r);
              if (song != null) parsed.add(song);
            }
            if (parsed.isNotEmpty) return parsed;
          }
        } catch (e) {
          debugPrint(
            'getPlaylistTracks InnerTube browse error for $cleanId: $e',
          );
        }
      }

      // 2. Try _ytMusic.getPlaylistVideos
      try {
        final videos = await _ytMusic.getPlaylistVideos(cleanId);
        if (videos.isNotEmpty) {
          return videos.where((v) => v.videoId.isNotEmpty).map((v) {
            final thumb = v.thumbnails.isNotEmpty
                ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                : null;
            final artistName = v.artist.name.isNotEmpty
                ? v.artist.name
                : 'Unknown Artist';
            return SongItem(
              id: v.videoId,
              title: v.name.isNotEmpty ? v.name : 'Untitled',
              artist: artistName,
              thumbnailUrl: thumb,
              durationSeconds: v.duration,
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('getPlaylistTracks error for $cleanId: $e');
      }
    }

    if (queryFallback != null && queryFallback.trim().isNotEmpty) {
      return searchSongs(queryFallback);
    }

    return [];
  }

  /// Fetches Liked Music ('LM' / 'VLLM') from the logged-in YouTube Music user account.
  /// Follows continuation tokens up to 10 pages (~1,000 tracks) as in BitChord.
  Future<List<SongItem>> getLikedSongs() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_currentAccount != null) {
      final songs = <SongItem>[];
      final seenIds = <String>{};

      void addSongs(dynamic root) {
        if (root == null) return;
        final renderers = _collectRenderers(
          root,
          'musicResponsiveListItemRenderer',
        );
        for (final r in renderers) {
          final s = parseSongFromRenderer(r);
          if (s != null && !seenIds.contains(s.id)) {
            seenIds.add(s.id);
            songs.add(s);
          }
        }
      }

      // 1. Authenticated InnerTube request for VLLM (authoritative browse ID in BitChord)
      try {
        var data = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': 'VLLM'},
        );
        data ??= await postInnerTube(
          'browse',
          bodyExtras: {'browseId': 'FEmusic_liked_videos'},
        );

        if (data != null) {
          addSongs(data);

          // Follow continuation tokens up to 10 pages
          int pages = 0;
          String? token = extractContinuationToken(data);
          while (token != null && token.isNotEmpty && pages < 10) {
            pages++;
            final nextData = await browseContinuation(token);
            if (nextData == null) break;
            final prevCount = songs.length;
            addSongs(nextData);
            if (songs.length == prevCount) break;
            token = extractContinuationToken(nextData);
          }

          if (songs.isNotEmpty) {
            return songs;
          }
        }
      } catch (e) {
        debugPrint('getLikedSongs InnerTube VLLM error: $e');
      }

      // 2. Fallback to _ytMusic.getPlaylistVideos('LM')
      try {
        final videos = await _ytMusic.getPlaylistVideos('LM');
        if (videos.isNotEmpty) {
          return videos.where((v) => v.videoId.isNotEmpty).map((v) {
            final thumb = v.thumbnails.isNotEmpty
                ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                : null;
            final artistName = v.artist.name.isNotEmpty
                ? v.artist.name
                : 'Unknown Artist';
            return SongItem(
              id: v.videoId,
              title: v.name.isNotEmpty ? v.name : 'Untitled',
              artist: artistName,
              thumbnailUrl: thumb,
              durationSeconds: v.duration,
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('getLikedSongs LM error: $e, trying VLLM fallback');
        try {
          final videos = await _ytMusic.getPlaylistVideos('VLLM');
          if (videos.isNotEmpty) {
            return videos.where((v) => v.videoId.isNotEmpty).map((v) {
              final thumb = v.thumbnails.isNotEmpty
                  ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                  : null;
              final artistName = v.artist.name.isNotEmpty
                  ? v.artist.name
                  : 'Unknown Artist';
              return SongItem(
                id: v.videoId,
                title: v.name.isNotEmpty ? v.name : 'Untitled',
                artist: artistName,
                thumbnailUrl: thumb,
                durationSeconds: v.duration,
              );
            }).toList();
          }
        } catch (_) {}
      }
    }

    return [];
  }

  /// Adds a song to the user's Liked Music on YouTube Music via InnerTube.
  Future<bool> likeSong(String videoId) async {
    if (_currentAccount == null) return false;
    try {
      final res = await postInnerTube(
        'like/like',
        bodyExtras: {
          'target': {'videoId': videoId},
        },
      );
      return res != null;
    } catch (e) {
      debugPrint('likeSong error ($videoId): $e');
      return false;
    }
  }

  /// Removes a song from the user's Liked Music on YouTube Music via InnerTube.
  Future<bool> unlikeSong(String videoId) async {
    if (_currentAccount == null) return false;
    try {
      final res = await postInnerTube(
        'like/removelike',
        bodyExtras: {
          'target': {'videoId': videoId},
        },
      );
      return res != null;
    } catch (e) {
      debugPrint('unlikeSong error ($videoId): $e');
      return false;
    }
  }

  /// Dislikes a track on YouTube Music via InnerTube.
  Future<bool> dislikeSong(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return false;
    try {
      if (_currentAccount != null) {
        final res = await postInnerTube(
          'like/dislike',
          bodyExtras: {
            'target': {'videoId': cleanId},
          },
        );
        return res != null;
      }
      return true;
    } catch (e) {
      debugPrint('dislikeSong error ($cleanId): $e');
      return false;
    }
  }

  /// Creates a playlist on YouTube Music via InnerTube.
  Future<String?> createPlaylist(String title, {String? description, String? firstVideoId}) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return null;
    if (_currentAccount == null) return null;
    try {
      final res = await postInnerTube(
        'playlist/create',
        bodyExtras: {
          'title': trimmedTitle,
          if (description != null && description.isNotEmpty) 'description': description,
          if (firstVideoId != null && firstVideoId.isNotEmpty) 'videoIds': [firstVideoId],
        },
      );
      final playlistId = res?['playlistId']?.toString();
      debugPrint('[MusicService] Created playlist "$trimmedTitle" with ID: $playlistId');
      return playlistId;
    } catch (e) {
      debugPrint('[MusicService] createPlaylist error: $e');
      return null;
    }
  }

  /// Adds a song to a YouTube Music playlist via InnerTube.
  Future<bool> addSongToPlaylist(String playlistId, String videoId) async {
    final cleanPlaylistId = playlistId.trim();
    final cleanVideoId = videoId.trim();
    if (cleanPlaylistId.isEmpty || cleanVideoId.isEmpty) return false;
    if (_currentAccount == null) return false;
    try {
      final res = await postInnerTube(
        'browse/edit_playlist',
        bodyExtras: {
          'playlistId': cleanPlaylistId,
          'actions': [
            {
              'action': 'ACTION_ADD_VIDEO',
              'addedVideoId': cleanVideoId,
            }
          ],
        },
      );
      final success = res != null;
      debugPrint('[MusicService] addSongToPlaylist ($cleanVideoId -> $cleanPlaylistId): $success');
      return success;
    } catch (e) {
      debugPrint('[MusicService] addSongToPlaylist error: $e');
      return false;
    }
  }

  /// Fetches YouTube Music Radio / Up Next tracks for a song ("Similar music, selected to play next").
  /// Directly powers YouTube Music AutoPlay and Radio mode.
  Future<List<SongItem>> getSongRadio(
    String videoId, {
    String? artist,
    String? title,
  }) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return [];

    // 1. Primary: dart_ytmusic_api getUpNexts(videoId)
    try {
      if (RegExp(r'^[a-zA-Z0-9-_]{11}$').hasMatch(cleanId)) {
        if (!_isInitialized) await initialize();
        final upNexts = await _ytMusic.getUpNexts(cleanId);
        if (upNexts.isNotEmpty) {
          final results = upNexts
              .where((item) => item.videoId.isNotEmpty && item.videoId != cleanId)
              .map((item) {
                final thumb = item.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(item.thumbnails.last.url)
                    : null;
                return SongItem(
                  id: item.videoId,
                  title: item.title.isNotEmpty ? item.title : 'Unknown Title',
                  artist: SongItem.sanitizeArtist(item.artists.name),
                  album: item.album?.name,
                  durationSeconds: item.duration > 0 ? item.duration : null,
                  thumbnailUrl: thumb,
                );
              })
              .toList();
          if (results.isNotEmpty) return results;
        }
      }
    } catch (e) {
      debugPrint('[MusicService] getSongRadio _ytMusic.getUpNexts error: $e');
    }

    // 2. Secondary: InnerTube "next" request with radio playlist "RDAMVM$cleanId"
    try {
      final data = await _ytMusic.constructRequest('next', body: {
        'videoId': cleanId,
        'playlistId': 'RDAMVM$cleanId',
        'isAudioOnly': true,
      });

      final tabs = data?['contents']?['singleColumnMusicWatchNextResultsRenderer']
                  ?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']
              ?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']
          ?['playlistPanelRenderer']?['contents'];

      if (tabs is List && tabs.isNotEmpty) {
        final List<SongItem> songs = [];
        for (final item in tabs.skip(1)) {
          final renderer = item['playlistPanelVideoRenderer'];
          if (renderer == null) continue;
          final vidId = renderer['videoId']?.toString() ?? '';
          if (vidId.isEmpty || vidId == cleanId) continue;
          final songTitle = renderer['title']?['runs']?[0]?['text']?.toString() ?? '';
          final longBylineRuns = renderer['longBylineText']?['runs'];
          final artistName = longBylineRuns?[0]?['text']?.toString() ?? '';
          final albumName = (longBylineRuns is List && longBylineRuns.length > 2)
              ? longBylineRuns[2]['text']?.toString()
              : null;
          final thumbs = renderer['thumbnail']?['thumbnails'];
          final thumbUrl = (thumbs is List && thumbs.isNotEmpty)
              ? SongItem.upgradeThumbnail(thumbs.last['url']?.toString())
              : null;
          final durationSec = parseDurationString(
            renderer['lengthText']?['runs']?[0]?['text']?.toString(),
          );

          songs.add(
            SongItem(
              id: vidId,
              title: songTitle.isNotEmpty ? songTitle : 'Unknown Title',
              artist: SongItem.sanitizeArtist(artistName),
              album: albumName,
              thumbnailUrl: thumbUrl,
              durationSeconds: durationSec,
            ),
          );
        }
        if (songs.isNotEmpty) return songs;
      }
    } catch (e) {
      debugPrint('[MusicService] getSongRadio InnerTube next error: $e');
    }

    // 3. Fallback: Search similar tracks by artist and title
    try {
      final query = '${artist ?? ''} ${title ?? ''}'.trim();
      if (query.isNotEmpty) {
        final searchResults = await searchSongs(query);
        final filtered = searchResults.where((s) => s.id != cleanId).toList();
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return [];
  }

  /// Searches artists on YouTube Music.
  Future<List<ArtistItem>> searchArtists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchArtists(trimmed);
      return results.where((a) => a.artistId.isNotEmpty).map((a) {
        final thumb = a.thumbnails.isNotEmpty
            ? SongItem.upgradeThumbnail(a.thumbnails.last.url)
            : null;
        return ArtistItem(
          id: a.artistId,
          name: a.name.isNotEmpty ? a.name : 'Unknown Artist',
          thumbnailUrl: thumb,
          subscribers: 'Artist',
        );
      }).toList();
    } catch (e) {
      debugPrint('searchArtists error: $e');
      return [];
    }
  }

  /// Fetches top songs for an artist on YouTube Music.
  Future<List<SongItem>> getArtistSongs(
    String artistId, {
    String? artistName,
  }) async {
    final cleanId = artistId.trim();
    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      try {
        final songs = await _ytMusic.getArtistSongs(cleanId);
        if (songs.isNotEmpty) {
          return songs.where((s) => s.videoId.isNotEmpty).map((s) {
            final thumb = s.thumbnails.isNotEmpty
                ? SongItem.upgradeThumbnail(s.thumbnails.last.url)
                : null;
            final name = s.artist.name.isNotEmpty
                ? s.artist.name
                : (artistName ?? 'Artist');
            return SongItem(
              id: s.videoId,
              title: s.name.isNotEmpty ? s.name : 'Untitled',
              artist: name,
              thumbnailUrl: thumb,
              durationSeconds: s.duration,
              album: s.album?.name,
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('getArtistSongs error for $cleanId: $e');
      }
    }

    if (artistName != null && artistName.isNotEmpty) {
      return searchSongs(artistName);
    }

    return [];
  }

  /// Fetches comprehensive artist details from YouTube Music including bio,
  /// subscriber stats, monthly audience, top songs, albums, singles & EPs,
  /// music videos, featured playlists, artist playlists, and fans might also like.
  Future<ArtistDetails> getArtistDetails(
    String artistIdOrName, {
    String? fallbackName,
  }) async {
    final rawQuery = artistIdOrName.trim();
    if (!_isInitialized) {
      await initialize();
    }

    // Check memory cache
    final cached = _artistDetailsCache[rawQuery.toLowerCase()];
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age < const Duration(minutes: 15)) {
        return cached.details;
      }
      _artistDetailsCache.remove(rawQuery.toLowerCase());
    }

    String targetId = rawQuery;
    String resolvedName = fallbackName ?? rawQuery;

    // If ID is not a standard channel browseId (UC...), search for the artist channel ID
    if (!targetId.startsWith('UC')) {
      final searchQuery = fallbackName != null && fallbackName.isNotEmpty
          ? fallbackName
          : rawQuery;
      final searchResults = await searchArtists(searchQuery);
      if (searchResults.isNotEmpty) {
        targetId = searchResults.first.id;
        resolvedName = searchResults.first.name;
      }
    }

    String? bannerUrl;
    String? thumbnailUrl;
    String? subscribers;
    String? monthlyListeners;
    String? description;
    List<SongItem> topSongs = [];
    List<AlbumItem> albums = [];
    List<AlbumItem> singles = [];
    List<VideoItem> videos = [];
    List<PlaylistItem> featuredOn = [];
    List<PlaylistItem> playlistsByArtist = [];
    List<ArtistItem> similarArtists = [];
    AlbumItem? recentRelease;
    String? moreTracksBrowseId;

    // 1. Direct InnerTube browse request to extract full rich layout matching YouTube Music
    if (targetId.startsWith('UC')) {
      try {
        final data = await _ytMusic.constructRequest(
          'browse',
          body: {'browseId': targetId},
        );
        final header =
            data['header']?['musicImmersiveHeaderRenderer'] ??
            data['header']?['musicVisualHeaderRenderer'] ??
            data['header']?['musicHeaderRenderer'];

        if (header != null) {
          final titleText = traverseString(header, ['title', 'runs', 'text']);
          if (titleText != null && titleText.isNotEmpty) {
            resolvedName = titleText;
          }

          // Subscribers
          final subButton =
              header['subscriptionButton']?['subscribeButtonRenderer'];
          subscribers =
              traverseString(subButton, [
                'longSubscriberCountText',
                'runs',
                'text',
              ]) ??
              traverseString(subButton, [
                'subscriberCountText',
                'runs',
                'text',
              ]) ??
              traverseString(subButton, [
                'shortSubscriberCountText',
                'runs',
                'text',
              ]);

          // Monthly Audience / Listeners
          monthlyListeners = traverseString(header, [
            'monthlyListenerCount',
            'runs',
            'text',
          ]);

          // Bio description
          final descRuns = header['description']?['runs'] as List?;
          if (descRuns != null && descRuns.isNotEmpty) {
            description = descRuns.map((r) => r['text'] ?? '').join('').trim();
          }

          // Banner Image
          final thumbs = traverseList(header, [
            'thumbnail',
            'musicThumbnailRenderer',
            'thumbnail',
            'thumbnails',
          ]);
          if (thumbs.isNotEmpty) {
            final lastUrl = thumbs.last?['url'] as String?;
            if (lastUrl != null && lastUrl.isNotEmpty) {
              bannerUrl = SongItem.upgradeThumbnail(lastUrl);
              thumbnailUrl = bannerUrl;
            }
          }
        }

        // Parse contents sections
        final contents =
            data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents != null) {
          for (final section in contents) {
            // Top songs shelf
            final shelf = section['musicShelfRenderer'];
            if (shelf != null) {
              moreTracksBrowseId ??=
                  traverseString(shelf, [
                    'bottomEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]) ??
                  traverseString(shelf, [
                    'title',
                    'runs',
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
              final shelfTitle =
                  (traverseString(shelf, ['title', 'runs', 'text']) ?? '')
                      .toLowerCase();
              if (shelfTitle.contains('song') || topSongs.isEmpty) {
                final items = shelf['contents'] as List? ?? [];
                for (final it in items) {
                  final item = it['musicResponsiveListItemRenderer'];
                  if (item == null) continue;
                  final vId =
                      item['playlistItemData']?['videoId'] ??
                      traverseString(item, [
                        'navigationEndpoint',
                        'watchEndpoint',
                        'videoId',
                      ]);
                  if (vId == null || (vId as String).isEmpty) continue;

                  final flexCols = item['flexColumns'] as List? ?? [];
                  String title = 'Untitled';
                  String artist = resolvedName;
                  String? album;

                  if (flexCols.isNotEmpty) {
                    final t = _extractNodeText(flexCols[0]).trim();
                    if (t.isNotEmpty && t.toLowerCase() != 'untitled') {
                      title = t;
                    } else {
                      title =
                          traverseString(flexCols[0], [
                            'musicResponsiveListItemFlexColumnRenderer',
                            'text',
                            'runs',
                            'text',
                          ]) ??
                          '';
                    }
                  }
                  if (title.isEmpty || title.toLowerCase() == 'untitled') {
                    continue; // Skip tracks without real title
                  }
                  if (flexCols.length > 1) {
                    final a = _extractNodeText(flexCols[1]).trim();
                    if (a.isNotEmpty) {
                      artist = a.split('•')[0].split('·')[0].trim();
                    } else {
                      artist =
                          traverseString(flexCols[1], [
                            'musicResponsiveListItemFlexColumnRenderer',
                            'text',
                            'runs',
                            'text',
                          ]) ??
                          resolvedName;
                    }
                  }
                  if (flexCols.length > 2) {
                    album = traverseString(flexCols[2], [
                      'musicResponsiveListItemFlexColumnRenderer',
                      'text',
                      'runs',
                      'text',
                    ]);
                  }

                  String? thumb;
                  final itemThumbs = traverseList(item, [
                    'thumbnail',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  topSongs.add(
                    SongItem(
                      id: vId,
                      title: title,
                      artist: artist,
                      thumbnailUrl: thumb,
                      album: album,
                    ),
                  );
                }
              }
            }

            // Carousels: Albums, Singles, Videos, Featured, Playlists, Similar Artists
            final carousel = section['musicCarouselShelfRenderer'];
            if (carousel != null) {
              final carouselTitle =
                  (traverseString(carousel, [
                            'header',
                            'musicCarouselShelfBasicHeaderRenderer',
                            'title',
                            'runs',
                            'text',
                          ]) ??
                          '')
                      .toLowerCase();
              final items = carousel['contents'] as List? ?? [];

              if (carouselTitle.contains('album')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Album';
                  final subtitle =
                      traverseString(renderer, ['subtitle', 'runs', 'text']) ??
                      '';
                  final yearMatch = RegExp(r'\b(19|20)\d{2}\b')
                      .firstMatch(subtitle);
                  final year = yearMatch != null
                      ? int.tryParse(yearMatch.group(0)!)
                      : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  albums.add(
                    AlbumItem(
                      id: browseId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      year: year,
                      type: 'Album',
                    ),
                  );
                }
              } else if (carouselTitle.contains('single') ||
                  carouselTitle.contains('ep')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Single';
                  final subtitle =
                      traverseString(renderer, ['subtitle', 'runs', 'text']) ??
                      '';
                  final yearMatch = RegExp(r'\b(19|20)\d{2}\b')
                      .firstMatch(subtitle);
                  final year = yearMatch != null
                      ? int.tryParse(yearMatch.group(0)!)
                      : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  singles.add(
                    AlbumItem(
                      id: browseId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      year: year,
                      type: 'Single',
                    ),
                  );
                }
              } else if (carouselTitle.contains('video')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final videoId = traverseString(renderer, [
                    'navigationEndpoint',
                    'watchEndpoint',
                    'videoId',
                  ]);
                  if (videoId == null || videoId.isEmpty) continue;
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Video';
                  final subtitle =
                      traverseString(renderer, ['subtitle', 'runs', 'text']) ??
                      '';
                  final views = subtitle.contains('views') ? subtitle : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  videos.add(
                    VideoItem(
                      id: videoId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      views: views,
                    ),
                  );
                }
              } else if (carouselTitle.contains('featured')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Playlist';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  featuredOn.add(
                    PlaylistItem(
                      id: browseId,
                      title: title,
                      author: 'YouTube Music',
                      thumbnailUrl: thumb,
                    ),
                  );
                }
              } else if (carouselTitle.contains('playlist')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Playlist';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  playlistsByArtist.add(
                    PlaylistItem(
                      id: browseId,
                      title: title,
                      author: resolvedName,
                      thumbnailUrl: thumb,
                    ),
                  );
                }
              } else if (carouselTitle.contains('fan') ||
                  carouselTitle.contains('similar')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final artistBrowseId = traverseString(renderer, [
                    'navigationEndpoint',
                    'browseEndpoint',
                    'browseId',
                  ]);
                  if (artistBrowseId == null || artistBrowseId.isEmpty) {
                    continue;
                  }
                  final title =
                      traverseString(renderer, ['title', 'runs', 'text']) ??
                      'Artist';
                  final subtitle =
                      traverseString(renderer, ['subtitle', 'runs', 'text']) ??
                      '';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, [
                    'thumbnailRenderer',
                    'musicThumbnailRenderer',
                    'thumbnail',
                    'thumbnails',
                  ]);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(
                      itemThumbs.last?['url'] as String? ?? '',
                    );
                  }

                  similarArtists.add(
                    ArtistItem(
                      id: artistBrowseId,
                      name: title,
                      thumbnailUrl: thumb,
                      subscribers: subtitle.isNotEmpty ? subtitle : null,
                    ),
                  );
                }
              }
            }

            // Description shelf (About the artist)
            final descShelf = section['musicDescriptionShelfRenderer'];
            if (descShelf != null) {
              if (description == null || description.isEmpty) {
                final descRuns = descShelf['description']?['runs'] as List?;
                if (descRuns != null && descRuns.isNotEmpty) {
                  description = descRuns
                      .map((r) => r['text'] ?? '')
                      .join('')
                      .trim();
                }
              }
              subscribers ??= traverseString(descShelf, [
                'subheader',
                'runs',
                'text',
              ]);
            }
          }
        }
      } catch (e) {
        debugPrint('getArtistDetails raw parse error: $e');
      }
    }

    // 2. High-reliability fallback via _ytMusic.getArtist() if essential lists are empty
    if ((topSongs.isEmpty || albums.isEmpty || singles.isEmpty) &&
        targetId.startsWith('UC')) {
      try {
        final artistFull = await _ytMusic.getArtist(targetId);
        if (topSongs.isEmpty && artistFull.topSongs.isNotEmpty) {
          topSongs = artistFull.topSongs
              .map(
                (s) => SongItem(
                  id: s.videoId,
                  title: s.name,
                  artist: s.artist.name.isNotEmpty
                      ? s.artist.name
                      : resolvedName,
                  thumbnailUrl: s.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(s.thumbnails.last.url)
                      : null,
                  album: s.album?.name,
                  durationSeconds: s.duration,
                ),
              )
              .toList();
        }
        if (albums.isEmpty && artistFull.topAlbums.isNotEmpty) {
          albums = artistFull.topAlbums
              .map(
                (a) => AlbumItem(
                  id: a.albumId,
                  title: a.name,
                  artist: a.artist.name.isNotEmpty
                      ? a.artist.name
                      : resolvedName,
                  thumbnailUrl: a.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(a.thumbnails.last.url)
                      : null,
                  year: a.year,
                  type: 'Album',
                ),
              )
              .toList();
        }
        if (singles.isEmpty && artistFull.topSingles.isNotEmpty) {
          singles = artistFull.topSingles
              .map(
                (a) => AlbumItem(
                  id: a.albumId,
                  title: a.name,
                  artist: a.artist.name.isNotEmpty
                      ? a.artist.name
                      : resolvedName,
                  thumbnailUrl: a.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(a.thumbnails.last.url)
                      : null,
                  year: a.year,
                  type: 'Single',
                ),
              )
              .toList();
        }
        if (videos.isEmpty && artistFull.topVideos.isNotEmpty) {
          videos = artistFull.topVideos
              .map(
                (v) => VideoItem(
                  id: v.videoId,
                  title: v.name,
                  artist: v.artist.name,
                  thumbnailUrl: v.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                      : null,
                  durationSeconds: v.duration,
                ),
              )
              .toList();
        }
        if (featuredOn.isEmpty && artistFull.featuredOn.isNotEmpty) {
          featuredOn = artistFull.featuredOn
              .map(
                (p) => PlaylistItem(
                  id: p.playlistId,
                  title: p.name,
                  author: p.artist.name.isNotEmpty
                      ? p.artist.name
                      : 'YouTube Music',
                  thumbnailUrl: p.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(p.thumbnails.last.url)
                      : null,
                ),
              )
              .toList();
        }
        if (similarArtists.isEmpty && artistFull.similarArtists.isNotEmpty) {
          similarArtists = artistFull.similarArtists
              .map(
                (a) => ArtistItem(
                  id: a.artistId,
                  name: a.name,
                  thumbnailUrl: a.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(a.thumbnails.last.url)
                      : null,
                ),
              )
              .toList();
        }
        if (bannerUrl == null && artistFull.thumbnails.isNotEmpty) {
          bannerUrl = SongItem.upgradeThumbnail(artistFull.thumbnails.last.url);
          thumbnailUrl = bannerUrl;
        }
      } catch (e) {
        debugPrint('getArtistDetails fallback error: $e');
      }
    }

    // Ensure at least 12 tracks in advance for top songs
    if (topSongs.length < 12) {
      // 1. Try moreTracksBrowseId if available
      if (moreTracksBrowseId != null && moreTracksBrowseId.isNotEmpty) {
        try {
          final moreData = await _ytMusic.constructRequest(
            'browse',
            body: {'browseId': moreTracksBrowseId},
          );
          final tabs =
              moreData['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
                  as List?;
          List? sections;
          if (tabs != null && tabs.isNotEmpty) {
            final firstTab = tabs.first;
            if (firstTab is Map) {
              sections =
                  firstTab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                      as List?;
            }
          }
          sections ??=
              moreData['contents']?['sectionListRenderer']?['contents']
                  as List?;
          final firstSection =
              (sections != null && sections.isNotEmpty && sections.first is Map)
              ? sections.first as Map
              : null;
          final playlistShelf =
              firstSection?['musicPlaylistShelfRenderer'] ??
              firstSection?['musicShelfRenderer'];
          final moreContents = playlistShelf?['contents'] as List? ?? [];

          for (final it in moreContents) {
            final item = it['musicResponsiveListItemRenderer'];
            if (item == null) continue;
            final vId =
                item['playlistItemData']?['videoId'] ??
                traverseString(item, [
                  'navigationEndpoint',
                  'watchEndpoint',
                  'videoId',
                ]);
            if (vId == null || (vId as String).isEmpty) continue;

            final flexCols = item['flexColumns'] as List? ?? [];
            String title = 'Untitled';
            String artist = resolvedName;
            String? album;

            if (flexCols.isNotEmpty) {
              final t = _extractNodeText(flexCols[0]).trim();
              if (t.isNotEmpty && t.toLowerCase() != 'untitled') {
                title = t;
              } else {
                title =
                    traverseString(flexCols[0], [
                      'musicResponsiveListItemFlexColumnRenderer',
                      'text',
                      'runs',
                      'text',
                    ]) ??
                    '';
              }
            }
            if (title.isEmpty || title.toLowerCase() == 'untitled') {
              continue; // Skip tracks without real title
            }
            if (flexCols.length > 1) {
              final a = _extractNodeText(flexCols[1]).trim();
              if (a.isNotEmpty) {
                artist = a.split('•')[0].split('·')[0].trim();
              } else {
                artist =
                    traverseString(flexCols[1], [
                      'musicResponsiveListItemFlexColumnRenderer',
                      'text',
                      'runs',
                      'text',
                    ]) ??
                    resolvedName;
              }
            }
            if (flexCols.length > 2) {
              album = traverseString(flexCols[2], [
                'musicResponsiveListItemFlexColumnRenderer',
                'text',
                'runs',
                'text',
              ]);
            }

            String? thumb;
            final itemThumbs = traverseList(item, [
              'thumbnail',
              'musicThumbnailRenderer',
              'thumbnail',
              'thumbnails',
            ]);
            if (itemThumbs.isNotEmpty) {
              thumb = SongItem.upgradeThumbnail(
                itemThumbs.last?['url'] as String? ?? '',
              );
            }

            final isDuplicate = topSongs.any(
              (s) =>
                  s.id == vId ||
                  s.title.trim().toLowerCase() == title.trim().toLowerCase(),
            );
            if (!isDuplicate) {
              topSongs.add(
                SongItem(
                  id: vId,
                  title: title,
                  artist: artist,
                  thumbnailUrl: thumb,
                  album: album,
                ),
              );
              if (topSongs.length >= 12) break;
            }
          }
        } catch (e) {
          debugPrint('Error fetching more browse tracks: $e');
        }
      }

      // 2. Query searchSongs as reliable fallback to reach at least 12 tracks
      if (topSongs.length < 12) {
        try {
          final query = resolvedName.isNotEmpty
              ? resolvedName
              : (fallbackName ?? '');
          if (query.isNotEmpty) {
            final additionalTracks = await searchSongs(query);
            for (final track in additionalTracks) {
              final isDuplicate = topSongs.any(
                (s) =>
                    s.id == track.id ||
                    s.title.trim().toLowerCase() ==
                        track.title.trim().toLowerCase(),
              );
              if (!isDuplicate) {
                topSongs.add(track);
                if (topSongs.length >= 12) break;
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching advance top songs: $e');
        }
      }
    }

    // Determine recent release spotlight
    if (singles.isNotEmpty) {
      recentRelease = singles.first;
    } else if (albums.isNotEmpty) {
      recentRelease = albums.first;
    }

    final details = ArtistDetails(
      id: targetId,
      name: resolvedName,
      bannerUrl: bannerUrl,
      thumbnailUrl: thumbnailUrl ?? bannerUrl,
      subscribers: subscribers,
      monthlyListeners: monthlyListeners,
      description: description,
      topSongs: topSongs,
      albums: albums,
      singles: singles,
      videos: videos,
      featuredOn: featuredOn,
      playlistsByArtist: playlistsByArtist,
      similarArtists: similarArtists,
      recentRelease: recentRelease,
    );

    // Cache details
    _artistDetailsCache[rawQuery.toLowerCase()] = (
      details: details,
      timestamp: DateTime.now(),
    );
    if (targetId.isNotEmpty) {
      _artistDetailsCache[targetId.toLowerCase()] = (
        details: details,
        timestamp: DateTime.now(),
      );
    }

    return details;
  }

  /// Fetches user's personalized mixes and playlists if logged into YouTube Music.
  Future<List<PlaylistItem>> getPersonalizedMixes() async {
    if (!_isInitialized) {
      await initialize();
    }

    final mixes = <PlaylistItem>[];
    if (_currentAccount != null) {
      try {
        final sections = await _ytMusic.getHomeSections();
        for (final section in sections) {
          final titleLower = section.title.toLowerCase();
          if (titleLower.contains('mixed for you') ||
              titleLower.contains('mix') ||
              titleLower.contains('playlist') ||
              titleLower.contains('radio')) {
            for (final item in section.contents) {
              if (item is PlaylistDetailed && item.playlistId.isNotEmpty) {
                final thumb = item.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(item.thumbnails.last.url)
                    : null;
                mixes.add(
                  PlaylistItem(
                    id: item.playlistId,
                    title: item.name.isNotEmpty ? item.name : 'Mix',
                    author: item.artist.name.isNotEmpty
                        ? item.artist.name
                        : 'YouTube Music',
                    thumbnailUrl: thumb,
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('getPersonalizedMixes error: $e');
      }
    }
    return mixes;
  }

  /// Fetches the user's specific playlists (created and liked) from their YouTube Music account.
  Future<List<PlaylistItem>> getUserPlaylists() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final playlists = <PlaylistItem>[];
    final seenIds = <String>{};

    void extractPlaylistsFromData(dynamic data) {
      if (data == null) return;
      // Grid items (Two Row)
      final twoRowItems = _collectRenderers(data, 'musicTwoRowItemRenderer');
      for (final item in twoRowItems) {
        final title = _extractNodeText(item['title']).trim();
        if (title.toLowerCase() == 'new playlist') continue;

        final browseId =
            traverseString(item, [
              'navigationEndpoint',
              'browseEndpoint',
              'browseId',
            ]) ??
            traverseString(item, [
              'navigationEndpoint',
              'watchPlaylistEndpoint',
              'playlistId',
            ]);
        if (browseId != null &&
            browseId.isNotEmpty &&
            !browseId.startsWith('UC') &&
            !seenIds.contains(browseId)) {
          seenIds.add(browseId);
          var author = _extractNodeText(item['subtitle']);
          String? thumb = _extractNodePhoto(item);
          if (browseId == 'VLLM' ||
              browseId == 'LM' ||
              title.toLowerCase() == 'liked music') {
            thumb ??= 'https://www.gstatic.com/youtube/media/ytm/images/pbg/liked-songs-delhi-576.png';
            author = '';
          }
          playlists.add(
            PlaylistItem(
              id: browseId,
              title: title.isNotEmpty ? title : 'Playlist',
              author: author.isNotEmpty && author.toLowerCase() != 'youtube music' ? author : '',
              thumbnailUrl: thumb,
              isCustom: false,
            ),
          );
        }
      }

      // Responsive list items
      final listItems = _collectRenderers(
        data,
        'musicResponsiveListItemRenderer',
      );
      for (final item in listItems) {
        final flexCols = item['flexColumns'] as List? ?? [];
        String title = 'Playlist';
        String author = 'YouTube Music';
        if (flexCols.isNotEmpty) {
          final t = _extractNodeText(flexCols[0]).trim();
          if (t.isNotEmpty) title = t;
        }
        if (title.toLowerCase() == 'new playlist') continue;

        final browseId =
            traverseString(item, [
              'navigationEndpoint',
              'browseEndpoint',
              'browseId',
            ]) ??
            traverseString(item, [
              'navigationEndpoint',
              'watchPlaylistEndpoint',
              'playlistId',
            ]);
        if (browseId != null &&
            browseId.isNotEmpty &&
            !browseId.startsWith('UC') &&
            !seenIds.contains(browseId)) {
          seenIds.add(browseId);
          if (flexCols.length > 1) {
            final a = _extractNodeText(flexCols[1]).trim();
            if (a.isNotEmpty) author = a;
          }
          String? thumb = _extractNodePhoto(item);
          if (browseId == 'VLLM' ||
              browseId == 'LM' ||
              title.toLowerCase() == 'liked music') {
            thumb ??= 'https://www.gstatic.com/youtube/media/ytm/images/pbg/liked-songs-delhi-576.png';
            author = '';
          }
          playlists.add(
            PlaylistItem(
              id: browseId,
              title: title,
              author: author.isNotEmpty && author.toLowerCase() != 'youtube music' ? author : '',
              thumbnailUrl: thumb,
              isCustom: false,
            ),
          );
        }
      }
    }

    // 1. Authenticated InnerTube liked & saved playlists
    try {
      final likedData = await postInnerTube(
        'browse',
        bodyExtras: {'browseId': 'FEmusic_liked_playlists'},
      );
      extractPlaylistsFromData(likedData);

      String? token = extractContinuationToken(likedData);
      int p = 0;
      while (token != null && token.isNotEmpty && p < 5) {
        p++;
        final next = await browseContinuation(token);
        if (next == null) break;
        extractPlaylistsFromData(next);
        token = extractContinuationToken(next);
      }
    } catch (e) {
      debugPrint('getUserPlaylists liked playlists error: $e');
    }

    // 2. Authenticated InnerTube library landing items (shared/saved playlists)
    try {
      final landingData = await postInnerTube(
        'browse',
        bodyExtras: {'browseId': 'FEmusic_library_landing'},
      );
      extractPlaylistsFromData(landingData);
    } catch (e) {
      debugPrint('getUserPlaylists landing error: $e');
    }

    return playlists;
  }

  /// Fetches the user's specific saved albums from their YouTube Music account.
  Future<List<AlbumItem>> getUserAlbums() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final albums = <AlbumItem>[];
    final seenIds = <String>{};

    // Authenticated InnerTube library saved & liked albums
    try {
      final feedIds = ['FEmusic_liked_albums', 'FEmusic_library_corpus_albums'];
      for (final feedId in feedIds) {
        final data = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': feedId},
        );
        if (data != null) {
          final items = _collectRenderers(data, 'musicTwoRowItemRenderer');
          for (final item in items) {
            final browseId = traverseString(item, [
              'navigationEndpoint',
              'browseEndpoint',
              'browseId',
            ]);
            if (browseId != null &&
                browseId.isNotEmpty &&
                !seenIds.contains(browseId)) {
              seenIds.add(browseId);
              final title = _extractNodeText(item['title']);
              final artist = _extractNodeText(item['subtitle']);
              final thumb = _extractNodePhoto(item);
              albums.add(
                AlbumItem(
                  id: browseId,
                  title: title.isNotEmpty ? title : 'Album',
                  artist: artist.isNotEmpty ? artist : 'Unknown Artist',
                  thumbnailUrl: thumb,
                  type: 'Album',
                  isCustom: false,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getUserAlbums InnerTube error: $e');
    }

    return albums;
  }

  /// Fetches the user's specific subscribed artists from their YouTube Music account.
  Future<List<ArtistItem>> getUserArtists() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final artists = <ArtistItem>[];
    final seenIds = <String>{};

    // Authenticated InnerTube library subscribed artists
    try {
      final feedIds = [
        'FEmusic_library_corpus_track_artists',
        'FEmusic_library_corpus_artists',
        'FEmusic_library_landing',
      ];
      for (final feedId in feedIds) {
        final data = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': feedId},
        );
        if (data != null) {
          final items = _collectRenderers(data, 'musicTwoRowItemRenderer');
          for (final item in items) {
            final browseId = traverseString(item, [
              'navigationEndpoint',
              'browseEndpoint',
              'browseId',
            ]);
            if (browseId != null &&
                browseId.isNotEmpty &&
                !seenIds.contains(browseId)) {
              final subscribers = _extractNodeText(item['subtitle']);
              final subLower = subscribers.toLowerCase();
              final isArtist =
                  browseId.startsWith('UC') ||
                  subLower.contains('artist') ||
                  subLower.contains('subscriber');
              if (isArtist) {
                seenIds.add(browseId);
                final name = _extractNodeText(item['title']);
                final thumb = _extractNodePhoto(item);
                artists.add(
                  ArtistItem(
                    id: browseId,
                    name: name.isNotEmpty ? name : 'Artist',
                    thumbnailUrl: thumb,
                    subscribers: subscribers.isNotEmpty
                        ? subscribers
                        : 'Subscribed',
                    isCustom: false,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getUserArtists InnerTube error: $e');
    }

    return artists;
  }

  Future<List<VideoItem>> searchVideos(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchVideos(trimmedQuery);
      return results.where((v) => v.videoId.isNotEmpty).map((v) {
        String? thumb;
        if (v.thumbnails.isNotEmpty) {
          final raw = v.thumbnails.last.url;
          thumb = SongItem.upgradeThumbnail(
            raw.startsWith('//') ? 'https:$raw' : raw,
          );
        }
        thumb ??= 'https://i.ytimg.com/vi/${v.videoId}/hqdefault.jpg';
        return VideoItem(
          id: v.videoId,
          title: v.name.isNotEmpty ? v.name : 'Untitled Video',
          artist: v.artist.name.isNotEmpty ? v.artist.name : 'Unknown Artist',
          thumbnailUrl: thumb,
          durationSeconds: v.duration,
        );
      }).toList();
    } catch (e) {
      debugPrint('searchVideos error: $e');
      return [];
    }
  }

  /// Searches playlists on YouTube Music.
  Future<List<PlaylistItem>> searchPlaylists(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchPlaylists(trimmedQuery);
      return results.where((p) => p.playlistId.isNotEmpty).map((p) {
        String? thumb;
        if (p.thumbnails.isNotEmpty) {
          final raw = p.thumbnails.last.url;
          thumb = SongItem.upgradeThumbnail(
            raw.startsWith('//') ? 'https:$raw' : raw,
          );
        }
        return PlaylistItem(
          id: p.playlistId,
          title: p.name.isNotEmpty ? p.name : 'Untitled Playlist',
          author: p.artist.name.isNotEmpty ? p.artist.name : 'YouTube Music',
          thumbnailUrl: thumb,
        );
      }).toList();
    } catch (e) {
      debugPrint('searchPlaylists error: $e');
      return [];
    }
  }

  /// Bundled multi-category search (Songs, Artists, Albums, Playlists, Videos)
  /// querying all categories concurrently with in-memory caching.
  Future<SearchResultSet> searchAll(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SearchResultSet();
    }

    final cacheKey = trimmed.toLowerCase();
    if (_searchAllMemoryCache.containsKey(cacheKey)) {
      return _searchAllMemoryCache[cacheKey]!;
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Run searches concurrently with safe fallbacks
    final songFuture = searchSongs(trimmed).catchError((e) {
      debugPrint('searchSongs error in searchAll: $e');
      return <SongItem>[];
    });
    final artistFuture = searchArtists(trimmed).catchError((e) {
      debugPrint('searchArtists error in searchAll: $e');
      return <ArtistItem>[];
    });
    final albumFuture = searchAlbums(trimmed).catchError((e) {
      debugPrint('searchAlbums error in searchAll: $e');
      return <AlbumItem>[];
    });
    final playlistFuture = searchPlaylists(trimmed).catchError((e) {
      debugPrint('searchPlaylists error in searchAll: $e');
      return <PlaylistItem>[];
    });
    final videoFuture = searchVideos(trimmed).catchError((e) {
      debugPrint('searchVideos error in searchAll: $e');
      return <VideoItem>[];
    });

    final results = await Future.wait([
      songFuture,
      artistFuture,
      albumFuture,
      playlistFuture,
      videoFuture,
    ]);

    final searchResultSet = SearchResultSet(
      songs: results[0] as List<SongItem>,
      artists: results[1] as List<ArtistItem>,
      albums: results[2] as List<AlbumItem>,
      playlists: results[3] as List<PlaylistItem>,
      videos: results[4] as List<VideoItem>,
    );

    // Warm album artwork cache for discovered albums
    for (final album in searchResultSet.albums) {
      if (album.thumbnailUrl != null && album.thumbnailUrl!.isNotEmpty) {
        _albumArtworkCache[album.id] = album.thumbnailUrl!;
      }
    }

    // Warm duration & artwork cache for discovered songs
    for (final song in searchResultSet.songs) {
      if (song.durationSeconds != null && song.durationSeconds! > 0) {
        unawaited(
          SongMetricsCacheService.instance.setDuration(
            song.id,
            song.durationSeconds!,
          ),
        );
      }
    }
    if (searchResultSet.songs.isNotEmpty) {
      unawaited(
        ArtworkCacheService.instance.prefetchArtworks(searchResultSet.songs),
      );
    }
    if (searchResultSet.artists.isNotEmpty) {
      unawaited(
        ArtworkCacheService.instance.prefetchImageUrls(
          searchResultSet.artists.map((a) => a.thumbnailUrl).toList(),
        ),
      );
    }
    if (searchResultSet.albums.isNotEmpty) {
      unawaited(
        ArtworkCacheService.instance.prefetchImageUrls(
          searchResultSet.albums.map((a) => a.thumbnailUrl).toList(),
        ),
      );
    }
    if (searchResultSet.playlists.isNotEmpty) {
      unawaited(
        ArtworkCacheService.instance.prefetchImageUrls(
          searchResultSet.playlists.map((p) => p.thumbnailUrl).toList(),
        ),
      );
    }
    if (searchResultSet.videos.isNotEmpty) {
      unawaited(
        ArtworkCacheService.instance.prefetchImageUrls(
          searchResultSet.videos.map((v) => v.thumbnailUrl).toList(),
        ),
      );
    }

    _searchAllMemoryCache[cacheKey] = searchResultSet;
    return searchResultSet;
  }

  /// Retrieves search suggestions for a given query from YouTube Music.
  Future<List<String>> getSearchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (!_isInitialized) {
      await initialize();
    }
    try {
      final suggestions = await _ytMusic.getSearchSuggestions(trimmed);
      return suggestions.where((s) => s.trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint('[MusicService] getSearchSuggestions error: $e');
      return const [];
    }
  }

  /// Curated InnerTube mood & genre categories with high-resolution imagery and playlist subtitles
  static const Map<String, ({String subtitle, String imageUrl, int color, String params})> curatedMoodMetadata = {
    'Chill': (
      subtitle: 'Coffee Shop Blend',
      imageUrl: 'https://yt3.googleusercontent.com/CDt4RjHDGr0YiX6WxARTBFkdb9k9VsAIm88sJXZ7B3O1yMoS53kLS_dy8ZIKRrFRHHCB6OJePWU1GbY=w544-h544-l90-rj',
      color: 4288988671,
      params: 'ggMPOg1uX1JOQWZFeDByc2Jm',
    ),
    'Commute': (
      subtitle: 'Feel-Good Hip Hop and R&B',
      imageUrl: 'https://yt3.googleusercontent.com/TALQkjUiJF2lNPNzYAFFAvJfJPiLHtSHF2YbtXKLA84h-ZaN7X8scDed7OTAiFgKx6CZ4K2ZAZyqUUw=w544-h544-l90-rj',
      color: 4294951424,
      params: 'ggMPOg1uX044Z2o5WERLckpU',
    ),
    'Diwali': (
      subtitle: 'Bollywood Party',
      imageUrl: 'https://yt3.googleusercontent.com/HFR703oTI5lyhzTdsn1Zo_Npm9QxtIMyVzz7JzzD1rxdgfESj97ckbb2cw7Ao-s5nmZ6AX56Xs3jLQ=w544-h544-l90-rj',
      color: 4284506208,
      params: 'ggMPOg1uX0lQVm1ablYxWml5',
    ),
    'Energize': (
      subtitle: 'Pump-Up Pop',
      imageUrl: 'https://yt3.googleusercontent.com/PiHeLTzGupMv0PkTI0dg-sstkzOx8yNkBOEfV67yP_sUkJtXLRk4JO8dwhz18rZAz9gHJSAGHeztsJ4=w544-h544-l90-rj',
      color: 4294961024,
      params: 'ggMPOg1uX2lRZUZiMnNrQnJW',
    ),
    'Feel good': (
      subtitle: 'Sunshine Indie',
      imageUrl: 'https://yt3.googleusercontent.com/Am3iIGzF5Dz-8e2nKJMQfn5TE_1aAT2wUOKHJJ2xzfSoS0LT4XV6pOZax_mKLc2HarHbqnm_VQ0sY9vF=w544-h544-l90-rj',
      color: 4289003428,
      params: 'ggMPOg1uXzZQbDB5eThLRTQ3',
    ),
    'Focus': (
      subtitle: 'Lofi Loft',
      imageUrl: 'https://yt3.googleusercontent.com/9I45SYZAfTeR17ByV9i2yDpWhQ5DTWMCrW3Lei8vMIiZzeyUnf2zRFUDBob4TGwgUkXAAR_x1Xa8VA=w544-h544-l90-rj',
      color: 4291611852,
      params: 'ggMPOg1uX0NvNGNhWThMYWRh',
    ),
    'Gaming': (
      subtitle: 'Gaming Hits',
      imageUrl: 'https://yt3.googleusercontent.com/QrISu_Bk4sR6MN_TUD2bbWO4ZyfdSFJVE8JPpCD4P9uCRmyQtE1e3HjxtwsiomjiR0idTKD7Wl6w9A=w544-h544-l90-rj',
      color: 4284506208,
      params: 'ggMPOg1uX3NmUVV4Vzl3WGQ0',
    ),
    'Party': (
      subtitle: 'Bollywood Dance Essentials',
      imageUrl: 'https://yt3.googleusercontent.com/kHXGXRuL3_9v5rKBGrGX_-TY3HMrMvuTO1cHaD_dGZS04YFp1WxF8hXXmTwjXSv-FVxNlJE201hPoKI=w544-h544-l90-rj',
      color: 4290018303,
      params: 'ggMPOg1uX0pmQ0s2V0JRclZs',
    ),
    'Romance': (
      subtitle: 'Bollywood Romantic Moments',
      imageUrl: 'https://yt3.googleusercontent.com/HEdSa36FoDLbUaGWynkGzG_QFFElSh2RpOF4UOXgPwWTUkbqynoWw8W5trrQAnQM76PgryWuXYTLMgw=w544-h544-l90-rj',
      color: 4291559424,
      params: 'ggMPOg1uX0FzQ2FhZWtUY211',
    ),
    'Sad': (
      subtitle: 'Bollywood Melancholy',
      imageUrl: 'https://yt3.googleusercontent.com/q4iCQuoHBeumL9s0LMTIiCMeYR2EdIlNp_YAKiKUjlehuF8-lRO-_PvCplt2TCvKQV3ECPQGZU_pmrQ=w544-h544-l90-rj',
      color: 4287401100,
      params: 'ggMPOg1uX0JLQ0gySWZKZVY1',
    ),
    'Sleep': (
      subtitle: 'Classical for Sleeping',
      imageUrl: 'https://yt3.googleusercontent.com/SwyowKe-kDLokD2wEouPllJwjfKlG73podaFDHBzaEDeR0mu3mgp0x4iy7ouTDD0JuksjzG3ObZsfQ=w544-h544-l90-rj',
      color: 4286267099,
      params: 'ggMPOg1uX1MxaFQ3Z0JMZkN4',
    ),
    'Workout': (
      subtitle: 'HIIT Desi Pop',
      imageUrl: 'https://yt3.googleusercontent.com/ugsYfFh0MWr_EITP7kg1K3PMeDx2HC_EkEqQzD7-ww31VEwGHJPuCXIdcxBAqJGc8z4o9Q9shyxQsA=w544-h544-l90-rj',
      color: 4294937920,
      params: 'ggMPOg1uX09LWkhnTjRGRUJh',
    ),
    'Classical': (
      subtitle: 'Essential Classical',
      imageUrl: 'https://yt3.googleusercontent.com/gkQ7vbmDn5Mdo2e0-dpTdiTD7uTEYXML6uPPTFLiRxe4ZVyAi5XNkzj_Of0WCwinF-Iup7YcM8O5iw=w544-h544-l90-rj',
      color: 4291611852,
      params: 'ggMPOg1uX1N4VmduTmdUR3dm',
    ),
    'Dance & electronic': (
      subtitle: 'Luxe Life',
      imageUrl: 'https://yt3.googleusercontent.com/HU5EiWVx-LtNAfQFoRATBZiDhSFc4JfAKCYcH2Lbi7mt8LEmsW5bsY9gLjCNU4pN47-NFxZ0Z_vLC-cI=w544-h544-l90-rj',
      color: 4278227647,
      params: 'ggMPOg1uX1NPTld3SDN3WGs4',
    ),
    'Country & Americana': (
      subtitle: 'Kick-Back Country',
      imageUrl: 'https://yt3.googleusercontent.com/T77OxvLBXUgKGdrRlde6oz9x4qijWMX-7TI0Iaez6btX87sZ2dCLAY3pPruIz-wCxU4QuLkMCnz4aE0=w544-h544-l90-rj',
      color: 4281564671,
      params: 'ggMPOg1uX1RXcFlyZEpRb1d3',
    ),
    'Bhojpuri': (
      subtitle: 'Bhojpuri Hitlist',
      imageUrl: 'https://yt3.googleusercontent.com/PbRBvk0EnWunitypEmB4gIMX-P3CK_XUZReOW8u_sshuCQDITvi8wE6_lEmmgz2A-Lw9Pgzy4TTbKdI=w544-h544-l90-rj',
      color: 4289333674,
      params: 'ggMPOg1uX05iYWtoenBuUkZX',
    ),
    'Bengali': (
      subtitle: 'Bengali Hitlist',
      imageUrl: 'https://yt3.googleusercontent.com/-BiMRAPPMOnnJhzj3gaBp8jBqIbJ63r6HWRJFHQVIs7EWFoSvZ8lXJpwQz9mfuk1SklqAV53-qt9yg=w544-h544-l90-rj',
      color: 4294961024,
      params: 'ggMPOg1uX1ZEZzBvYUp0TGNI',
    ),
  };

  Future<({List<MusicCategory> moods, List<MusicCategory> genres})>
  _fetchMoodsAndGenres() async {
    final List<MusicCategory> parsedMoods = [];
    final List<MusicCategory> parsedGenres = [];

    try {
      dynamic moodRes;
      if (_currentAccount != null) {
        moodRes = await postInnerTube(
          'browse',
          bodyExtras: {'browseId': 'FEmusic_moods_and_genres'},
        );
      }
      moodRes ??= await _ytMusic.constructRequest(
        'browse',
        body: {'browseId': 'FEmusic_moods_and_genres'},
      );

      if (moodRes is Map) {
        final tabs = traverseList(moodRes, [
          'contents',
          'singleColumnBrowseResultsRenderer',
          'tabs',
        ]);
        final sectionContents =
            tabs.firstOrNull?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List? ??
            [];

        for (final section in sectionContents) {
          final title =
              traverseString(section, [
                'gridRenderer',
                'header',
                'gridHeaderRenderer',
                'title',
                'runs',
              ]) ??
              traverseString(section, [
                'musicCarouselShelfRenderer',
                'header',
                'musicCarouselShelfBasicHeaderRenderer',
                'title',
                'runs',
              ]) ??
              '';

          final items =
              (section['gridRenderer']?['items'] as List?) ??
              (section['musicCarouselShelfRenderer']?['contents'] as List?) ??
              [];

          for (final it in items) {
            final btn = it['musicNavigationButtonRenderer'];
            if (btn == null) continue;
            final textRuns = btn['buttonText']?['runs'] as List? ?? [];
            final text = textRuns.isNotEmpty
                ? textRuns.first['text'] as String? ?? ''
                : '';
            final color = (btn['solid']?['leftStripeColor'] as num?)?.toInt();
            final params = btn['clickCommand']?['browseEndpoint']?['params'] as String?;

            if (text.isNotEmpty) {
              final curated = curatedMoodMetadata[text];
              final cat = MusicCategory(
                title: text,
                colorValue: color ?? curated?.color,
                params: params ?? curated?.params,
                imageUrl: curated?.imageUrl,
                subtitle: curated?.subtitle,
              );
              if (title.toLowerCase().contains('mood') ||
                  title.toLowerCase().contains('moment')) {
                parsedMoods.add(cat);
              } else {
                parsedGenres.add(cat);
              }
            }
          }
        }

        // If sectionContents didn't yield items, collect any navigation buttons
        if (parsedMoods.isEmpty && parsedGenres.isEmpty) {
          final buttons = _collectRenderers(
            moodRes,
            'musicNavigationButtonRenderer',
          );
          for (int i = 0; i < buttons.length; i++) {
            final btn = buttons[i];
            final text = _extractNodeText(btn['buttonText']).trim();
            final color = (btn['solid']?['leftStripeColor'] as num?)?.toInt();
            final params = btn['clickCommand']?['browseEndpoint']?['params'] as String?;
            if (text.isNotEmpty) {
              final curated = curatedMoodMetadata[text];
              final cat = MusicCategory(
                title: text,
                colorValue: color ?? curated?.color,
                params: params ?? curated?.params,
                imageUrl: curated?.imageUrl,
                subtitle: curated?.subtitle,
              );
              if (i < 8) {
                parsedMoods.add(cat);
              } else {
                parsedGenres.add(cat);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_fetchMoodsAndGenres error: $e');
    }

    if (parsedMoods.isEmpty && parsedGenres.isEmpty) {
      curatedMoodMetadata.forEach((name, data) {
        parsedMoods.add(MusicCategory(
          title: name,
          colorValue: data.color,
          params: data.params,
          imageUrl: data.imageUrl,
          subtitle: data.subtitle,
        ));
      });
    }

    return (moods: parsedMoods, genres: parsedGenres);
  }

  /// Fetches lyrics using either lrc.red (Apple Music TTML / word-synced) or YouTube Music.
  Future<LyricsResult> getLyricsWithMetadata({
    required String videoId,
    required String title,
    required String artist,
    String? album,
    String? isrc,
    int? durationSeconds,
    LyricsProviderType provider = LyricsProviderType.lrcRed,
  }) async {
    return _lyricsService.fetchLyricsForProvider(
      provider: provider,
      title: title,
      artist: artist,
      videoId: videoId,
      isrc: isrc,
      durationSeconds: durationSeconds,
      ytFallback: () => _fetchYtMusicLyrics(videoId),
    );
  }

  /// Backward-compatible getLyrics method.
  Future<List<LyricLine>> getLyrics(
    String videoId, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
  }) async {
    if (title != null && artist != null) {
      final res = await getLyricsWithMetadata(
        videoId: videoId,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
      );
      if (res.lines.isNotEmpty) return res.lines;
    }
    return _fetchYtMusicLyrics(videoId);
  }

  Future<List<LyricLine>> _fetchYtMusicLyrics(String videoId) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    // 1. Try timed lyrics first for synchronized karaoke scrolling
    try {
      final timed = await _ytMusic.getTimedLyrics(trimmedId);
      if (timed != null && timed.timedLyricsData.isNotEmpty) {
        final parsed = timed.timedLyricsData
            .map((item) {
              final line = item.lyricLine?.trim() ?? '';
              return LyricLine(
                text: line,
                startTimeMs: item.cueRange?.startTimeMilliseconds,
                endTimeMs: item.cueRange?.endTimeMilliseconds,
              );
            })
            .where((l) => l.text.isNotEmpty)
            .toList();

        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('getTimedLyrics fallback: $e');
    }

    // 2. Fallback to plain text lyrics
    try {
      final plain = await _ytMusic.getLyrics(trimmedId);
      if (plain != null && plain.trim().isNotEmpty) {
        return plain
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => LyricLine(text: l))
            .toList();
      }
    } catch (e) {
      debugPrint('getLyrics error: $e');
    }

    return [];
  }

  /// Searches for songs by query string with in-memory caching.
  Future<List<SongItem>> searchSongs(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [];
    }

    final cacheKey = trimmedQuery.toLowerCase();
    if (_searchSongsMemoryCache.containsKey(cacheKey)) {
      return _searchSongsMemoryCache[cacheKey]!;
    }

    if (!_isInitialized) {
      await initialize();
    }

    final results = await _ytMusic.searchSongs(trimmedQuery);

    final songs = results.where((song) => song.videoId.isNotEmpty).map((song) {
      final artistName = song.artist.name.isNotEmpty
          ? song.artist.name
          : 'Unknown Artist';

      String? thumbUrl;
      if (song.thumbnails.isNotEmpty) {
        thumbUrl = song.thumbnails.last.url;
      }

      return SongItem(
        id: song.videoId,
        title: song.name.isNotEmpty ? song.name : 'Untitled Track',
        artist: artistName,
        album: song.album?.name,
        thumbnailUrl: SongItem.upgradeThumbnail(thumbUrl),
        durationSeconds: song.duration,
      );
    }).toList();

    for (final song in songs) {
      if (song.durationSeconds != null && song.durationSeconds! > 0) {
        unawaited(
          SongMetricsCacheService.instance.setDuration(
            song.id,
            song.durationSeconds!,
          ),
        );
      }
    }
    if (songs.isNotEmpty) {
      unawaited(ArtworkCacheService.instance.prefetchArtworks(songs));
    }

    _searchSongsMemoryCache[cacheKey] = songs;
    return songs;
  }

  /// Invalidates any cached audio stream URL for [videoId].
  void invalidateStream(String videoId) {
    _streamCache.remove(videoId.trim());
  }

  /// Resolves the audio stream info (URL, matching headers, bitrate, mimeType)
  /// using client fallback rotation and stream probing.
  /// Pass [forceRefresh] = true to bypass memory cache and get a fresh streaming URL.
  Future<AudioStreamInfo> resolveAudioStream(
    String videoId, {
    bool forceRefresh = false,
  }) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('Video ID cannot be empty');
    }

    if (forceRefresh) {
      _streamCache.remove(trimmedId);
    }

    // Check memory cache with smart URL expiry check
    final cached = _streamCache[trimmedId];
    if (cached != null) {
      bool isCacheValid = false;
      final expireMatch = RegExp(r'[?&]expire=(\d+)')
          .firstMatch(cached.info.url);
      if (expireMatch != null) {
        final expireSec = int.tryParse(expireMatch.group(1) ?? '');
        if (expireSec != null) {
          final expireDate = DateTime.fromMillisecondsSinceEpoch(
            expireSec * 1000,
          );
          final age = DateTime.now().difference(cached.timestamp);
          // Only trust cached URL if within 1 hour and at least 30 min before expire
          if (age < const Duration(hours: 1) &&
              DateTime.now().isBefore(
                expireDate.subtract(const Duration(minutes: 30)),
              )) {
            isCacheValid = true;
          }
        }
      } else {
        final age = DateTime.now().difference(cached.timestamp);
        if (age < const Duration(hours: 1)) {
          isCacheValid = true;
        }
      }

      if (isCacheValid) {
        if (cached.info.durationSeconds != null &&
            cached.info.durationSeconds! > 0) {
          unawaited(
            SongMetricsCacheService.instance.setDuration(
              trimmedId,
              cached.info.durationSeconds!,
            ),
          );
        }
        return cached.info;
      }
      _streamCache.remove(trimmedId);
    }

    if (!_isInitialized) {
      await initialize();
    }

    Object? lastError;

    // Try each client tier in order until a verified stream is obtained
    for (final client in _clientTiers) {
      try {
        final streamInfo = await _extractWithClient(trimmedId, client);
        if (streamInfo != null) {
          // Probe stream URL with bounded range (0-1024) to ensure HTTP 206 / 200 before returning
          final isViable = await _probeStreamUrl(
            streamInfo.url,
            streamInfo.headers,
          );
          if (isViable) {
            _streamCache[trimmedId] = (
              info: streamInfo,
              timestamp: DateTime.now(),
            );
            if (streamInfo.durationSeconds != null &&
                streamInfo.durationSeconds! > 0) {
              unawaited(
                SongMetricsCacheService.instance.setDuration(
                  trimmedId,
                  streamInfo.durationSeconds!,
                ),
              );
            }
            return streamInfo;
          }
        }
      } catch (e) {
        lastError = e;
        // Continue to fallback client
      }
    }

    if (lastError != null) {
      throw Exception(
        'Failed to resolve stream for track $trimmedId: $lastError',
      );
    }
    throw Exception(
      'No playable audio stream could be verified for track $trimmedId',
    );
  }

  /// Resolves a crisp high-definition video stream (HLS .m3u8 or progressive MP4) for [videoId].
  /// Used for Apple Music / Spotify Canvas-style moving background video in the player screen.
  Future<VideoStreamInfo?> resolveVideoStream(String videoId) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return null;

    final cached = _videoStreamCache[trimmedId];
    if (cached != null) {
      return cached;
    }

    if (!_isInitialized) {
      await initialize();
    }

    for (final client in _clientTiers) {
      try {
        final data = await _ytMusic.constructRequest(
          "player",
          body: {"videoId": trimmedId},
          options: ClientRequestOptions(
            clientName: client.clientName,
            clientVersion: client.clientVersion,
          ),
        );

        if (data is! Map) continue;

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) continue;

        // 1. Prefer HLS Variant Playlist locked to crisp 720p/1080p (.m3u8) - prevents
        // ExoPlayer ABR from starting blurry at 144p/240p or lagging during quality switches.
        final hlsUrl = streamingData['hlsManifestUrl'] as String?;
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          final headers = {'User-Agent': client.userAgent};
          final lockedVariant = await _pickCrispHlsVariant(hlsUrl, headers);
          final info = lockedVariant ??
              VideoStreamInfo(
                url: hlsUrl,
                headers: headers,
                width: 1920,
                height: 1080,
                qualityLabel: '1080p',
              );
          _videoStreamCache[trimmedId] = info;
          return info;
        }

        // 2. Next check adaptiveFormats H.264 MP4 (720p/1080p hardware-decoded video-only stream)
        final adaptiveFormats =
            streamingData['adaptiveFormats'] as List<dynamic>? ?? [];
        final h264Adaptive = adaptiveFormats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          final h = (f['height'] as num?)?.toInt() ?? 0;
          return mime.startsWith('video/mp4') &&
              mime.contains('avc1') &&
              h >= 720 &&
              h <= 1080 &&
              f.containsKey('url');
        }).toList();

        if (h264Adaptive.isNotEmpty) {
          h264Adaptive.sort((a, b) {
            final aH = (a['height'] as num?)?.toInt() ?? 0;
            final bH = (b['height'] as num?)?.toInt() ?? 0;
            // Always prefer highest definition first (1080p > 720p) for crystal-clear playback
            return bH.compareTo(aH);
          });
          final selected = h264Adaptive.first;
          final videoUrl = selected['url'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            final w = (selected['width'] as num?)?.toInt() ?? 1280;
            final h = (selected['height'] as num?)?.toInt() ?? 720;
            final q = selected['qualityLabel'] as String? ?? '${h}p';
            final info = VideoStreamInfo(
              url: videoUrl,
              headers: {'User-Agent': client.userAgent},
              width: w,
              height: h,
              qualityLabel: q,
            );
            _videoStreamCache[trimmedId] = info;
            return info;
          }
        }

        // 3. Next check combined progressive MP4 formats (>= 720p first)
        final progressiveFormats =
            (streamingData['formats'] as List<dynamic>? ?? []).where((f) {
              final mime = f['mimeType'] as String? ?? '';
              return mime.startsWith('video/mp4') && f.containsKey('url');
            }).toList();

        if (progressiveFormats.isNotEmpty) {
          progressiveFormats.sort((a, b) {
            final aHeight = (a['height'] as num?)?.toInt() ?? 0;
            final bHeight = (b['height'] as num?)?.toInt() ?? 0;
            return bHeight.compareTo(aHeight);
          });
          final selected = progressiveFormats.first;
          final videoUrl = selected['url'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            final w = (selected['width'] as num?)?.toInt() ?? 640;
            final h = (selected['height'] as num?)?.toInt() ?? 360;
            final q = selected['qualityLabel'] as String? ?? '${h}p';
            final info = VideoStreamInfo(
              url: videoUrl,
              headers: {'User-Agent': client.userAgent},
              width: w,
              height: h,
              qualityLabel: q,
            );
            _videoStreamCache[trimmedId] = info;
            return info;
          }
        }

        // 4. Fallback to remaining adaptiveFormats MP4
        final videoFormats = adaptiveFormats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          return mime.startsWith('video/mp4') && f.containsKey('url');
        }).toList();

        if (videoFormats.isEmpty) continue;

        videoFormats.sort((a, b) {
          final bHeight = (b['height'] as num?)?.toInt() ?? 0;
          final aHeight = (a['height'] as num?)?.toInt() ?? 0;
          return bHeight.compareTo(aHeight);
        });

        final selectedFormat = videoFormats.firstWhere((f) {
          final h = (f['height'] as num?)?.toInt() ?? 0;
          return h >= 720 && h <= 1080;
        }, orElse: () => videoFormats.first);

        final videoUrl = selectedFormat['url'] as String?;
        if (videoUrl == null || videoUrl.isEmpty) continue;

        final width = (selectedFormat['width'] as num?)?.toInt() ?? 1280;
        final height = (selectedFormat['height'] as num?)?.toInt() ?? 720;
        final qualityLabel =
            selectedFormat['qualityLabel'] as String? ?? '${height}p';

        final info = VideoStreamInfo(
          url: videoUrl,
          headers: {'User-Agent': client.userAgent},
          width: width,
          height: height,
          qualityLabel: qualityLabel,
        );

        _videoStreamCache[trimmedId] = info;
        return info;
      } catch (_) {
        // Continue to fallback client
      }
    }

    _videoStreamCache[trimmedId] = null;
    return null;
  }

  /// Parses an HLS master playlist and locks onto a crisp 720p or 1080p H.264 variant stream
  /// so ExoPlayer/AVPlayer never starts blurry at 144p/240p or stalls on adaptive bitrate jumps.
  Future<VideoStreamInfo?> _pickCrispHlsVariant(
    String masterUrl,
    Map<String, String> headers,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse(masterUrl);
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 2));
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));

      final lines = body.split('\n').map((l) => l.trim()).toList();
      final resRegex = RegExp(r'RESOLUTION=(\d+)x(\d+)');
      final candidates = <({String url, int width, int height, bool isH264})>[];

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i];
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final nextLine = lines[i + 1];
        if (nextLine.isEmpty || nextLine.startsWith('#')) continue;

        final match = resRegex.firstMatch(line);
        if (match == null) continue;
        final w = int.tryParse(match.group(1) ?? '') ?? 0;
        final h = int.tryParse(match.group(2) ?? '') ?? 0;
        if (h < 720 || h > 1080) continue;

        final isH264 = line.contains('avc1') || !line.contains('vp09') && !line.contains('av01');
        final resolvedUrl = uri.resolve(nextLine).toString();
        candidates.add((url: resolvedUrl, width: w, height: h, isH264: isH264));
      }

      if (candidates.isEmpty) return null;

      // Prefer hardware-accelerated H.264 (avc1) highest quality (1080p first, then 720p)
      candidates.sort((a, b) {
        if (a.isH264 != b.isH264) return a.isH264 ? -1 : 1;
        return b.height.compareTo(a.height);
      });

      final best = candidates.first;
      return VideoStreamInfo(
        url: best.url,
        headers: headers,
        width: best.width,
        height: best.height,
        qualityLabel: '${best.height}p',
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Backwards-compatible convenience method that returns just the direct stream URL.
  Future<String> getAudioStreamUrl(String videoId) async {
    final info = await resolveAudioStream(videoId);
    return info.url;
  }

  /// Queries the InnerTube player endpoint with the given client profile.
  Future<AudioStreamInfo?> _extractWithClient(
    String videoId,
    _InnerTubeClientConfig clientConfig,
  ) async {
    final data = await _ytMusic.constructRequest(
      "player",
      body: {"videoId": videoId},
      options: ClientRequestOptions(
        clientName: clientConfig.clientName,
        clientVersion: clientConfig.clientVersion,
      ),
    );

    if (data is! Map) return null;

    final playabilityStatus =
        data['playabilityStatus'] as Map<String, dynamic>?;
    if (playabilityStatus != null && playabilityStatus['status'] != 'OK') {
      return null;
    }

    final streamingData = data['streamingData'] as Map<String, dynamic>?;
    if (streamingData == null) return null;

    final adaptiveFormats =
        streamingData['adaptiveFormats'] as List<dynamic>? ?? [];

    // Filter available audio formats with direct playable URLs
    final audioFormats = adaptiveFormats.where((f) {
      final mime = f['mimeType'] as String? ?? '';
      return mime.startsWith('audio/') && f.containsKey('url');
    }).toList();

    if (audioFormats.isEmpty) return null;

    // Sort by bitrate descending
    audioFormats.sort((a, b) {
      final bBitrate = (b['bitrate'] as num?)?.toInt() ?? 0;
      final aBitrate = (a['bitrate'] as num?)?.toInt() ?? 0;
      return bBitrate.compareTo(aBitrate);
    });

    // Prefer AAC (audio/mp4) for 100% universal hardware decoding across Android & Apple platforms
    final selectedFormat = audioFormats.firstWhere(
      (f) => (f['mimeType'] as String? ?? '').contains('audio/mp4'),
      orElse: () => audioFormats.first,
    );

    final streamUrl = selectedFormat['url'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) return null;

    final bitrate = (selectedFormat['bitrate'] as num?)?.toInt() ?? 128000;
    final mimeType = selectedFormat['mimeType'] as String? ?? 'audio/mp4';
    final contentLength = int.tryParse(
      selectedFormat['contentLength'] as String? ?? '',
    );

    int? durationMs;
    final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
    if (videoDetails != null && videoDetails['lengthSeconds'] != null) {
      final lenSec = int.tryParse(videoDetails['lengthSeconds'].toString());
      if (lenSec != null && lenSec > 0) {
        durationMs = lenSec * 1000;
      }
    }
    if (durationMs == null && selectedFormat['approxDurationMs'] != null) {
      durationMs = int.tryParse(selectedFormat['approxDurationMs'].toString());
    }

    return AudioStreamInfo(
      url: streamUrl,
      headers: {'User-Agent': clientConfig.userAgent},
      bitrate: bitrate,
      mimeType: mimeType,
      contentLength: contentLength,
      durationMs: durationMs,
    );
  }

  /// BitChord-style probe to verify that the stream URL actually serves bytes
  /// with the designated headers before handing it to the player.
  Future<bool> _probeStreamUrl(
    String streamUrl,
    Map<String, String> headers,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(streamUrl));
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('Range', 'bytes=0-1024');

      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final isSuccess =
          response.statusCode == 206 || response.statusCode == 200;
      await response.drain();
      return isSuccess;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  void dispose() {
    _streamCache.clear();
    _videoStreamCache.clear();
    _artistDetailsCache.clear();
    _animatedArtworkCache.clear();
    _animatedArtworkDataCache.clear();
    _lyricsService.dispose();
    _cachedHomeData = null;
  }
}
