import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/app_theme.dart';

/// Matrix-style background with falling characters.
///
/// The effect sits behind a dark overlay, so it is tuned for low cost: glyphs
/// are laid out once and cached, frames are capped at ~30 fps, and the
/// animation stops entirely when [animate] is false (reduced or no motion).
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final Color? primaryColor;
  final bool animate;

  const AnimatedBackground({
    super.key,
    required this.child,
    this.primaryColor,
    this.animate = true,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  static const _frameInterval = Duration(milliseconds: 33);

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final List<MatrixColumn> _columns = [];
  final Random _random = Random();
  Size _size = Size.zero;
  Duration _lastTick = Duration.zero;

  Color get _primaryColor => widget.primaryColor ?? AppTheme.primaryGreen;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant AnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!widget.animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    if (_lastTick != Duration.zero && delta < _frameInterval) return;
    // Speeds are expressed per 60 fps frame; scale by the real elapsed time.
    final steps = _lastTick == Duration.zero
        ? 1.0
        : delta.inMicroseconds / 16667;
    _lastTick = elapsed;
    for (final column in _columns) {
      column.advance(steps, _size.height, _random);
    }
    _frame.value++;
  }

  void _initColumns(Size size) {
    if (_columns.isNotEmpty && size == _size) return;
    _size = size;
    _columns.clear();
    final columnCount = (size.width / 25).floor();
    for (int i = 0; i < columnCount; i++) {
      _columns.add(
        MatrixColumn(
          x: i * 25.0,
          speed: 1 + _random.nextDouble() * 3,
          glyphs: MatrixColumn.randomGlyphs(5 + _random.nextInt(15), _random),
          startY: -_random.nextDouble() * size.height * 2,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initColumns(Size(constraints.maxWidth, constraints.maxHeight));

        return Stack(
          children: [
            Container(color: AppTheme.backgroundDark),
            RepaintBoundary(
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: MatrixPainter(
                  columns: _columns,
                  maxHeight: constraints.maxHeight,
                  primaryColor: _primaryColor,
                  repaint: _frame,
                ),
              ),
            ),
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
            widget.child,
          ],
        );
      },
    );
  }
}

class MatrixColumn {
  static const String chars = '01アイウエオカキクケコサシスセソタチツテト';

  final double x;
  double speed;
  List<int> glyphs;
  double startY;

  MatrixColumn({
    required this.x,
    required this.speed,
    required this.glyphs,
    required this.startY,
  });

  int get length => glyphs.length;

  static List<int> randomGlyphs(int length, Random random) =>
      List<int>.generate(length, (_) => random.nextInt(chars.length));

  void advance(double steps, double maxHeight, Random random) {
    startY += speed * steps;
    if (startY > maxHeight + length * 20) {
      startY = -length * 20.0;
      speed = 1 + random.nextDouble() * 3;
      glyphs = randomGlyphs(glyphs.length, random);
    }
  }
}

class MatrixPainter extends CustomPainter {
  static const int _maxLength = 20;
  static Color? _cachedColor;
  static List<List<TextPainter>>? _glyphCache;

  final List<MatrixColumn> columns;
  final double maxHeight;
  final Color primaryColor;

  MatrixPainter({
    required this.columns,
    required this.maxHeight,
    required this.primaryColor,
    super.repaint,
  });

  /// TextPainters are laid out once per glyph and fade step, then reused.
  static List<List<TextPainter>> _glyphsFor(Color color) {
    if (_glyphCache != null && _cachedColor == color) return _glyphCache!;
    for (final row in _glyphCache ?? const <List<TextPainter>>[]) {
      for (final painter in row) {
        painter.dispose();
      }
    }
    _cachedColor = color;
    _glyphCache = List.generate(_maxLength, (step) {
      final opacity = (1 - step / _maxLength) * 0.15;
      return List.generate(MatrixColumn.chars.length, (index) {
        return TextPainter(
          text: TextSpan(
            text: MatrixColumn.chars[index],
            style: TextStyle(
              color: color.withValues(alpha: opacity),
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
    });
    return _glyphCache!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cache = _glyphsFor(primaryColor);
    for (final column in columns) {
      for (int i = 0; i < column.length; i++) {
        final y = column.startY + i * 20;
        if (y < 0 || y > maxHeight) continue;
        final step = (i * _maxLength / column.length).floor().clamp(
          0,
          _maxLength - 1,
        );
        cache[step][column.glyphs[i]].paint(canvas, Offset(column.x, y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter oldDelegate) =>
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.maxHeight != maxHeight ||
      !identical(oldDelegate.columns, columns);
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

    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

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
                color: widget.glowColor.withValues(
                  alpha: _glowAnimation.value * 0.5,
                ),
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
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
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
