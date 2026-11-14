import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/smart_connect_service.dart';
import '../utils/night_signal.dart';

/// Full-screen view of a Smart Connect run.
///
/// Every route is a blip on a radar; its distance from the centre is its
/// latency. Unreachable routes sit on the edge in red, measured ones turn
/// the signal colour, and the route that wins is pulled to the centre.
class SmartConnectRadarScreen extends StatelessWidget {
  final String scopeLabel;
  final Color accent;
  final bool animate;

  const SmartConnectRadarScreen({
    super.key,
    required this.scopeLabel,
    required this.accent,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final service = SmartConnectService();
    return Scaffold(
      backgroundColor: NightSignal.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final phase = service.phase;
            final running = service.isRunning;
            final succeeded = phase == SmartConnectPhase.succeeded;
            final blips = service.blips;
            final ranked = blips.where((b) => b.realDelayMs != null).toList()
              ..sort((a, b) => a.realDelayMs!.compareTo(b.realDelayMs!));
            final reachable = blips
                .where((b) => b.state != BlipState.pending)
                .length;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: NightSignal.surface,
                          fixedSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: NightSignal.line),
                          ),
                        ),
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          color: NightSignal.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Connect',
                              style: NightSignal.title(size: 20),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$scopeLabel · ${blips.length} route${blips.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: NightSignal.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      Center(
                        child: RadarView(
                          blips: blips,
                          accent: accent,
                          sweeping: running && animate,
                          label: service.headline,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Step(
                        index: 1,
                        label: 'Check every route',
                        meta: '$reachable/${blips.length}',
                        state: _stepState(phase, 0),
                        accent: accent,
                      ),
                      _Step(
                        index: 2,
                        label: 'Measure real traffic',
                        meta: phase == SmartConnectPhase.measuring
                            ? '${service.progressDone}/${service.progressTotal}'
                            : (ranked.isEmpty ? '' : '${ranked.length}'),
                        state: _stepState(phase, 1),
                        accent: accent,
                      ),
                      _Step(
                        index: 3,
                        label: 'Connect and verify',
                        meta: succeeded
                            ? service.message.split('•').last.trim()
                            : '',
                        state: _stepState(phase, 2),
                        accent: accent,
                      ),
                      if (phase == SmartConnectPhase.failed ||
                          phase == SmartConnectPhase.cancelled) ...[
                        const SizedBox(height: 10),
                        Text(
                          service.message,
                          style: const TextStyle(
                            color: NightSignal.warning,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (ranked.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          decoration: NightSignal.card(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('REAL DELAY', style: NightSignal.eyebrow()),
                              const SizedBox(height: 8),
                              for (final blip in ranked.take(5))
                                _DelayRow(
                                  blip: blip,
                                  accent: accent,
                                  best: identical(blip, ranked.first),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        if (running) {
                          service.cancel();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: succeeded
                            ? accent
                            : NightSignal.raised,
                        foregroundColor: succeeded
                            ? NightSignal.background
                            : NightSignal.text,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      child: Text(
                        running
                            ? 'Cancel'
                            : (succeeded
                                  ? 'Connected · ${service.message.split('•').last.trim()}'
                                  : 'Back'),
                      ),
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

  static _StepState _stepState(SmartConnectPhase phase, int step) {
    final order = switch (phase) {
      SmartConnectPhase.scanning => 0,
      SmartConnectPhase.measuring => 1,
      SmartConnectPhase.connecting || SmartConnectPhase.verifying => 2,
      SmartConnectPhase.succeeded => 3,
      _ => -1,
    };
    if (order == -1) return _StepState.idle;
    if (step < order) return _StepState.done;
    if (step == order) return _StepState.active;
    return _StepState.idle;
  }
}

enum _StepState { idle, active, done }

class _Step extends StatelessWidget {
  final int index;
  final String label;
  final String meta;
  final _StepState state;
  final Color accent;

  const _Step({
    required this.index,
    required this.label,
    required this.meta,
    required this.state,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final active = state == _StepState.active;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? accent
                  : (active
                        ? NightSignal.warning.withValues(alpha: 0.18)
                        : const Color(0x0FFFFFFF)),
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: NightSignal.background,
                  )
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? NightSignal.warning : NightSignal.muted,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: done || active ? NightSignal.text : NightSignal.muted,
              ),
            ),
          ),
          Text(
            meta,
            style: NightSignal.number(size: 12, color: NightSignal.muted),
          ),
        ],
      ),
    );
  }
}

class _DelayRow extends StatelessWidget {
  final RadarBlip blip;
  final Color accent;
  final bool best;

  const _DelayRow({
    required this.blip,
    required this.accent,
    required this.best,
  });

  @override
  Widget build(BuildContext context) {
    final ms = blip.realDelayMs!;
    final color = best ? accent : NightSignal.upload;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              blip.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: best ? NightSignal.text : NightSignal.soft,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (1 - ms / 900).clamp(0.08, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  color: color,
                  backgroundColor: const Color(0x0FFFFFFF),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '$ms ms',
              textAlign: TextAlign.right,
              style: NightSignal.number(
                size: 12,
                color: color,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The radar itself: rings, an optional sweep, and one blip per route.
class RadarView extends StatefulWidget {
  final List<RadarBlip> blips;
  final Color accent;
  final bool sweeping;
  final String label;

  const RadarView({
    super.key,
    required this.blips,
    required this.accent,
    required this.sweeping,
    required this.label,
  });

  static const double size = 300;

  /// Position of a blip: latency sets the distance, the id the angle.
  static Offset positionOf(RadarBlip blip, int index) {
    const center = size / 2;
    if (blip.state == BlipState.winner) return const Offset(center, center);
    final latency = blip.latency;
    final unreachable =
        blip.state == BlipState.unreachable || blip.state == BlipState.failed;
    final distance = unreachable || latency == null
        ? (blip.state == BlipState.pending ? 96.0 : 138.0)
        : 30 + (math.min(latency, 900) / 900) * 104;
    final angle = (index * 137.5) * math.pi / 180;
    return Offset(
      center + math.cos(angle) * distance,
      center + math.sin(angle) * distance,
    );
  }

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.sweeping) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sweeping && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.sweeping && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  Color _colorOf(RadarBlip blip) {
    switch (blip.state) {
      case BlipState.pending:
        return NightSignal.faint;
      case BlipState.reachable:
        return NightSignal.upload;
      case BlipState.unreachable:
      case BlipState.failed:
        return NightSignal.danger;
      case BlipState.measured:
      case BlipState.winner:
        return widget.accent;
      case BlipState.trying:
        return NightSignal.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = RadarView.size;
    final hasWinner = widget.blips.any((b) => b.state == BlipState.winner);
    return Semantics(
      label: widget.label,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: CustomPaint(painter: _RingsPainter())),
            if (widget.sweeping)
              Positioned.fill(
                child: RotationTransition(
                  turns: _sweep,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          NightSignal.upload.withValues(alpha: 0.26),
                          NightSignal.upload.withValues(alpha: 0),
                          NightSignal.upload.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.2, 1],
                      ),
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < widget.blips.length; i++)
              _Blip(
                key: ValueKey(widget.blips[i].id),
                position: RadarView.positionOf(widget.blips[i], i),
                color: _colorOf(widget.blips[i]),
                dimmed: hasWinner && widget.blips[i].state != BlipState.winner,
                winner: widget.blips[i].state == BlipState.winner,
                delay: Duration(milliseconds: (i % 12) * 60),
              ),
            Positioned(
              left: size / 2 - 24,
              top: size / 2 - 24,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  // Opaque, so the winning blip settles underneath it.
                  color: hasWinner
                      ? Color.alphaBlend(
                          widget.accent.withValues(alpha: 0.18),
                          NightSignal.raised,
                        )
                      : NightSignal.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasWinner ? widget.accent : NightSignal.lineStrong,
                    width: hasWinner ? 1.6 : 1,
                  ),
                  boxShadow: hasWinner
                      ? [
                          BoxShadow(
                            color: widget.accent.withValues(alpha: 0.45),
                            blurRadius: 26,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  hasWinner ? Icons.shield_rounded : Icons.smartphone_rounded,
                  size: 20,
                  color: hasWinner ? widget.accent : NightSignal.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blip extends StatelessWidget {
  final Offset position;
  final Color color;
  final bool dimmed;
  final bool winner;
  final Duration delay;

  const _Blip({
    super.key,
    required this.position,
    required this.color,
    required this.dimmed,
    required this.winner,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      left: position.dx - 7,
      top: position.dy - 7,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: dimmed ? 0.35 : 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 550) + delay,
          curve: Curves.easeOutBack,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: winner ? 18 : 14,
            height: winner ? 18 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x14FFFFFF);
    for (final r in [
      size.width / 2,
      size.width / 2 - 52,
      size.width / 2 - 104,
    ]) {
      canvas.drawCircle(center, r, ring);
    }
    final axis = Paint()..color = const Color(0x0DFFFFFF);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axis);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axis);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
