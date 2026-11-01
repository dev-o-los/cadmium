import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_account.dart';
import 'home_data_provider.dart';
import 'music_service_provider.dart';

const String _kGoogleAccountKey = 'ytm_google_account_v1';

class AuthNotifier extends StateNotifier<UserAccount?> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(null) {
    _loadStoredAccount();
  }

  Future<void> _loadStoredAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_kGoogleAccountKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final account = UserAccount.fromJsonString(jsonString);
        state = account;
        _ref.read(musicServiceProvider).setAuthAccount(account);
      }
    } catch (e) {
      debugPrint('Failed to load stored Google YouTube Music account: $e');
    }
  }

  /// Connects a Google Account with YouTube Music credentials
  Future<void> signInWithGoogleAccount(UserAccount account) async {
    state = account;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGoogleAccountKey, account.toJsonString());
    } catch (e) {
      debugPrint('Failed to save Google account to SharedPreferences: $e');
    }

    // Configure MusicService with user credentials and refresh recommendations feed
    _ref.read(musicServiceProvider).setAuthAccount(account);
    try {
      _ref.read(homeDataProvider.notifier).refresh();
    } catch (e) {
      debugPrint('Error triggering home refresh: $e');
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
    try {
      _ref.read(homeDataProvider.notifier).refresh();
    } catch (e) {
      debugPrint('Error triggering home refresh on sign out: $e');
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  return AuthNotifier(ref);
});
