import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/config_provider.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';
import 'services/config_optimizer_service.dart';
import 'services/fragment_service.dart';
import 'services/auto_reconnect_service.dart';
import 'services/connection_health_service.dart';

/// Opens local storage and services in parallel.
///
/// Runs behind the splash animation instead of before the first frame, so the
/// app paints immediately. A failure is reported instead of leaving a blank
/// screen.
Future<void> bootstrapServices() async {
  await Hive.initFlutter();
  await Future.wait<void>([
    ConfigOptimizerService().initialize(),
    FragmentService().initialize(),
    AutoReconnectService().initializeStorage(),
    ConnectionHealthService().initialize(),
  ]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for immersive dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.backgroundDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Lock orientation to portrait
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );

  runApp(const HesamVoidApp());
}

class HesamVoidApp extends StatelessWidget {
  const HesamVoidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ConfigProvider())],
      child: MaterialApp(
        title: 'Hesam Void',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

/// Animated Splash Screen
class SplashScreen extends StatefulWidget {
  /// Startup work to finish before leaving the splash. Tests can replace it.
  final Future<void> Function() bootstrap;

  const SplashScreen({super.key, this.bootstrap = bootstrapServices});

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
  static const _minimumSplash = Duration(milliseconds: 1100);
  Object? _startupError;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
    _logoController.forward();
    _sequenceTimers.add(
      Timer(const Duration(milliseconds: 350), () {
        if (mounted) _textController.forward();
      }),
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_startupError != null) setState(() => _startupError = null);
    final minimum = Completer<void>();
    _sequenceTimers.add(Timer(_minimumSplash, minimum.complete));
    try {
      await widget.bootstrap();
      await minimum.future;
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error);
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
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
                            'Local-first • Your own routes',
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

              if (_startupError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Text(
                        'Local storage could not be opened.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Close other apps and try again. If it keeps '
                        'happening, reinstall the latest release.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('TRY AGAIN'),
                      ),
                    ],
                  ),
                )
              else
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
