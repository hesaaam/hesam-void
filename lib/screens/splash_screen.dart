import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_theme.dart';
import '../services/vpn_service.dart';
import 'home_screen.dart';

/// Advanced Cinematic Splash Screen
/// Matrix-style animation with loading progress
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _matrixController;
  late AnimationController _logoController;
  late AnimationController _progressController;
  
  final VpnService _vpnService = VpnService();
  
  String _statusText = 'Initializing...';
  double _progress = 0;
  bool _isReady = false;
  String? _coreVersion;
  
  // Matrix rain characters
  final List<MatrixColumn> _matrixColumns = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    
    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    
    _matrixController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
    
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    
    // Initialize matrix columns
    _initializeMatrix();
    
    // Start loading sequence
    _startLoadingSequence();
  }

  void _initializeMatrix() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screenWidth = MediaQuery.of(context).size.width;
      final columnCount = (screenWidth / 20).floor();
      
      for (int i = 0; i < columnCount; i++) {
        _matrixColumns.add(MatrixColumn(
          x: i * 20.0,
          speed: 2 + _random.nextDouble() * 4,
          characters: List.generate(
            10 + _random.nextInt(15),
            (_) => _getRandomChar(),
          ),
          y: -_random.nextDouble() * 500,
        ));
      }
    });
  }

  String _getRandomChar() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#\$%&*ヲァィゥェォカキクケコサシスセソタチツテト';
    return chars[_random.nextInt(chars.length)];
  }

  Future<void> _startLoadingSequence() async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 1: Logo animation
    _logoController.forward();
    setState(() {
      _statusText = 'Loading Hesam Void...';
      _progress = 0.1;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Step 2: Initialize V2Ray
    setState(() {
      _statusText = 'Initializing V2Ray Core...';
      _progress = 0.3;
    });
    await _vpnService.initialize();
    _coreVersion = _vpnService.coreVersion;
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 3: Check permissions
    setState(() {
      _statusText = 'Checking permissions...';
      _progress = 0.5;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    
    // Step 4: Load configs
    setState(() {
      _statusText = 'Loading configurations...';
      _progress = 0.7;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    
    // Step 5: Testing connection
    setState(() {
      _statusText = 'Testing connection...';
      _progress = 0.85;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    
    // Step 6: Ready
    setState(() {
      _statusText = 'Ready!';
      _progress = 1.0;
      _isReady = true;
    });
    
    // Add haptic feedback
    HapticFeedback.mediumImpact();
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Navigate to home
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 800),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _matrixController.dispose();
    _logoController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Stack(
        children: [
          // Matrix rain background
          AnimatedBuilder(
            animation: _matrixController,
            builder: (context, _) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: MatrixRainPainter(
                  columns: _matrixColumns,
                  random: _random,
                ),
              );
            },
          ),
          
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Colors.transparent,
                  AppTheme.backgroundDark.withValues(alpha: 0.8),
                  AppTheme.backgroundDark,
                ],
              ),
            ),
          ),
          
          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                
                // Logo
                _buildLogo(),
                
                const SizedBox(height: 40),
                
                // App name with glitch effect
                _buildAppName(),
                
                const SizedBox(height: 8),
                
                // Tagline
                Text(
                  'SECURE • FAST • PRIVATE',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                    letterSpacing: 4,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 1000.ms, duration: 600.ms),
                
                const Spacer(flex: 2),
                
                // Loading section
                _buildLoadingSection(),
                
                const SizedBox(height: 40),
                
                // Version info
                if (_coreVersion != null)
                  Text(
                    'Xray Core: $_coreVersion',
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontFamily: 'JetBrainsMono',
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 2000.ms),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.5 + _logoController.value * 0.5,
          child: Opacity(
            opacity: _logoController.value,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryGreen,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Center(
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
    )
        .animate(target: _isReady ? 1 : 0)
        .shimmer(
          duration: 2000.ms,
          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
        );
  }

  Widget _buildAppName() {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          AppTheme.primaryGreen,
          AppTheme.accentCyan,
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
          letterSpacing: 6,
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 500.ms, duration: 800.ms)
        .slideY(begin: 0.3, end: 0, curve: Curves.easeOut)
        .then()
        .shimmer(
          duration: 3000.ms,
          color: AppTheme.accentCyan.withValues(alpha: 0.3),
        );
  }

  Widget _buildLoadingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50),
      child: Column(
        children: [
          // Progress bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: MediaQuery.of(context).size.width * 0.7 * _progress,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGreen,
                        AppTheme.accentCyan,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Status text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isReady)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen),
                  ),
                ),
              if (_isReady)
                Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.primaryGreen,
                  size: 14,
                ),
              const SizedBox(width: 10),
              Text(
                _statusText,
                style: TextStyle(
                  color: _isReady ? AppTheme.primaryGreen : AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Progress percentage
          Text(
            '${(_progress * 100).toInt()}%',
            style: TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 1500.ms, duration: 500.ms);
  }
}

/// Matrix column data
class MatrixColumn {
  double x;
  double y;
  double speed;
  List<String> characters;
  
  MatrixColumn({
    required this.x,
    required this.y,
    required this.speed,
    required this.characters,
  });
}

/// Matrix rain painter
class MatrixRainPainter extends CustomPainter {
  final List<MatrixColumn> columns;
  final Random random;
  
  MatrixRainPainter({required this.columns, required this.random});
  
  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 14,
    );

    for (var column in columns) {
      // Update position
      column.y += column.speed;
      
      // Reset if off screen
      if (column.y > size.height + column.characters.length * 20) {
        column.y = -column.characters.length * 20.0;
        // Randomize characters
        for (int i = 0; i < column.characters.length; i++) {
          if (random.nextDouble() > 0.7) {
            column.characters[i] = _getRandomChar();
          }
        }
      }
      
      // Draw characters
      for (int i = 0; i < column.characters.length; i++) {
        final charY = column.y + i * 20;
        
        if (charY < 0 || charY > size.height) continue;
        
        // Calculate alpha (fade from top to bottom)
        final alpha = i == column.characters.length - 1
            ? 1.0
            : (i / column.characters.length) * 0.5;
        
        final color = i == column.characters.length - 1
            ? Colors.white
            : AppTheme.primaryGreen.withValues(alpha: alpha);
        
        final textSpan = TextSpan(
          text: column.characters[i],
          style: textStyle.copyWith(color: color),
        );
        
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        
        textPainter.paint(canvas, Offset(column.x, charY));
      }
    }
  }
  
  String _getRandomChar() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#\$%&*';
    return chars[random.nextInt(chars.length)];
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
