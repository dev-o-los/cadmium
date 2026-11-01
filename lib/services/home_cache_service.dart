import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/home_data.dart';

/// Persistent cache service for Home Screen data.
/// Saves and loads the entire aggregated Home feed to disk so that on app launch,
/// the Home screen displays rich content instantly (under 5 milliseconds)
/// without waiting for network requests.
class HomeCacheService {
  static const String _prefKeyTime = 'wavify_home_cache_timestamp';
  static const String _prefKeyData = 'wavify_home_cache_json';
  static const String _fileName = 'home_data_cache.json';

  static final HomeCacheService _instance = HomeCacheService._internal();
  static HomeCacheService get instance => _instance;

  HomeCacheService._internal();

  HomeData? _memoryCache;
  DateTime? _lastCacheTime;

  /// Returns the in-memory cached home data if available.
  HomeData? get memoryCache => _memoryCache;

  /// Returns the timestamp of when home data was last cached.
  DateTime? get lastCacheTime => _lastCacheTime;

  bool get _isBindingInitialized {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves [HomeData] to persistent disk cache (SharedPreferences & local file).
  Future<void> saveHomeData(HomeData data) async {
    if (data.isEmpty) return;

    _memoryCache = data;
    _lastCacheTime = DateTime.now();

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final jsonString = jsonEncode(data.toJson());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyData, jsonString);
      await prefs.setInt(_prefKeyTime, _lastCacheTime!.millisecondsSinceEpoch);

      // Also persist to local documents file for redundancy
      await _saveToFile(jsonString);
    } catch (_) {}
  }

  /// Loads cached [HomeData] from memory, SharedPreferences, or local file.
  Future<HomeData?> loadHomeData() async {
    if (_memoryCache != null && !_memoryCache!.isEmpty) {
      return _memoryCache;
    }

    if (!_isBindingInitialized) return null;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final timeMs = prefs.getInt(_prefKeyTime);
      if (timeMs != null) {
        _lastCacheTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
      }

      final jsonString = prefs.getString(_prefKeyData);
      if (jsonString != null && jsonString.isNotEmpty) {
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        final homeData = HomeData.fromJson(decoded);
        if (!homeData.isEmpty) {
          _memoryCache = homeData;
          return homeData;
        }
      }

      // Fallback: load from local file
      final fileData = await _loadFromFile();
      if (fileData != null && !fileData.isEmpty) {
        _memoryCache = fileData;
        return fileData;
      }
    } catch (_) {}

    return null;
  }

  /// Checks if cache is valid and fresh within [ttl].
  bool isFresh({Duration ttl = const Duration(hours: 4)}) {
    if (_lastCacheTime == null) return false;
    return DateTime.now().difference(_lastCacheTime!) < ttl;
  }

  /// Clears persistent and in-memory home cache.
  Future<void> clear() async {
    _memoryCache = null;
    _lastCacheTime = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyData);
      await prefs.remove(_prefKeyTime);

      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('HomeCacheService.clear error: $e');
    }
  }

  Future<File> _getCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _saveToFile(String jsonString) async {
    try {
      final file = await _getCacheFile();
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  Future<HomeData?> _loadFromFile() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          return HomeData.fromJson(decoded);
        }
      }
    } catch (_) {}
    return null;
  }
}
