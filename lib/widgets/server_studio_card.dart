import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/connection_health_service.dart';
import '../utils/app_theme.dart';

class ServerStudioCard extends StatelessWidget {
  final VpnConfig config;
  final ConnectionHealthSnapshot snapshot;
  final bool isSelected;
  final bool isFavorite;
  final bool isTesting;
  final bool compact;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback onSelect;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTest;
  final VoidCallback onShowQr;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const ServerStudioCard({
    super.key,
    required this.config,
    required this.snapshot,
    required this.isSelected,
    required this.isFavorite,
    required this.isTesting,
    required this.compact,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.onTest,
    required this.onShowQr,
    required this.onCopy,
    required this.onDelete,
  });

  Color get _healthColor {
    switch (snapshot.level) {
      case ConnectionHealthLevel.excellent:
        return const Color(0xFF20E870);
      case ConnectionHealthLevel.good:
        return accentColor;
      case ConnectionHealthLevel.caution:
        return const Color(0xFFFFB020);
      case ConnectionHealthLevel.unavailable:
        return const Color(0xFFFF5C6C);
      case ConnectionHealthLevel.unverified:
        return const Color(0xFF8B9BB4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final protocolColor = AppTheme.getProtocolColor(config.protocolString);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${config.name}, ${snapshot.levelLabel}, ${snapshot.scoreLabel}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.all(compact ? 11 : 15),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: .13)
                  : surfaceColor.withValues(alpha: .84),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? accentColor.withValues(alpha: .8)
                    : textColor.withValues(alpha: .12),
                width: isSelected ? 1.3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: .14),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: protocolColor.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        config.protocol.shortName,
                        style: TextStyle(
                          color: protocolColor,
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  config.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontFamily: 'JetBrainsMono',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontFamily: 'JetBrainsMono',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${config.address}:${config.port}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withValues(alpha: .5),
                              fontFamily: 'JetBrainsMono',
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isFavorite
                          ? 'Remove from Favorites'
                          : 'Add to Favorites',
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: isFavorite
                            ? const Color(0xFFFFC857)
                            : textColor.withValues(alpha: .45),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        icon: Icons.auto_graph_rounded,
                        label: snapshot.scoreLabel,
                        color: _healthColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.speed_rounded,
                        label: snapshot.latestLatencyMs == null
                            ? 'UNCHECKED'
                            : '${snapshot.latestLatencyMs}ms',
                        color: snapshot.latestLatencyMs == null
                            ? textColor.withValues(alpha: .52)
                            : _healthColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.history_toggle_off_rounded,
                        label: snapshot.attempts == 0
                            ? 'NEW'
                            : '${(snapshot.successRate * 100).round()}% OK',
                        color: textColor.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 13),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        compact
                            ? snapshot.levelLabel
                            : (snapshot.reasons.firstOrNull ??
                                  'No local health data'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: .46),
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    if (isTesting)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _healthColor,
                        ),
                      )
                    else
                      PopupMenuButton<_StudioAction>(
                        tooltip: 'Profile actions',
                        color: surfaceColor,
                        onSelected: (action) {
                          switch (action) {
                            case _StudioAction.test:
                              onTest();
                            case _StudioAction.qr:
                              onShowQr();
                            case _StudioAction.copy:
                              onCopy();
                            case _StudioAction.delete:
                              onDelete();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: _StudioAction.test,
                            child: Text('Run local check'),
                          ),
                          const PopupMenuItem(
                            value: _StudioAction.qr,
                            child: Text('Show QR'),
                          ),
                          const PopupMenuItem(
                            value: _StudioAction.copy,
                            child: Text('Copy config'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _StudioAction.delete,
                            child: Text('Delete profile'),
                          ),
                        ],
                        child: Icon(
                          Icons.more_horiz_rounded,
                          color: textColor.withValues(alpha: .62),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StudioAction { test, qr, copy, delete }

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
