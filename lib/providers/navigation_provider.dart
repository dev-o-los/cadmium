import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global provider for the active navigation tab index:
/// 0: Home, 1: Explore, 2: Library, 3: Search
final currentTabProvider = StateProvider<int>((ref) => 0);

