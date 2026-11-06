import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'constants/app_colors.dart';
import 'constants/apple_typography.dart';
import 'screens/splash_screen.dart';
import 'services/artwork_cache_service.dart';
import 'services/audio_cache_service.dart';
import 'services/home_cache_service.dart';
import 'services/player_history_cache_service.dart';
import 'services/song_metrics_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize persistent caches asynchronously so app launch and playback are instant
  ArtworkCacheService.instance.init();
  AudioCacheService.instance.init();
  SongMetricsCacheService.instance.init();
  PlayerHistoryCacheService.instance.init();
  HomeCacheService.instance.loadHomeData();

  runApp(const ProviderScope(child: AurumApp()));
}

class AurumApp extends StatelessWidget {
  const AurumApp({super.key});

  @override
  Widget build(BuildContext context) {
    const appleDarkBackground = Color(0xFF000000);
    const appleDarkSurface = Color(0xFF1C1C1E);
    const appleDarkSurfaceHigh = Color(0xFF2C2C2E);

    return MaterialApp(
      title: 'Cadmium',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Dark mode only as requested
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: appleDarkBackground,
        primaryColor: Colors.white,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        listTileTheme: const ListTileThemeData(enableFeedback: false),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.white,
          surface: appleDarkSurface,
          onSurface: Colors.white,
          onSurfaceVariant: AppColors.appleSecondaryText,
          surfaceContainerHighest: appleDarkSurfaceHigh,
          outline: Color(0xFF3A3A3C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: AppleTypography.largeTitle,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xCC161618),
          selectedItemColor: Colors.white,
          unselectedItemColor: AppColors.appleSecondaryText,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/// Backwards-compatible aliases for [AurumApp].
typedef CadmiumApp = AurumApp;
typedef WavifyApp = AurumApp;
