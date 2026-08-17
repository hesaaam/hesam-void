import 'package:flutter/material.dart';

import '../services/connection_health_service.dart';
import '../utils/app_theme.dart';

class ConnectionHealthCard extends StatelessWidget {
  final String profileName;
  final ConnectionHealthSnapshot snapshot;
  final bool isRecommended;
  final VoidCallback? onChooseRecommended;

  const ConnectionHealthCard({
    super.key,
    required this.profileName,
    required this.snapshot,
    this.isRecommended = false,
    this.onChooseRecommended,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(snapshot.level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${snapshot.score}',
                  style: TextStyle(
                    color: color,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'CONNECTION NAVIGATOR',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snapshot.levelLabel,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'BEST NOW',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            profileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _Metric(icon: Icons.speed_rounded, label: snapshot.latencyLabel),
              const SizedBox(width: 16),
              _Metric(
                icon: Icons.insights_rounded,
                label: '${snapshot.successes}/${snapshot.attempts} checks',
              ),
            ],
          ),
          if (snapshot.reasons.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              snapshot.reasons.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (onChooseRecommended != null) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onChooseRecommended,
                icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('USE RECOMMENDED PROFILE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryGreen,
                  side: const BorderSide(color: AppTheme.primaryGreen),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _colorFor(ConnectionHealthLevel level) {
    switch (level) {
      case ConnectionHealthLevel.excellent:
        return AppTheme.primaryGreen;
      case ConnectionHealthLevel.good:
        return AppTheme.accentCyan;
      case ConnectionHealthLevel.caution:
        return Colors.orangeAccent;
      case ConnectionHealthLevel.unavailable:
        return AppTheme.accentRed;
      case ConnectionHealthLevel.unverified:
        return AppTheme.textMuted;
    }
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Metric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.textMuted, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
