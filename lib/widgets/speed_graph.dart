import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_theme.dart';
import '../services/vpn_service.dart';

/// Real-time Speed Graph Widget
/// Shows live upload/download speed with animated wave graph
class SpeedGraph extends StatefulWidget {
  final VpnStats stats;
  final bool isConnected;
  final double height;

  const SpeedGraph({
    super.key,
    required this.stats,
    required this.isConnected,
    this.height = 150,
  });

  @override
  State<SpeedGraph> createState() => _SpeedGraphState();
}

class _SpeedGraphState extends State<SpeedGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  // Speed history (last 60 data points)
  final List<double> _downloadHistory = List.filled(60, 0);
  final List<double> _uploadHistory = List.filled(60, 0);

  // Peak speeds
  double _peakDownload = 0;
  double _peakUpload = 0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void didUpdateWidget(SpeedGraph oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Add new data points
    if (widget.isConnected) {
      _downloadHistory.removeAt(0);
      _downloadHistory.add(widget.stats.downloadSpeed.toDouble());

      _uploadHistory.removeAt(0);
      _uploadHistory.add(widget.stats.uploadSpeed.toDouble());

      // Update peaks
      if (widget.stats.downloadSpeed > _peakDownload) {
        _peakDownload = widget.stats.downloadSpeed.toDouble();
      }
      if (widget.stats.uploadSpeed > _peakUpload) {
        _peakUpload = widget.stats.uploadSpeed.toDouble();
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
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
      child: Column(
        children: [
          // Header with current speeds
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSpeedIndicator(
                icon: Icons.arrow_downward_rounded,
                label: 'Download',
                speed: widget.stats.downloadSpeedStr,
                color: AppTheme.accentCyan,
              ),
              _buildPeakIndicator(),
              _buildSpeedIndicator(
                icon: Icons.arrow_upward_rounded,
                label: 'Upload',
                speed: widget.stats.uploadSpeedStr,
                color: AppTheme.accentPurple,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Graph area
          Expanded(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: SpeedGraphPainter(
                    downloadHistory: _downloadHistory,
                    uploadHistory: _uploadHistory,
                    animationValue: _waveController.value,
                    isConnected: widget.isConnected,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate(target: widget.isConnected ? 1 : 0).fadeIn(duration: 400.ms);
  }

  Widget _buildSpeedIndicator({
    required IconData icon,
    required String label,
    required String speed,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            Text(
              speed,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPeakIndicator() {
    return Column(
      children: [
        const Text(
          'PEAK',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontFamily: 'JetBrainsMono',
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward, color: AppTheme.accentCyan, size: 10),
            Text(
              _formatSpeed(_peakDownload.toInt()),
              style: const TextStyle(
                color: AppTheme.accentCyan,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_upward, color: AppTheme.accentPurple, size: 10),
            Text(
              _formatSpeed(_peakUpload.toInt()),
              style: const TextStyle(
                color: AppTheme.accentPurple,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024)
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// Custom painter for speed graph
class SpeedGraphPainter extends CustomPainter {
  final List<double> downloadHistory;
  final List<double> uploadHistory;
  final double animationValue;
  final bool isConnected;

  SpeedGraphPainter({
    required this.downloadHistory,
    required this.uploadHistory,
    required this.animationValue,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isConnected) {
      _drawDisconnectedState(canvas, size);
      return;
    }

    final maxValue = [
      ...downloadHistory,
      ...uploadHistory,
    ].reduce((a, b) => a > b ? a : b);

    final normalizedMax = maxValue > 0 ? maxValue.toDouble() : 1.0;

    // Draw grid lines
    _drawGrid(canvas, size);

    // Draw download line
    _drawSpeedLine(
      canvas,
      size,
      downloadHistory,
      normalizedMax,
      AppTheme.accentCyan,
    );

    // Draw upload line
    _drawSpeedLine(
      canvas,
      size,
      uploadHistory,
      normalizedMax,
      AppTheme.accentPurple,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.backgroundElevated
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines
    for (int i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawSpeedLine(
    Canvas canvas,
    Size size,
    List<double> history,
    double maxValue,
    Color color,
  ) {
    if (history.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final pointWidth = size.width / (history.length - 1);

    // Start points
    final startY = size.height - (history[0] / maxValue * size.height);
    path.moveTo(0, startY);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, startY);

    // Draw curve through all points
    for (int i = 1; i < history.length; i++) {
      final x = i * pointWidth;
      final y = size.height - (history[i] / maxValue * size.height);

      // Use quadratic bezier for smooth curves
      final prevX = (i - 1) * pointWidth;
      final prevY = size.height - (history[i - 1] / maxValue * size.height);
      final midX = (prevX + x) / 2;

      path.quadraticBezierTo(prevX, prevY, midX, (prevY + y) / 2);
      fillPath.quadraticBezierTo(prevX, prevY, midX, (prevY + y) / 2);

      if (i == history.length - 1) {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw fill with gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Draw glow effect
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    // Draw current point indicator
    if (history.isNotEmpty) {
      final lastX = size.width;
      final lastY = size.height - (history.last / maxValue * size.height);

      // Pulsing effect
      final pulseRadius = 4 + sin(animationValue * 2 * pi) * 2;

      canvas.drawCircle(
        Offset(lastX, lastY),
        pulseRadius + 2,
        Paint()..color = color.withValues(alpha: 0.3),
      );
      canvas.drawCircle(
        Offset(lastX, lastY),
        pulseRadius,
        Paint()..color = color,
      );
    }
  }

  void _drawDisconnectedState(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw flat line
    final y = size.height / 2;
    final path = Path()..moveTo(0, y);

    for (double x = 0; x < size.width; x += 10) {
      final waveY = y + sin((x / size.width + animationValue) * 2 * pi) * 5;
      path.lineTo(x, waveY);
    }

    canvas.drawPath(path, paint);

    // Draw "Disconnected" text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'NOT CONNECTED',
        style: TextStyle(
          color: AppTheme.textMuted,
          fontSize: 12,
          fontFamily: 'JetBrainsMono',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(SpeedGraphPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.downloadHistory != downloadHistory ||
        oldDelegate.uploadHistory != uploadHistory;
  }
}

/// Speed Graph Widget with VPN Service integration
class SpeedGraphWidget extends StatefulWidget {
  final VpnService vpnService;
  final Color? primaryColor;
  final Color? backgroundColor;

  const SpeedGraphWidget({
    super.key,
    required this.vpnService,
    this.primaryColor,
    this.backgroundColor,
  });

  @override
  State<SpeedGraphWidget> createState() => _SpeedGraphWidgetState();
}

class _SpeedGraphWidgetState extends State<SpeedGraphWidget> {
  @override
  void initState() {
    super.initState();
    widget.vpnService.addListener(_onVpnChanged);
  }

  void _onVpnChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.vpnService.removeListener(_onVpnChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpeedGraph(
          stats: widget.vpnService.stats,
          isConnected: widget.vpnService.isConnected,
          height: 180,
        ),
        const SizedBox(height: 12),
        // Additional stats row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: (widget.backgroundColor ?? AppTheme.backgroundCard)
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (widget.primaryColor ?? AppTheme.primaryGreen).withValues(
                alpha: 0.2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniStat(
                'Duration',
                widget.vpnService.stats.duration,
                Icons.timer_outlined,
                widget.primaryColor ?? AppTheme.primaryGreen,
              ),
              Container(
                width: 1,
                height: 30,
                color: AppTheme.backgroundElevated,
              ),
              _buildMiniStat(
                'Total ↓',
                widget.vpnService.stats.totalDownloadStr,
                Icons.arrow_downward,
                AppTheme.accentCyan,
              ),
              Container(
                width: 1,
                height: 30,
                color: AppTheme.backgroundElevated,
              ),
              _buildMiniStat(
                'Total ↑',
                widget.vpnService.stats.totalUploadStr,
                Icons.arrow_upward,
                AppTheme.accentPurple,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ],
    );
  }
}

/// Mini speed indicator for compact display
class MiniSpeedIndicator extends StatelessWidget {
  final int downloadSpeed;
  final int uploadSpeed;

  const MiniSpeedIndicator({
    super.key,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_downward, color: AppTheme.accentCyan, size: 12),
        Text(
          _formatSpeed(downloadSpeed),
          style: const TextStyle(
            color: AppTheme.accentCyan,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.arrow_upward, color: AppTheme.accentPurple, size: 12),
        Text(
          _formatSpeed(uploadSpeed),
          style: const TextStyle(
            color: AppTheme.accentPurple,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec}B';
    if (bytesPerSec < 1024 * 1024)
      return '${(bytesPerSec / 1024).toStringAsFixed(0)}K';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}M';
  }
}
