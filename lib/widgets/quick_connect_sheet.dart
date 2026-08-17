import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/connection_health_service.dart';

class QuickConnectSheet extends StatelessWidget {
  final List<VpnConfig> configs;
  final VpnConfig? selectedConfig;
  final VpnConfig? recommendedConfig;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final ValueChanged<VpnConfig> onSelect;
  final ValueChanged<VpnConfig> onConnect;
  final Future<void> Function() onRunChecks;

  const QuickConnectSheet({
    super.key,
    required this.configs,
    required this.selectedConfig,
    required this.recommendedConfig,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onSelect,
    required this.onConnect,
    required this.onRunChecks,
  });

  static Future<void> show(
    BuildContext context, {
    required List<VpnConfig> configs,
    required VpnConfig? selectedConfig,
    required VpnConfig? recommendedConfig,
    required Color accentColor,
    required Color surfaceColor,
    required Color textColor,
    required ValueChanged<VpnConfig> onSelect,
    required ValueChanged<VpnConfig> onConnect,
    required Future<void> Function() onRunChecks,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QuickConnectSheet(
        configs: configs,
        selectedConfig: selectedConfig,
        recommendedConfig: recommendedConfig,
        accentColor: accentColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
        onSelect: onSelect,
        onConnect: onConnect,
        onRunChecks: onRunChecks,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final health = ConnectionHealthService();
    final candidate = selectedConfig ?? recommendedConfig;
    final maxHeight = MediaQuery.sizeOf(context).height * .82;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: accentColor.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .42),
              blurRadius: 26,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.bolt_rounded, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUICK CONNECT',
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'JetBrainsMono',
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Choose a route with local health context',
                          style: TextStyle(
                            color: textColor.withValues(alpha: .52),
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Run checks for all profiles',
                    onPressed: configs.isEmpty
                        ? null
                        : () async {
                            await onRunChecks();
                          },
                    icon: Icon(Icons.speed_rounded, color: accentColor),
                  ),
                ],
              ),
            ),
            if (candidate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RecommendedRouteCard(
                  config: candidate,
                  isRecommended: candidate.id == recommendedConfig?.id,
                  snapshot: health.snapshotFor(candidate.id),
                  accentColor: accentColor,
                  surfaceColor: surfaceColor,
                  textColor: textColor,
                  onConnect: () {
                    onSelect(candidate);
                    Navigator.pop(context);
                    onConnect(candidate);
                  },
                ),
              )
            else
              _EmptyRouteState(textColor: textColor, accentColor: accentColor),
            const SizedBox(height: 18),
            Flexible(
              child: configs.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      shrinkWrap: true,
                      itemCount: configs.length > 8 ? 8 : configs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final config = configs[index];
                        final snapshot = health.snapshotFor(config.id);
                        final selected = config.id == selectedConfig?.id;
                        return _RouteRow(
                          config: config,
                          snapshot: snapshot,
                          selected: selected,
                          accentColor: accentColor,
                          textColor: textColor,
                          onTap: () {
                            onSelect(config);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedRouteCard extends StatelessWidget {
  final VpnConfig config;
  final bool isRecommended;
  final ConnectionHealthSnapshot snapshot;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback onConnect;

  const _RecommendedRouteCard({
    required this.config,
    required this.isRecommended,
    required this.snapshot,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final healthColor = _healthColor(snapshot.level, accentColor);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            healthColor.withValues(alpha: .2),
            surfaceColor.withValues(alpha: .35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: healthColor.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRecommended
                    ? Icons.auto_awesome_rounded
                    : Icons.route_rounded,
                color: healthColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                isRecommended ? 'BEST NOW' : 'SELECTED ROUTE',
                style: TextStyle(
                  color: healthColor,
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                snapshot.scoreLabel,
                style: TextStyle(
                  color: textColor.withValues(alpha: .7),
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            config.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            snapshot.reasons.firstOrNull ??
                'Run a check to learn about this route',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor.withValues(alpha: .58),
              fontFamily: 'JetBrainsMono',
              fontSize: 10.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.shield_rounded, size: 18),
              label: const Text('PROTECT WITH THIS ROUTE'),
              style: FilledButton.styleFrom(
                backgroundColor: healthColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final VpnConfig config;
  final ConnectionHealthSnapshot snapshot;
  final bool selected;
  final Color accentColor;
  final Color textColor;
  final VoidCallback onTap;

  const _RouteRow({
    required this.config,
    required this.snapshot,
    required this.selected,
    required this.accentColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final healthColor = _healthColor(snapshot.level, accentColor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .11)
                : textColor.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: .72)
                  : textColor.withValues(alpha: .1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  config.protocol.shortName,
                  style: TextStyle(
                    color: healthColor,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      snapshot.latestLatencyMs == null
                          ? 'No local check yet'
                          : '${snapshot.latestLatencyMs} ms  •  ${snapshot.levelLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: .48),
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 18)
              else
                Text(
                  snapshot.score.toString(),
                  style: TextStyle(
                    color: healthColor,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRouteState extends StatelessWidget {
  final Color textColor;
  final Color accentColor;

  const _EmptyRouteState({required this.textColor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        children: [
          Icon(Icons.route_outlined, color: accentColor, size: 42),
          const SizedBox(height: 12),
          Text(
            'No saved routes yet',
            style: TextStyle(color: textColor, fontFamily: 'JetBrainsMono'),
          ),
          const SizedBox(height: 6),
          Text(
            'Import a configuration to use Quick Connect.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor.withValues(alpha: .52),
              fontFamily: 'JetBrainsMono',
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

Color _healthColor(ConnectionHealthLevel level, Color fallback) {
  switch (level) {
    case ConnectionHealthLevel.excellent:
      return const Color(0xFF20E870);
    case ConnectionHealthLevel.good:
      return fallback;
    case ConnectionHealthLevel.caution:
      return const Color(0xFFFFB020);
    case ConnectionHealthLevel.unavailable:
      return const Color(0xFFFF5C6C);
    case ConnectionHealthLevel.unverified:
      return const Color(0xFF8B9BB4);
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
