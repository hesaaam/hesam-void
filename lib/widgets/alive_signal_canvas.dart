import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/vpn_service.dart';

/// The primary connection surface for 4SUPER.
///
/// It visualizes actual [VpnStatus] values from the engine. It does not create
/// timer-driven mock connection states or fabricated network measurements.
class AliveSignalCanvas extends StatelessWidget {
  final VpnStatus status;
  final VpnConfig? config;
  final VpnStats stats;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback onPrimaryAction;
  final VoidCallback onChooseRoute;
  final VoidCallback onOpenStory;
  final bool reduceMotion;
  final bool disableMotion;

  const AliveSignalCanvas({
    super.key,
    required this.status,
    required this.config,
    required this.stats,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onPrimaryAction,
    required this.onChooseRoute,
    required this.onOpenStory,
    this.reduceMotion = false,
    this.disableMotion = false,
  });

  bool get _isBusy =>
      status == VpnStatus.connecting || status == VpnStatus.disconnecting;

  Color get _statusColor {
    switch (status) {
      case VpnStatus.connected:
        return const Color(0xFF20E870);
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return const Color(0xFFFFB020);
      case VpnStatus.error:
        return const Color(0xFFFF5C6C);
      case VpnStatus.disconnected:
        return accentColor;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case VpnStatus.connected:
        return Icons.shield_rounded;
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return Icons.radar_rounded;
      case VpnStatus.error:
        return Icons.route_rounded;
      case VpnStatus.disconnected:
        return Icons.power_settings_new_rounded;
    }
  }

  String get _eyebrow {
    switch (status) {
      case VpnStatus.connected:
        return 'PROTECTION ACTIVE';
      case VpnStatus.connecting:
        return 'PREPARING SECURE ROUTE';
      case VpnStatus.disconnecting:
        return 'CLOSING SECURE ROUTE';
      case VpnStatus.error:
        return 'PATH NEEDS ATTENTION';
      case VpnStatus.disconnected:
        return 'ALIVE SIGNAL';
    }
  }

  String get _headline {
    switch (status) {
      case VpnStatus.connected:
        return config == null ? 'Protected' : 'Protected on ${config!.name}';
      case VpnStatus.connecting:
        return 'Securing your route';
      case VpnStatus.disconnecting:
        return 'Disconnecting safely';
      case VpnStatus.error:
        return 'Connection needs another try';
      case VpnStatus.disconnected:
        return config == null ? 'Ready when you are' : 'Your route is ready';
    }
  }

  String get _supportingText {
    switch (status) {
      case VpnStatus.connected:
        return '${stats.downloadSpeedStr} down  •  ${stats.uploadSpeedStr} up';
      case VpnStatus.connecting:
        return 'Negotiating the selected profile';
      case VpnStatus.disconnecting:
        return 'Returning traffic to your normal route';
      case VpnStatus.error:
        return 'Open Connection Story to see the local reason';
      case VpnStatus.disconnected:
        return config == null
            ? 'Pick a profile, then protect your route'
            : '${config!.protocol.shortName}  •  ${config!.address}';
    }
  }

  String get _primaryLabel {
    switch (status) {
      case VpnStatus.connected:
        return 'DISCONNECT';
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return 'WORKING…';
      case VpnStatus.error:
        return 'TRY AGAIN';
      case VpnStatus.disconnected:
        return config == null ? 'CHOOSE A ROUTE' : 'PROTECT NOW';
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    final canvasHeight = compact ? 292.0 : 330.0;

    return Semantics(
      container: true,
      label: 'Connection state: $_headline. $_supportingText',
      child: Container(
        height: canvasHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _statusColor.withValues(alpha: 0.38)),
          boxShadow: [
            BoxShadow(
              color: _statusColor.withValues(alpha: 0.14),
              blurRadius: 32,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: disableMotion
                      ? 0
                      : (_isBusy || status == VpnStatus.connected ? 1 : 0.35),
                ),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (context, energy, _) {
                  return CustomPaint(
                    painter: _SignalFieldPainter(
                      color: _statusColor,
                      energy: energy,
                      active:
                          !disableMotion &&
                          (_isBusy || status == VpnStatus.connected),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withValues(alpha: 0.78),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _eyebrow,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.64),
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Open Connection Story',
                        onPressed: onOpenStory,
                        icon: Icon(
                          Icons.history_toggle_off_rounded,
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _isBusy ? null : onPrimaryAction,
                    child: Semantics(
                      button: true,
                      label: _primaryLabel,
                      child: AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: compact ? 126 : 148,
                        height: compact ? 126 : 148,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.18),
                          border: Border.all(color: _statusColor, width: 2.4),
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withValues(
                                alpha: _isBusy || status == VpnStatus.connected
                                    ? 0.36
                                    : 0.18,
                              ),
                              blurRadius: _isBusy ? 44 : 28,
                              spreadRadius: _isBusy ? 5 : 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          _statusIcon,
                          size: compact ? 56 : 64,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'JetBrainsMono',
                      fontSize: compact ? 15 : 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _supportingText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.56),
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10.5,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : onPrimaryAction,
                          icon: Icon(
                            status == VpnStatus.connected
                                ? Icons.lock_open_rounded
                                : Icons.shield_rounded,
                            size: 17,
                          ),
                          label: Text(_primaryLabel),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _statusColor,
                            side: BorderSide(
                              color: _statusColor.withValues(alpha: 0.72),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            textStyle: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _isBusy ? null : onChooseRoute,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor.withValues(alpha: 0.8),
                          side: BorderSide(
                            color: textColor.withValues(alpha: 0.18),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
                        child: const Icon(Icons.alt_route_rounded, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalFieldPainter extends CustomPainter {
  final Color color;
  final double energy;
  final bool active;

  const _SignalFieldPainter({
    required this.color,
    required this.energy,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.49);
    final base = math.min(size.width, size.height) * 0.18;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var index = 0; index < 4; index++) {
      final radius = base + (index * 27.0) + (energy * index * 3);
      paint.color = color.withValues(
        alpha: (0.18 - index * 0.032).clamp(0.035, 0.18),
      );
      canvas.drawCircle(center, radius, paint);
    }

    if (active) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.12 + (energy * 0.08))
        ..strokeWidth = 1;
      final path = Path()
        ..moveTo(20, size.height - 54)
        ..quadraticBezierTo(
          size.width * .28,
          size.height - 78,
          center.dx,
          center.dy + base,
        )
        ..quadraticBezierTo(
          size.width * .74,
          size.height - 78,
          size.width - 20,
          size.height - 54,
        );
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalFieldPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.energy != energy ||
        oldDelegate.active != active;
  }
}
