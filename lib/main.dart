import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
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
  runApp(const WavifyApp());
}

class WavifyApp extends StatelessWidget {
  const WavifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const appleMusicRed = Color(0xFFFA243C);
    const appleDarkBackground = Color(0xFF000000);
    const appleDarkSurface = Color(0xFF1C1C1E);
    const appleDarkSurfaceHigh = Color(0xFF2C2C2E);

    return MaterialApp(
      title: 'Wavify',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Dark mode only as requested
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: appleDarkBackground,
        primaryColor: appleMusicRed,
        colorScheme: const ColorScheme.dark(
          primary: appleMusicRed,
          onPrimary: Colors.white,
          secondary: appleMusicRed,
          surface: appleDarkSurface,
          onSurface: Colors.white,
          onSurfaceVariant: Color(0xFF8E8E93),
          surfaceContainerHighest: appleDarkSurfaceHigh,
          outline: Color(0xFF3A3A3C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.0,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xCC161618),
          selectedItemColor: appleMusicRed,
          unselectedItemColor: Color(0xFF8E8E93),
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
      home: const HomeScreen(),
    );
  }
}
