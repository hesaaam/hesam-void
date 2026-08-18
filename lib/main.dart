import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/config_provider.dart';
import 'screens/home_screen.dart';
import 'screens/windows_desktop_shell.dart';
import 'utils/app_theme.dart';
import 'services/config_optimizer_service.dart';
import 'services/fragment_service.dart';
import 'services/auto_reconnect_service.dart';
import 'services/connection_health_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize all services with persistent storage
  await ConfigOptimizerService().initialize();
  await FragmentService().initialize();
  await AutoReconnectService().initializeStorage();
  await ConnectionHealthService().initialize();

  // Android keeps the established immersive mobile presentation. Windows uses
  // its own desktop shell and must remain resizable rather than portrait-only.
  if (!Platform.isWindows) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.backgroundDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(const HesamVoidApp());
}

class HesamVoidApp extends StatelessWidget {
  const HesamVoidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ConfigProvider())],
      child: MaterialApp(
        title: Platform.isWindows
            ? 'Hesam Void 4SUPER for Windows'
            : 'Hesam Void',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Platform.isWindows
            ? const WindowsDesktopShell()
            : const SplashScreen(),
      ),
    );
  }
}

/// Animated Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  final List<Timer> _sequenceTimers = <Timer>[];

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
        );

    _startAnimations();
  }

  void _startAnimations() {
    _sequenceTimers.add(
      Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _logoController.forward();
        _sequenceTimers.add(
          Timer(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            _textController.forward();
            _sequenceTimers.add(
              Timer(const Duration(milliseconds: 2000), () {
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const HomeScreen(),
                    transitionDuration: const Duration(milliseconds: 800),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                  ),
                );
              }),
            );
          }),
        );
      }),
    );
  }

  @override
  void dispose() {
    for (final timer in _sequenceTimers) {
      timer.cancel();
    }
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              AppTheme.primaryGreen.withValues(alpha: 0.1),
              AppTheme.backgroundDark,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundCard,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGreen.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.shield_rounded,
                            color: AppTheme.primaryGreen,
                            size: 60,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),

              // Animated Text
              AnimatedBuilder(
                animation: _textController,
                builder: (context, child) {
                  return SlideTransition(
                    position: _textSlide,
                    child: Opacity(
                      opacity: _textOpacity.value,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                AppTheme.primaryGreen,
                                AppTheme.lightGreen,
                                AppTheme.primaryGreen,
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              'HESAM VOID',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'JetBrainsMono',
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Secure • Private • Free',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 14,
                              fontFamily: 'JetBrainsMono',
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 60),

              // Loading indicator
              AnimatedBuilder(
                animation: _textController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textOpacity.value,
                    child: SizedBox(
                      width: 150,
                      child: LinearProgressIndicator(
                        backgroundColor: AppTheme.backgroundElevated,
                        valueColor: const AlwaysStoppedAnimation(
                          AppTheme.primaryGreen,
                        ),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
