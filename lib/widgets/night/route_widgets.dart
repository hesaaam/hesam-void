import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/subscription.dart';
import '../../models/vpn_config.dart';
import '../../utils/night_signal.dart';
import '../subscription_folder_card.dart'
    show expiryLabel, formatAgo, formatDataSize;

/// Actions for one route, shown from its row's menu.
class RouteActions {
  final VoidCallback onSelect;
  final VoidCallback onTest;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onShowQr;
  final VoidCallback onDelete;

  const RouteActions({
    required this.onSelect,
    required this.onTest,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onCopy,
    required this.onShowQr,
    required this.onDelete,
  });
}

/// A compact route line: protocol chip, name, signal bars and latency.
class RouteRow extends StatelessWidget {
  final VpnConfig config;
  final bool selected;
  final bool favorite;
  final bool testing;
  final Color accent;
  final RouteActions actions;
  final bool divider;

  const RouteRow({
    super.key,
    required this.config,
    required this.selected,
    required this.favorite,
    required this.testing,
    required this.accent,
    required this.actions,
    this.divider = true,
  });

  static Color protocolColor(VpnProtocol protocol, Color accent) {
    switch (protocol) {
      case VpnProtocol.json:
        return NightSignal.upload;
      case VpnProtocol.vless:
        return accent;
      case VpnProtocol.trojan:
        return NightSignal.violet;
      case VpnProtocol.shadowsocks:
        return NightSignal.warning;
      case VpnProtocol.vmess:
        return NightSignal.orange;
      case VpnProtocol.ssh:
        return NightSignal.soft;
      case VpnProtocol.unknown:
        return NightSignal.muted;
    }
  }

  void _openMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NightSignal.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) {
        Widget item(
          IconData icon,
          String label,
          VoidCallback action, {
          Color? color,
        }) {
          return ListTile(
            leading: Icon(icon, color: color ?? NightSignal.text),
            title: Text(
              label,
              style: TextStyle(color: color ?? NightSignal.text),
            ),
            onTap: () {
              Navigator.pop(sheet);
              action();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NightSignal.title(size: 17),
                  ),
                ),
                item(
                  Icons.check_circle_outline_rounded,
                  'Use this route',
                  actions.onSelect,
                ),
                item(Icons.speed_rounded, 'Check latency', actions.onTest),
                item(
                  favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  favorite ? 'Remove from favorites' : 'Add to favorites',
                  actions.onToggleFavorite,
                ),
                item(Icons.edit_rounded, 'Edit', actions.onEdit),
                item(Icons.copy_rounded, 'Copy link', actions.onCopy),
                item(Icons.qr_code_2_rounded, 'Show QR code', actions.onShowQr),
                item(
                  Icons.delete_outline_rounded,
                  'Delete',
                  actions.onDelete,
                  color: NightSignal.danger,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ping = config.ping;
    final color = NightSignal.forLatency(ping, good: accent);
    final level = ping == null
        ? 0
        : ping < 200
        ? 4
        : ping < 350
        ? 3
        : ping < 600
        ? 2
        : 1;
    final proto = protocolColor(config.protocol, accent);
    return Semantics(
      selected: selected,
      button: true,
      label:
          '${config.name}, ${config.protocol.displayName}, '
          '${ping == null ? 'not measured' : '$ping milliseconds'}',
      child: InkWell(
        onTap: actions.onSelect,
        onLongPress: () => _openMenu(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
          decoration: BoxDecoration(
            border: divider
                ? const Border(top: BorderSide(color: Color(0x0DFFFFFF)))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x0FFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  config.protocol.shortName,
                  style: NightSignal.number(size: 10, color: proto),
                ),
              ),
              const SizedBox(width: 12),
              if (selected) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              if (favorite) ...[
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: NightSignal.warning,
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  config.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: NightSignal.text,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (testing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else
                _SignalBars(level: level, color: color),
              SizedBox(
                width: 62,
                child: Text(
                  ping == null ? '—' : '$ping ms',
                  textAlign: TextAlign.right,
                  style: NightSignal.number(
                    size: 12,
                    color: ping == null ? NightSignal.faint : color,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Route actions',
                onPressed: () => _openMenu(context),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: NightSignal.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int level;
  final Color color;

  const _SignalBars({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 3,
              height: 5.0 + i * 3,
              decoration: BoxDecoration(
                color: i < level ? color : const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            if (i < 3) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

/// A subscription folder: usage ring, expiry badge and its routes inside,
/// opened in place.
class FolderTile extends StatelessWidget {
  final Subscription subscription;
  final int routeCount;
  final int? bestPing;
  final bool open;
  final bool refreshing;
  final bool containsSelection;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onManage;
  final List<Widget> children;

  const FolderTile({
    super.key,
    required this.subscription,
    required this.routeCount,
    required this.bestPing,
    required this.open,
    required this.refreshing,
    required this.containsSelection,
    required this.accent,
    required this.onToggle,
    required this.onManage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final usage = subscription.usageFraction;
    final days = subscription.daysLeft();
    final ringColor = usage != null && usage > 0.8
        ? NightSignal.orange
        : accent;
    final used = subscription.usedBytes;
    final total = subscription.totalBytes;
    final usageText = total != null
        ? '${formatDataSize(used ?? 0)} of ${formatDataSize(total)}'
        : (used != null
              ? '${formatDataSize(used)} used'
              : 'updated ${formatAgo(subscription.updatedAt)}');
    final dayColor = days == null
        ? NightSignal.muted
        : (days <= 3 ? NightSignal.orange : accent);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: NightSignal.card(
        radius: 22,
        border: containsSelection
            ? accent.withValues(alpha: 0.55)
            : (open ? NightSignal.lineStrong : NightSignal.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              onLongPress: onManage,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Row(
                  children: [
                    _UsageRing(
                      fraction: usage,
                      color: ringColor,
                      busy: refreshing,
                      accent: accent,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  subscription.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: NightSignal.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (subscription.lastError != null) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 15,
                                  color: NightSignal.warning,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$routeCount routes · $usageText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NightSignal.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (days != null)
                                _Pill(
                                  label: expiryLabel(days),
                                  color: dayColor,
                                ),
                              if (bestPing != null)
                                _Pill(
                                  label: 'best $bestPing ms',
                                  color: NightSignal.soft,
                                  quiet: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Manage subscription',
                      onPressed: onManage,
                      icon: const Icon(
                        Icons.tune_rounded,
                        size: 19,
                        color: NightSignal.muted,
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: NightSignal.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(children: children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _UsageRing extends StatelessWidget {
  final double? fraction;
  final Color color;
  final bool busy;
  final Color accent;

  const _UsageRing({
    required this.fraction,
    required this.color,
    required this.busy,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction ?? 0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: const Size(52, 52),
              painter: _RingPainter(value: value, color: color),
            ),
          ),
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          else if (fraction != null)
            Text(
              '${(fraction! * 100).round()}%',
              style: NightSignal.number(size: 11),
            )
          else
            Icon(Icons.folder_special_rounded, size: 20, color: accent),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;

  const _RingPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(4);
    canvas.drawArc(
      inner,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0x14FFFFFF),
    );
    if (value <= 0) return;
    canvas.drawArc(
      inner,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool quiet;

  const _Pill({required this.label, required this.color, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: quiet ? const Color(0x0FFFFFFF) : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: quiet ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
  }
}
