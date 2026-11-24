import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ssh_config.dart';
import '../services/experience_preferences_service.dart';
import '../services/ssh/ssh_check.dart';
import '../services/ssh/ssh_session.dart';
import '../utils/night_signal.dart';

/// What the person chose after the check.
enum SshCheckChoice { edit, saveAndConnect }

/// Runs the server check and shows each step as it finishes: the route
/// from phone to server turns from a moving amber dash into a green flow
/// once every step has an answer.
class SshCheckSheet extends StatefulWidget {
  final SshConfig config;
  final Color accent;
  final bool offerConnect;

  const SshCheckSheet({
    super.key,
    required this.config,
    required this.accent,
    this.offerConnect = true,
  });

  static Future<SshCheckChoice?> show(
    BuildContext context,
    SshConfig config, {
    required Color accent,
    bool offerConnect = true,
  }) {
    return showModalBottomSheet<SshCheckChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NightSignal.surface,
      barrierColor: const Color(0x99050810),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SshCheckSheet(
        config: config,
        accent: accent,
        offerConnect: offerConnect,
      ),
    );
  }

  @override
  State<SshCheckSheet> createState() => _SshCheckSheetState();
}

enum _RowState { pending, running, passed, warning, failed, skipped }

class _SshCheckSheetState extends State<SshCheckSheet>
    with SingleTickerProviderStateMixin {
  late final List<SshCheckStep> _steps = SshCheck.stepsFor(widget.config);
  final Map<SshCheckStep, SshCheckResult> _results = {};
  SshCheckReport? _report;
  late final AnimationController _flow;
  final bool _reduceMotion = ExperiencePreferencesService().reduceMotion;

  bool get _done => _report != null;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!_reduceMotion) _flow.repeat();
    _run();
  }

  Future<void> _run() async {
    final report = await SshCheck.run(
      widget.config,
      onResult: (result) {
        if (mounted) setState(() => _results[result.step] = result);
      },
    );
    if (!mounted) return;
    setState(() => _report = report);
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  _RowState _stateOf(SshCheckStep step) {
    final result = _results[step];
    if (result == null) {
      final firstOpen = _steps.firstWhere(
        (s) => !_results.containsKey(s),
        orElse: () => step,
      );
      return !_done && firstOpen == step
          ? _RowState.running
          : _RowState.pending;
    }
    return switch (result.outcome) {
      SshCheckOutcome.passed => _RowState.passed,
      SshCheckOutcome.warning => _RowState.warning,
      SshCheckOutcome.failed => _RowState.failed,
      SshCheckOutcome.skipped => _RowState.skipped,
    };
  }

  String _label(SshCheckStep step) => switch (step) {
    SshCheckStep.reach => 'Server reachable',
    SshCheckStep.tls => 'TLS handshake',
    SshCheckStep.upgrade => 'Payload / WebSocket accepted',
    SshCheckStep.signIn => 'Signed in',
    SshCheckStep.udpgw => 'UDP gateway',
    SshCheckStep.dns => 'DNS through the tunnel',
  };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final canConnect = report?.canConnect ?? false;
    final failed = _done && !canConnect;
    final headline = !_done
        ? 'Checking server…'
        : canConnect
        ? 'Ready to connect'
        : 'Cannot connect yet';
    final failure = _results.values
        .where((r) => r.outcome == SshCheckOutcome.failed)
        .firstOrNull;
    final warning = _results.values
        .where((r) => r.outcome == SshCheckOutcome.warning)
        .firstOrNull;
    final summary = !_done
        ? 'Testing each step your connection will use.'
        : failure != null
        ? failure.detail
        : warning?.step == SshCheckStep.udpgw
        ? 'Calls may not work on this server: its UDP gateway did not answer.'
        : 'Every step answered.';

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NightSignal.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: AnimatedBuilder(
                animation: _flow,
                builder: (context, _) => CustomPaint(
                  painter: _RoutePainter(
                    phase: _flow.value,
                    state: !_done
                        ? _RouteState.checking
                        : failed
                        ? _RouteState.failed
                        : _RouteState.open,
                    accent: widget.accent,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _Node(icon: Icons.smartphone_rounded),
                      _Node(
                        icon: Icons.terminal_rounded,
                        border: !_done
                            ? NightSignal.warning
                            : failed
                            ? NightSignal.danger
                            : widget.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CHECK SERVER · ${widget.config.remarks.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NightSignal.eyebrow(),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                headline,
                key: ValueKey(headline),
                style: NightSignal.title(size: 22),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                summary,
                key: ValueKey(summary),
                style: TextStyle(
                  color: failure != null
                      ? NightSignal.danger
                      : NightSignal.soft,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: NightSignal.scene,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: NightSignal.line),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    _StepRow(
                      label: _label(_steps[i]),
                      detail: _results[_steps[i]]?.detail ?? '',
                      milliseconds: _results[_steps[i]]?.milliseconds,
                      state: _stateOf(_steps[i]),
                      accent: widget.accent,
                      last: i == _steps.length - 1,
                      reduceMotion: _reduceMotion,
                    ),
                ],
              ),
            ),
            if (report?.banner != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: NightSignal.card(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SERVER MESSAGE', style: NightSignal.eyebrow()),
                    const SizedBox(height: 6),
                    Text(
                      report!.banner!,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NightSignal.text,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: _done ? 1 : 0.35,
              duration: const Duration(milliseconds: 400),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _done
                          ? () => Navigator.pop(context, SshCheckChoice.edit)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NightSignal.text,
                        side: const BorderSide(color: NightSignal.lineStrong),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        widget.offerConnect ? 'Edit settings' : 'Close',
                      ),
                    ),
                  ),
                  if (widget.offerConnect) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GlowButton(
                        enabled: _done && canConnect,
                        accent: widget.accent,
                        glow: !_reduceMotion,
                        label: 'Save & connect',
                        onPressed: () => Navigator.pop(
                          context,
                          SshCheckChoice.saveAndConnect,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final IconData icon;
  final Color border;
  const _Node({required this.icon, this.border = NightSignal.lineStrong});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: NightSignal.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: 18, color: NightSignal.text),
    );
  }
}

enum _RouteState { checking, open, failed }

class _RoutePainter extends CustomPainter {
  final double phase;
  final _RouteState state;
  final Color accent;

  _RoutePainter({
    required this.phase,
    required this.state,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 52.0;
    final y = size.height / 2;
    final start = inset;
    final end = size.width - inset;
    final length = end - start;
    if (length <= 0) return;

    if (state == _RouteState.open) {
      canvas.drawLine(
        Offset(start, y),
        Offset(end, y),
        Paint()
          ..color = accent.withValues(alpha: 0.55)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < 3; i++) {
        final t = (phase + i / 3) % 1.0;
        final x = end - t * length;
        final fade = math.min(1.0, math.min(t, 1 - t) * 8);
        canvas.drawCircle(
          Offset(x, y),
          9,
          Paint()..color = accent.withValues(alpha: 0.18 * fade),
        );
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()..color = accent.withValues(alpha: fade),
        );
      }
      return;
    }

    final color = state == _RouteState.failed
        ? NightSignal.danger
        : NightSignal.warning;
    final dash = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final offset = state == _RouteState.checking ? phase * 14 : 0.0;
    for (double x = start - 14 + offset; x < end; x += 14) {
      final a = x.clamp(start, end);
      final b = (x + 6).clamp(start, end);
      if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.phase != phase || old.state != state || old.accent != accent;
}

class _StepRow extends StatelessWidget {
  final String label;
  final String detail;
  final int? milliseconds;
  final _RowState state;
  final Color accent;
  final bool last;
  final bool reduceMotion;

  const _StepRow({
    required this.label,
    required this.detail,
    required this.milliseconds,
    required this.state,
    required this.accent,
    required this.last,
    required this.reduceMotion,
  });

  Color get _color => switch (state) {
    _RowState.passed => accent,
    _RowState.warning => NightSignal.warning,
    _RowState.failed => NightSignal.danger,
    _ => NightSignal.faint,
  };

  @override
  Widget build(BuildContext context) {
    final active = state != _RowState.pending && state != _RowState.skipped;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 350);
    final value = milliseconds != null ? '$milliseconds ms' : null;
    return AnimatedOpacity(
      opacity: active ? 1 : 0.4,
      duration: duration,
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: NightSignal.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                ),
                child: _icon(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state == _RowState.failed && label == 'Signed in'
                        ? 'Sign-in'
                        : label,
                    style: const TextStyle(
                      color: NightSignal.text,
                      fontSize: 14,
                    ),
                  ),
                  if (detail.isNotEmpty &&
                      state != _RowState.failed &&
                      value == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: state == _RowState.warning
                              ? NightSignal.warning
                              : NightSignal.muted,
                          fontSize: 11,
                          fontFamily: state == _RowState.warning
                              ? null
                              : NightSignal.mono,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Text(value, style: NightSignal.number(size: 12, color: _color)),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    switch (state) {
      case _RowState.running:
        return const SizedBox(
          key: ValueKey('running'),
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: NightSignal.warning,
          ),
        );
      case _RowState.passed:
        return Icon(
          Icons.check_circle_outline_rounded,
          key: const ValueKey('passed'),
          size: 22,
          color: accent,
        );
      case _RowState.warning:
        return const Icon(
          Icons.warning_amber_rounded,
          key: ValueKey('warning'),
          size: 22,
          color: NightSignal.warning,
        );
      case _RowState.failed:
        return const Icon(
          Icons.cancel_outlined,
          key: ValueKey('failed'),
          size: 22,
          color: NightSignal.danger,
        );
      case _RowState.pending:
      case _RowState.skipped:
        return const Icon(
          Icons.circle_outlined,
          key: ValueKey('pending'),
          size: 22,
          color: NightSignal.faint,
        );
    }
  }
}

/// The primary button; once enabled it sends out two soft rings.
class _GlowButton extends StatefulWidget {
  final bool enabled;
  final bool glow;
  final Color accent;
  final String label;
  final VoidCallback onPressed;

  const _GlowButton({
    required this.enabled,
    required this.glow,
    required this.accent,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didUpdateWidget(covariant _GlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled && widget.glow) {
      _pulse.forward(from: 0).then((_) {
        if (mounted) _pulse.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              if (_pulse.isAnimating)
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.5 * (1 - t)),
                  spreadRadius: 14 * t,
                ),
            ],
          ),
          child: child,
        );
      },
      child: FilledButton(
        onPressed: widget.enabled ? widget.onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: widget.accent,
          foregroundColor: NightSignal.background,
          disabledBackgroundColor: NightSignal.raised,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
