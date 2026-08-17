import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/vpn_service.dart';
import '../utils/app_theme.dart';

/// Big Animated Connect Button
class ConnectButton extends StatefulWidget {
  final VpnStatus status;
  final VoidCallback onTap;
  final String? serverName;
  final Color? primaryColor;

  const ConnectButton({
    super.key,
    required this.status,
    required this.onTap,
    this.serverName,
    this.primaryColor,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;

  Color get _primaryColor => widget.primaryColor ?? AppTheme.primaryGreen;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updateAnimations();
  }

  @override
  void didUpdateWidget(ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    if (widget.status == VpnStatus.connecting) {
      _rotationController.repeat();
      _pulseController.stop();
    } else if (widget.status == VpnStatus.connected) {
      _rotationController.stop();
      _pulseController.repeat(reverse: true);
    } else {
      _rotationController.stop();
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status text
        Text(
              _getStatusText(),
              style: TextStyle(
                color: _getStatusColor(),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrainsMono',
                letterSpacing: 2,
              ),
            )
            .animate(target: widget.status == VpnStatus.connected ? 1 : 0)
            .shimmer(
              duration: 2000.ms,
              color: _getStatusColor().withValues(alpha: 0.5),
            ),

        const SizedBox(height: 8),

        // Server name
        if (widget.serverName != null)
          Text(
            widget.serverName!,
            style: TextStyle(
              color: _primaryColor.withValues(alpha: 0.5),
              fontSize: 12,
              fontFamily: 'JetBrainsMono',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        const SizedBox(height: 24),

        // Main button
        GestureDetector(
          onTap: widget.status == VpnStatus.connecting ? null : widget.onTap,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseAnimation, _rotationController]),
            builder: (context, child) {
              return Transform.scale(
                scale: widget.status == VpnStatus.connected
                    ? _pulseAnimation.value
                    : 1.0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow rings
                    ..._buildGlowRings(),

                    // Rotating ring (when connecting)
                    if (widget.status == VpnStatus.connecting)
                      Transform.rotate(
                        angle: _rotationController.value * 2 * pi,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.transparent,
                              width: 3,
                            ),
                            gradient: SweepGradient(
                              colors: [
                                _primaryColor.withValues(alpha: 0),
                                _primaryColor,
                                _primaryColor.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Main button circle
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.backgroundCard,
                        border: Border.all(
                          color: _getStatusColor().withValues(alpha: 0.5),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _getStatusColor().withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _getIcon(),
                          color: _getStatusColor(),
                          size: 50,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Action text
        Text(
          _getActionText(),
          style: TextStyle(
            color: _primaryColor.withValues(alpha: 0.6),
            fontSize: 12,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGlowRings() {
    if (widget.status != VpnStatus.connected) return [];

    return [
      // Ring 1
      Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _getStatusColor().withValues(alpha: 0.1),
                width: 2,
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.3, 1.3),
            duration: 2000.ms,
          )
          .fadeOut(duration: 2000.ms),

      // Ring 2
      Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _getStatusColor().withValues(alpha: 0.1),
                width: 2,
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.3, 1.3),
            duration: 2000.ms,
            delay: 500.ms,
          )
          .fadeOut(duration: 2000.ms, delay: 500.ms),
    ];
  }

  IconData _getIcon() {
    switch (widget.status) {
      case VpnStatus.connected:
        return Icons.power_settings_new_rounded;
      case VpnStatus.connecting:
        return Icons.sync_rounded;
      case VpnStatus.disconnecting:
        return Icons.sync_disabled_rounded;
      case VpnStatus.error:
        return Icons.error_outline_rounded;
      default:
        return Icons.power_settings_new_rounded;
    }
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case VpnStatus.connected:
        return _primaryColor;
      case VpnStatus.connecting:
        return AppTheme.accentCyan;
      case VpnStatus.disconnecting:
        return AppTheme.accentOrange;
      case VpnStatus.error:
        return AppTheme.accentRed;
      default:
        return _primaryColor.withValues(alpha: 0.5);
    }
  }

  String _getStatusText() {
    switch (widget.status) {
      case VpnStatus.connected:
        return 'CONNECTED';
      case VpnStatus.connecting:
        return 'CONNECTING...';
      case VpnStatus.disconnecting:
        return 'DISCONNECTING...';
      case VpnStatus.error:
        return 'CONNECTION ERROR';
      default:
        return 'DISCONNECTED';
    }
  }

  String _getActionText() {
    switch (widget.status) {
      case VpnStatus.connected:
        return 'Tap to disconnect';
      case VpnStatus.connecting:
        return 'Please wait...';
      case VpnStatus.disconnecting:
        return 'Please wait...';
      default:
        return 'Tap to connect';
    }
  }
}

/// Connection Statistics Widget
class ConnectionStats extends StatelessWidget {
  final VpnStats stats;
  final Color? primaryColor;

  const ConnectionStats({super.key, required this.stats, this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final color = primaryColor ?? AppTheme.primaryGreen;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                stats.duration,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Upload / Download
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Upload',
                  speed: stats.uploadSpeedStr,
                  total: stats.totalUploadStr,
                  color: AppTheme.accentCyan,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: AppTheme.backgroundElevated,
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Download',
                  speed: stats.downloadSpeedStr,
                  total: stats.totalDownloadStr,
                  color: AppTheme.accentPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String speed,
    required String total,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          speed,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          total,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ],
    );
  }
}
