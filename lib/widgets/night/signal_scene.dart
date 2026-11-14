import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/vpn_service.dart';
import '../../utils/night_signal.dart';

/// The live route between this phone and the server.
///
/// While connected, light particles travel along the route: downloads
/// towards the phone, uploads towards the server. Their speed follows the
/// real traffic counters, so a busy tunnel visibly flows faster.
class SignalScene extends StatefulWidget {
  final VpnStatus status;
  final ValueListenable<VpnStats> stats;
  final Color accent;
  final String eyebrow;
  final String headline;
  final String serverLabel;
  final String? latencyLabel;
  final bool animate;

  const SignalScene({
    super.key,
    required this.status,
    required this.stats,
    required this.accent,
    required this.eyebrow,
    required this.headline,
    required this.serverLabel,
    this.latencyLabel,
    this.animate = true,
  });

  @override
  State<SignalScene> createState() => _SignalSceneState();
}

class _SignalSceneState extends State<SignalScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Duration _last = Duration.zero;

  bool get _connected => widget.status == VpnStatus.connected;
  bool get _connecting =>
      widget.status == VpnStatus.connecting ||
      widget.status == VpnStatus.disconnecting;
  bool get _moving => widget.animate && (_connected || _connecting);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (_moving) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant SignalScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!_moving && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  /// Seconds for one particle to cross the route, from download speed.
  double get _cycleSeconds {
    if (_connecting) return 1.1;
    final bytes = widget.stats.value.downloadSpeed.toDouble();
    if (bytes <= 20 * 1024) return 4.2;
    final t = (math.log(bytes / (20 * 1024)) / math.log(400)).clamp(0.0, 1.0);
    return 4.2 - t * 3.1;
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _phase.value = (_phase.value + dt / _cycleSeconds) % 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final serverColor = _connected ? accent : NightSignal.muted;
    return Semantics(
      container: true,
      label: '${widget.headline}. ${widget.eyebrow}',
      child: Container(
        height: 290,
        decoration: BoxDecoration(
          color: NightSignal.scene,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: NightSignal.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final sx = width / 342;
            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScenePainter(
                        phase: _phase,
                        accent: accent,
                        connected: _connected,
                        connecting: _connecting,
                        scaleX: sx,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18 * sx,
                  top: 190,
                  child: const _Node(
                    icon: Icons.smartphone_rounded,
                    label: 'You',
                    border: NightSignal.lineStrong,
                    color: NightSignal.text,
                  ),
                ),
                Positioned(
                  left: 272 * sx,
                  top: 68,
                  child: _Node(
                    icon: Icons.public_rounded,
                    label: widget.serverLabel,
                    border: _connected ? accent : NightSignal.lineStrong,
                    color: serverColor,
                    pulse: _connected && widget.animate,
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 18,
                  right: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.eyebrow.toUpperCase(),
                              style: NightSignal.eyebrow(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: NightSignal.title(size: 23),
                            ),
                          ],
                        ),
                      ),
                      if (widget.latencyLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x0DFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.latencyLabel!,
                            style: NightSignal.number(size: 12, color: accent),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_connected)
                  Positioned(
                    right: 18,
                    bottom: 16,
                    child: ValueListenableBuilder<VpnStats>(
                      valueListenable: widget.stats,
                      builder: (context, stats, _) => Row(
                        children: [
                          Text(
                            '↓ ${stats.downloadSpeedStr}',
                            style: NightSignal.number(
                              size: 12,
                              color: accent,
                              weight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '↑ ${stats.uploadSpeedStr}',
                            style: NightSignal.number(
                              size: 12,
                              color: NightSignal.upload,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color border;
  final Color color;
  final bool pulse;

  const _Node({
    required this.icon,
    required this.label,
    required this.border,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (pulse) Positioned.fill(child: _Pulse(color: border)),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: NightSignal.raised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: NightSignal.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// A soft ring breathing out of the server node while protected.
class _Pulse extends StatefulWidget {
  final Color color;
  const _Pulse({required this.color});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Transform.scale(
          scale: 1 + t * 0.35,
          child: Opacity(
            opacity: (1 - t) * 0.55,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.color, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  final ValueListenable<double> phase;
  final Color accent;
  final bool connected;
  final bool connecting;
  final double scaleX;

  _ScenePainter({
    required this.phase,
    required this.accent,
    required this.connected,
    required this.connecting,
    required this.scaleX,
  }) : super(repaint: phase);

  static const _down = 6;
  static const _up = 3;

  Path _route() {
    return Path()
      ..moveTo(44 * scaleX, 214)
      ..cubicTo(124 * scaleX, 214, 160 * scaleX, 92, 298 * scaleX, 92);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x09FFFFFF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final route = _route();
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0x17FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    final metric = route.computeMetrics().first;
    final length = metric.length;

    if (connecting) {
      final dash = Paint()
        ..color = NightSignal.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final offset = phase.value * 16;
      for (double d = -16 + offset; d < length; d += 16) {
        final start = d.clamp(0.0, length);
        final end = (d + 6).clamp(0.0, length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), dash);
        }
      }
      return;
    }

    if (!connected) return;
    canvas.drawPath(
      route,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    void particle(double t, Color color, double radius) {
      final tangent = metric.getTangentForOffset(t * length);
      if (tangent == null) return;
      final fade = math.min(1.0, math.min(t, 1 - t) * 10);
      canvas.drawCircle(
        tangent.position,
        radius * 2.4,
        Paint()
          ..color = color.withValues(alpha: 0.18 * fade)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        tangent.position,
        radius,
        Paint()..color = color.withValues(alpha: fade),
      );
    }

    // Downloads travel from the server to the phone.
    for (var i = 0; i < _down; i++) {
      particle(1 - ((phase.value + i / _down) % 1.0), accent, 3);
    }
    // Uploads travel the other way, a little slower and smaller.
    for (var i = 0; i < _up; i++) {
      particle(
        ((phase.value * 0.8 + i / _up + 0.17) % 1.0),
        NightSignal.upload,
        2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.accent != accent ||
      old.connected != connected ||
      old.connecting != connecting ||
      old.scaleX != scaleX;
}
