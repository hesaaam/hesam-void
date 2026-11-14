import 'package:flutter/material.dart';

import '../../services/vpn_service.dart';
import '../../utils/night_signal.dart';

/// The round connect / disconnect control under the route scene.
class PowerButton extends StatefulWidget {
  final VpnStatus status;
  final bool busy;
  final Color accent;
  final VoidCallback? onPressed;
  final String semanticLabel;

  const PowerButton({
    super.key,
    required this.status,
    required this.busy,
    required this.accent,
    required this.onPressed,
    required this.semanticLabel,
  });

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.status == VpnStatus.connected;
    final background = connected
        ? widget.accent
        : (widget.busy ? NightSignal.raised : NightSignal.text);
    final icon = widget.busy ? NightSignal.warning : NightSignal.background;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: SizedBox(
            width: 106,
            height: 106,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.busy)
                  RotationTransition(
                    turns: _spin,
                    child: Container(
                      width: 106,
                      height: 106,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: NightSignal.warning.withValues(alpha: 0.15),
                          width: 2,
                        ),
                      ),
                      child: CustomPaint(painter: _ArcPainter()),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: background,
                    boxShadow: [
                      BoxShadow(
                        color: connected
                            ? widget.accent.withValues(alpha: 0.45)
                            : Colors.black.withValues(alpha: 0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    size: 36,
                    color: icon,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Offset.zero & size,
      -1.6,
      1.4,
      false,
      Paint()
        ..color = NightSignal.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// One destination of the bottom navigation.
class NightNavItem {
  final IconData icon;
  final String label;
  const NightNavItem(this.icon, this.label);
}

/// Floating bottom navigation used across the main tabs.
class NightNavBar extends StatelessWidget {
  final List<NightNavItem> items;
  final int index;
  final Color accent;
  final ValueChanged<int> onSelect;

  const NightNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: NightSignal.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NightSignal.lineStrong),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  label: items[i].label,
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    radius: 36,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == index
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: i == index ? accent : NightSignal.muted,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: i == index ? 1.12 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            child: Icon(
                              items[i].icon,
                              size: 21,
                              color: i == index ? accent : NightSignal.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(items[i].label),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded stat cell (Session, Data, Internet).
class StatCell extends StatelessWidget {
  final String label;
  final Widget value;

  const StatCell({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightSignal.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: NightSignal.muted, fontSize: 11),
          ),
          const SizedBox(height: 5),
          value,
        ],
      ),
    );
  }
}
