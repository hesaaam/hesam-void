import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Animated Matrix-style background with falling characters
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final Color? primaryColor;
  
  const AnimatedBackground({
    super.key, 
    required this.child,
    this.primaryColor,
  });
  
  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<MatrixColumn> _columns = [];
  final Random _random = Random();

  Color get _primaryColor => widget.primaryColor ?? AppTheme.primaryGreen;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initColumns(Size size) {
    if (_columns.isNotEmpty) return;
    
    final columnCount = (size.width / 25).floor();
    for (int i = 0; i < columnCount; i++) {
      _columns.add(MatrixColumn(
        x: i * 25.0,
        speed: 1 + _random.nextDouble() * 3,
        length: 5 + _random.nextInt(15),
        startY: -_random.nextDouble() * size.height * 2,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initColumns(Size(constraints.maxWidth, constraints.maxHeight));
        
        return Stack(
          children: [
            // Dark background
            Container(color: AppTheme.backgroundDark),
            
            // Matrix rain effect
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: MatrixPainter(
                    columns: _columns,
                    maxHeight: constraints.maxHeight,
                    primaryColor: _primaryColor,
                  ),
                );
              },
            ),
            
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.backgroundDark.withValues(alpha: 0.9),
                    AppTheme.backgroundDark.withValues(alpha: 0.95),
                    AppTheme.backgroundDark,
                  ],
                ),
              ),
            ),
            
            // Child content
            widget.child,
          ],
        );
      },
    );
  }
}

class MatrixColumn {
  double x;
  double speed;
  int length;
  double startY;
  
  MatrixColumn({
    required this.x,
    required this.speed,
    required this.length,
    required this.startY,
  });
}

class MatrixPainter extends CustomPainter {
  final List<MatrixColumn> columns;
  final double maxHeight;
  final Color primaryColor;
  static const String chars = '01アイウエオカキクケコサシスセソタチツテト';
  final Random _random = Random();
  
  MatrixPainter({
    required this.columns, 
    required this.maxHeight,
    required this.primaryColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final column in columns) {
      column.startY += column.speed;
      
      if (column.startY > maxHeight + column.length * 20) {
        column.startY = -column.length * 20.0;
        column.speed = 1 + _random.nextDouble() * 3;
      }
      
      for (int i = 0; i < column.length; i++) {
        final y = column.startY + i * 20;
        if (y < 0 || y > maxHeight) continue;
        
        final opacity = (1 - i / column.length) * 0.15;
        final paint = Paint()
          ..color = primaryColor.withValues(alpha: opacity);
        
        final textPainter = TextPainter(
          text: TextSpan(
            text: chars[_random.nextInt(chars.length)],
            style: TextStyle(
              color: paint.color,
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(column.x, y));
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Glowing container with animation
class GlowingContainer extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double borderRadius;
  final bool animate;
  
  const GlowingContainer({
    super.key,
    required this.child,
    this.glowColor = AppTheme.primaryGreen,
    this.borderRadius = 16,
    this.animate = true,
  });
  
  @override
  State<GlowingContainer> createState() => _GlowingContainerState();
}

class _GlowingContainerState extends State<GlowingContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.glowColor.withValues(alpha: _glowAnimation.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: _glowAnimation.value * 0.5),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Container(
              color: AppTheme.backgroundCard,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// Pulse animation wrapper
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;
  
  const PulseAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.minScale = 0.95,
    this.maxScale = 1.05,
  });
  
  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}

/// Typing animation for text
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration charDuration;
  
  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.charDuration = const Duration(milliseconds: 50),
  });
  
  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _charIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _startTyping();
  }
  
  void _startTyping() async {
    while (_charIndex < widget.text.length) {
      await Future.delayed(widget.charDuration);
      if (mounted) {
        setState(() {
          _charIndex++;
          _displayedText = widget.text.substring(0, _charIndex);
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Text(
      '$_displayedText${_charIndex < widget.text.length ? '▌' : ''}',
      style: widget.style ?? Theme.of(context).textTheme.bodyLarge,
    );
  }
}
