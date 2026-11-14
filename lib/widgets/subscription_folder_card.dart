import 'package:flutter/material.dart';

import '../models/subscription.dart';

/// Human-readable data size, e.g. 38.2 GB.
String formatDataSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Short relative time, e.g. "just now", "5m ago", "3h ago", "2d ago".
String formatAgo(DateTime? time, [DateTime? now]) {
  if (time == null) return 'never';
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Colour for the days-left badge: calm, then warning, then expired.
Color expiryColor(int? daysLeft) {
  if (daysLeft == null) return const Color(0xFF8A94A6);
  if (daysLeft < 0) return const Color(0xFFFF5C6C);
  if (daysLeft <= 3) return const Color(0xFFFFB020);
  return const Color(0xFF20E870);
}

String expiryLabel(int? daysLeft) {
  if (daysLeft == null) return '';
  if (daysLeft < 0) return 'Expired';
  if (daysLeft == 0) return 'Expires today';
  return '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
}

/// A subscription shown as a folder in the Servers tab.
class SubscriptionFolderCard extends StatelessWidget {
  final Subscription subscription;
  final int routeCount;
  final int? bestPing;
  final bool isRefreshing;
  final bool containsSelection;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  const SubscriptionFolderCard({
    super.key,
    required this.subscription,
    required this.routeCount,
    required this.bestPing,
    required this.isRefreshing,
    required this.containsSelection,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final days = subscription.daysLeft();
    final usage = subscription.usageFraction;
    final used = subscription.usedBytes;
    final total = subscription.totalBytes;
    final hasError = subscription.lastError != null;
    final details = <String>[
      '$routeCount route${routeCount == 1 ? '' : 's'}',
      if (bestPing != null) 'best $bestPing ms',
      'updated ${formatAgo(subscription.updatedAt)}',
    ];

    return Semantics(
      button: true,
      label:
          'Subscription ${subscription.name}, $routeCount routes. '
          '${expiryLabel(days)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: containsSelection
                    ? accentColor.withValues(alpha: 0.7)
                    : textColor.withValues(alpha: 0.1),
                width: containsSelection ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.folder_special_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              if (hasError) ...[
                                const SizedBox(width: 6),
                                const Tooltip(
                                  message: 'Last update failed',
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    size: 15,
                                    color: Color(0xFFFFB020),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            details.join('  •  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.58),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRefreshing)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: 'Update subscription',
                        onPressed: onRefresh,
                        icon: Icon(
                          Icons.sync_rounded,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: textColor.withValues(alpha: 0.4),
                    ),
                  ],
                ),
                if (usage != null || days != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        if (usage != null)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: usage,
                                    minHeight: 6,
                                    color: usage > 0.9
                                        ? const Color(0xFFFF5C6C)
                                        : usage > 0.75
                                        ? const Color(0xFFFFB020)
                                        : accentColor,
                                    backgroundColor: textColor.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${formatDataSize(used ?? 0)} of '
                                  '${formatDataSize(total!)} used',
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.6),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (used != null)
                          Expanded(
                            child: Text(
                              '${formatDataSize(used)} used • unlimited',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.6),
                                fontSize: 11.5,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (days != null) ...[
                          const SizedBox(width: 12),
                          _Badge(
                            label: expiryLabel(days),
                            color: expiryColor(days),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
