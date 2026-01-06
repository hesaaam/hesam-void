import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_theme.dart';

/// Connection Map Animation Widget
/// Shows animated connection from user location to server on a world map
class ConnectionMap extends StatefulWidget {
  final bool isConnected;
  final String? serverCountry;
  final String? serverCity;
  final int? ping;
  
  const ConnectionMap({
    super.key,
    required this.isConnected,
    this.serverCountry,
    this.serverCity,
    this.ping,
  });
  
  @override
  State<ConnectionMap> createState() => _ConnectionMapState();
}

class _ConnectionMapState extends State<ConnectionMap>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _lineController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _lineAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _lineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _lineController, curve: Curves.easeOut),
    );
    
    _updateAnimations();
  }

  @override
  void didUpdateWidget(ConnectionMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnected != widget.isConnected) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
      _lineController.forward(from: 0);
    } else {
      _pulseController.stop();
      _lineController.reverse();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isConnected
              ? AppTheme.primaryGreen.withValues(alpha: 0.3)
              : AppTheme.backgroundElevated,
        ),
      ),
      child: Stack(
        children: [
          // Background map grid
          CustomPaint(
            size: Size.infinite,
            painter: MapGridPainter(),
          ),
          
          // Connection visualization
          AnimatedBuilder(
            animation: Listenable.merge([_pulseAnimation, _lineAnimation]),
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: ConnectionPainter(
                  isConnected: widget.isConnected,
                  pulseValue: _pulseAnimation.value,
                  lineProgress: _lineAnimation.value,
                ),
              );
            },
          ),
          
          // Location labels
          Positioned(
            left: 20,
            bottom: 20,
            child: _buildLocationLabel(
              icon: Icons.my_location_rounded,
              label: 'You',
              sublabel: 'Iran',
              color: AppTheme.accentCyan,
              isSource: true,
            ),
          ),
          
          if (widget.isConnected)
            Positioned(
              right: 20,
              top: 20,
              child: _buildLocationLabel(
                icon: Icons.vpn_lock_rounded,
                label: widget.serverCity ?? 'Server',
                sublabel: widget.serverCountry ?? 'Connected',
                color: AppTheme.primaryGreen,
                isSource: false,
                ping: widget.ping,
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .slideX(begin: 0.2, end: 0),
          
          // Status indicator
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.isConnected
                      ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                      : AppTheme.backgroundElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isConnected
                        ? AppTheme.primaryGreen
                        : AppTheme.textMuted.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.isConnected
                            ? AppTheme.primaryGreen
                            : AppTheme.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isConnected ? 'TUNNEL ACTIVE' : 'NOT CONNECTED',
                      style: TextStyle(
                        color: widget.isConnected
                            ? AppTheme.primaryGreen
                            : AppTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationLabel({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required bool isSource,
    int? ping,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            Row(
              children: [
                Text(
                  sublabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                if (ping != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.getPingColor(ping).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${ping}ms',
                      style: TextStyle(
                        color: AppTheme.getPingColor(ping),
                        fontSize: 9,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Map grid painter
class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.backgroundElevated.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    // Draw latitude lines (curves)
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      final path = Path()..moveTo(0, y);
      
      for (double x = 0; x <= size.width; x += 10) {
        final curveY = y + sin(x / size.width * pi) * 5;
        path.lineTo(x, curveY);
      }
      
      canvas.drawPath(path, paint);
    }

    // Draw longitude lines
    for (int i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw some "land mass" shapes
    _drawLandMass(canvas, size, paint);
  }

  void _drawLandMass(Canvas canvas, Size size, Paint paint) {
    final landPaint = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    // Simplified continent shapes
    // Europe/Asia area
    final path1 = Path()
      ..moveTo(size.width * 0.3, size.height * 0.2)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.15, size.width * 0.7, size.height * 0.25)
      ..quadraticBezierTo(size.width * 0.8, size.height * 0.4, size.width * 0.6, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.45, size.width * 0.3, size.height * 0.2);
    
    canvas.drawPath(path1, landPaint);

    // Middle East/Iran area (highlighted)
    final iranPaint = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final iranPath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.2, size.height * 0.45, size.width * 0.25, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.22, size.height * 0.65, size.width * 0.15, size.height * 0.55);
    
    canvas.drawPath(iranPath, iranPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Connection line painter
class ConnectionPainter extends CustomPainter {
  final bool isConnected;
  final double pulseValue;
  final double lineProgress;

  ConnectionPainter({
    required this.isConnected,
    required this.pulseValue,
    required this.lineProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Source point (Iran - bottom left)
    final sourcePoint = Offset(size.width * 0.18, size.height * 0.7);
    
    // Destination point (Server - top right)
    final destPoint = Offset(size.width * 0.82, size.height * 0.25);

    // Draw source point
    _drawPulsingPoint(canvas, sourcePoint, AppTheme.accentCyan, pulseValue);

    if (isConnected) {
      // Draw connection line
      _drawConnectionLine(canvas, sourcePoint, destPoint, lineProgress);
      
      // Draw destination point
      _drawPulsingPoint(canvas, destPoint, AppTheme.primaryGreen, pulseValue);
      
      // Draw data flow particles
      _drawDataParticles(canvas, sourcePoint, destPoint, lineProgress);
    }
  }

  void _drawPulsingPoint(Canvas canvas, Offset point, Color color, double pulse) {
    // Outer glow
    canvas.drawCircle(
      point,
      12 * pulse,
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Middle ring
    canvas.drawCircle(
      point,
      8 * pulse,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Center point
    canvas.drawCircle(
      point,
      4,
      Paint()..color = color,
    );
  }

  void _drawConnectionLine(Canvas canvas, Offset start, Offset end, double progress) {
    if (progress <= 0) return;

    final path = Path();
    
    // Create curved path
    final controlPoint1 = Offset(
      start.dx + (end.dx - start.dx) * 0.3,
      start.dy - 50,
    );
    final controlPoint2 = Offset(
      start.dx + (end.dx - start.dx) * 0.7,
      end.dy + 50,
    );

    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      controlPoint1.dx, controlPoint1.dy,
      controlPoint2.dx, controlPoint2.dy,
      end.dx, end.dy,
    );

    // Get path metrics for partial drawing
    final pathMetric = path.computeMetrics().first;
    final extractPath = pathMetric.extractPath(0, pathMetric.length * progress);

    // Draw glow
    canvas.drawPath(
      extractPath,
      Paint()
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.3)
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Draw main line
    canvas.drawPath(
      extractPath,
      Paint()
        ..color = AppTheme.primaryGreen
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Draw dashed effect
    _drawDashedPath(canvas, extractPath, progress);
  }

  void _drawDashedPath(Canvas canvas, Path path, double progress) {
    final dashPaint = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Create dashed effect using path effect
    // This is a simplified version
  }

  void _drawDataParticles(Canvas canvas, Offset start, Offset end, double progress) {
    if (progress < 0.5) return;

    final random = Random(42);
    final particleCount = 5;

    for (int i = 0; i < particleCount; i++) {
      final t = ((progress * 2 - 1 + i * 0.2) % 1);
      
      // Calculate position along curve
      final x = start.dx + (end.dx - start.dx) * t;
      final y = start.dy + (end.dy - start.dy) * t - sin(t * pi) * 30;

      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()..color = AppTheme.primaryGreen.withValues(alpha: 0.8 - t * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(ConnectionPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
           oldDelegate.lineProgress != lineProgress ||
           oldDelegate.isConnected != isConnected;
  }
}

/// Connection Map Widget - wrapper with customization
class ConnectionMapWidget extends StatelessWidget {
  final String serverAddress;
  final bool isConnected;
  final Color? primaryColor;
  
  const ConnectionMapWidget({
    super.key,
    required this.serverAddress,
    required this.isConnected,
    this.primaryColor,
  });
  
  @override
  Widget build(BuildContext context) {
    // Extract country from server address (simplified)
    String? country;
    if (serverAddress.contains('de') || serverAddress.contains('germany')) {
      country = 'Germany';
    } else if (serverAddress.contains('us') || serverAddress.contains('america')) {
      country = 'United States';
    } else if (serverAddress.contains('nl') || serverAddress.contains('netherlands')) {
      country = 'Netherlands';
    } else if (serverAddress.contains('uk') || serverAddress.contains('london')) {
      country = 'United Kingdom';
    } else if (serverAddress.contains('fr') || serverAddress.contains('france')) {
      country = 'France';
    } else if (serverAddress.contains('jp') || serverAddress.contains('japan')) {
      country = 'Japan';
    } else if (serverAddress.contains('sg') || serverAddress.contains('singapore')) {
      country = 'Singapore';
    } else {
      country = 'Unknown';
    }
    
    return ConnectionMap(
      isConnected: isConnected,
      serverCountry: country,
      serverCity: serverAddress,
    );
  }
}
