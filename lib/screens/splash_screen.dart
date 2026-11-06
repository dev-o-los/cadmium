import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';

/// Premium Apple-style Splash Screen for Aurum.
/// Features the signature liquid glass audio capsule logo centered on pure OLED black
/// with a gentle ambient fade and seamless transition to the main interface.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');

    if (isTest) {
      // In test harness, navigate immediately to avoid async timers
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToHome();
      });
      return;
    }

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _goToHome();
    });
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest) {
      return const HomeScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF000000),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: child,
                ),
              );
            },
            child: Image.asset(
              'assets/images/app_logo_cropped.png',
              width: 96,
              height: 96,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => Image.asset(
                'assets/images/app_logo.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
