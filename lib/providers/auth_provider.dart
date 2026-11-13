import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';
import '../services/music_service.dart';
import 'home_data_provider.dart';
import 'library_provider.dart';
import 'music_service_provider.dart';

const String _kGoogleAccountKey = 'ytm_google_account_v1';

class AuthNotifier extends StateNotifier<UserAccount?> {
  final Ref _ref;
  bool _isHealing = false;

  AuthNotifier(this._ref) : super(null) {
    _loadStoredAccount();
  }

  Future<void> _loadStoredAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_kGoogleAccountKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final account = UserAccount.fromJsonString(jsonString);
        _ref.read(musicServiceProvider).setAuthAccount(account);
        state = account;

        // If avatarUrl or verified details are missing, attempt to fetch in background to heal profile
        if (account.avatarUrl == null ||
            account.avatarUrl!.isEmpty ||
            account.displayName == 'YouTube Music User') {
          _healMissingAvatar(account);
        }
      }
    } catch (e) {
      debugPrint('Failed to load stored Google YouTube Music account: $e');
    }
  }

  /// Refreshes the active account profile (avatar, name, email) from YouTube
  Future<void> refreshProfile() async {
    final account = state;
    if (account != null) {
      await _healMissingAvatar(account);
    }
  }

  /// Attempts to fetch verified avatar in the background if previously missing
  Future<void> _healMissingAvatar(UserAccount account) async {
    if (_isHealing) return;
    _isHealing = true;
    try {
      var cookiesToUse = account.cookies;
      try {
        final freshCookies =
            await MusicService.extractFreshCookiesFromWebView();
        if (freshCookies != null && freshCookies.isNotEmpty) {
          cookiesToUse = freshCookies;
        }
      } catch (_) {}

      final profile = await _ref
          .read(musicServiceProvider)
          .fetchAccountProfile(
            cookies: cookiesToUse,
            dataSyncId: account.dataSyncId,
            pageId: account.pageId,
            authUser: account.authUser,
            visitorData: account.visitorData,
          );
      if (profile != null &&
          (profile.avatarUrl != null || profile.displayName.isNotEmpty)) {
        final updated = account.copyWith(
          cookies: cookiesToUse,
          avatarUrl: profile.avatarUrl ?? account.avatarUrl,
          displayName:
              profile.displayName.isNotEmpty &&
                  profile.displayName != 'YouTube Music User'
              ? profile.displayName
              : account.displayName,
          email: profile.email.isNotEmpty ? profile.email : account.email,
        );
        state = updated;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kGoogleAccountKey, updated.toJsonString());
        _ref.read(musicServiceProvider).setAuthAccount(updated);
      }
    } catch (e) {
      debugPrint('Error healing missing profile avatar: $e');
    } finally {
      _isHealing = false;
    }
  }

  /// Connects a Google Account with YouTube Music credentials and syncs all tabs
  Future<void> signInWithGoogleAccount(UserAccount account) async {
    state = account;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGoogleAccountKey, account.toJsonString());
    } catch (e) {
      debugPrint('Failed to save Google account to SharedPreferences: $e');
    }

    // Configure MusicService with user credentials
    _ref.read(musicServiceProvider).setAuthAccount(account);

    // Refresh Home, Explore, and Library all at once in parallel seamlessly!
    syncAllTabs();
  }

  /// Syncs Home, Explore, and Library all at once in parallel
  Future<void> syncAllTabs() async {
    try {
      await Future.wait([
        // 1. Home feed and Explore categories & charts
        _ref.read(homeDataProvider.notifier).refresh(),
        // 2. Liked songs
        _ref.read(youtubeLikedSongsProvider.notifier).fetchLikedSongs(),
        // 3. User Playlists
        _ref.refresh(userPlaylistsProvider.future),
        // 4. User Albums
        _ref.refresh(userAlbumsProvider.future),
        // 5. User Artists
        _ref.refresh(userArtistsProvider.future),
      ]);
    } catch (e) {
      debugPrint('Error syncing all tabs: $e');
    }
  }

  /// Toggles whether home feed requests use personal account recommendations
  Future<void> togglePersonalizedRecommendations(bool enabled) async {
    if (state == null) return;
    final updated = state!.copyWith(isPersonalizedEnabled: enabled);
    await signInWithGoogleAccount(updated);
  }

  /// Disconnects and signs out of the Google YouTube Music account
  Future<void> signOut() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGoogleAccountKey);
    } catch (e) {
      debugPrint('Failed to clear Google account from SharedPreferences: $e');
    }

    _ref.read(musicServiceProvider).setAuthAccount(null);
    syncAllTabs();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  return AuthNotifier(ref);
});
