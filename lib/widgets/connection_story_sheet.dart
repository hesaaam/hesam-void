import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/connection_health_service.dart';
import '../services/vpn_service.dart';

class ConnectionStorySheet extends StatelessWidget {
  final VpnConfig? config;
  final VpnStatus status;
  final String? currentError;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;

  const ConnectionStorySheet({
    super.key,
    required this.config,
    required this.status,
    required this.currentError,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
  });

  static Future<void> show(
    BuildContext context, {
    required VpnConfig? config,
    required VpnStatus status,
    required String? currentError,
    required Color accentColor,
    required Color surfaceColor,
    required Color textColor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ConnectionStorySheet(
        config: config,
        status: status,
        currentError: currentError,
        accentColor: accentColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final health = ConnectionHealthService();
    final events = config == null
        ? <ConnectionHealthEvent>[]
        : health.eventsFor(config!.id);
    final snapshot = config == null ? null : health.snapshotFor(config!.id);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: accentColor.withValues(alpha: .26)),
        ),
        child: Column(
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
                      color: accentColor.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.timeline_rounded, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CONNECTION STORY',
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'JetBrainsMono',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          config?.name ??
                              'Select a route to see its local history',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor.withValues(alpha: .52),
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: status, accentColor: accentColor),
                ],
              ),
            ),
            if (snapshot != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _LocalHealthSummary(
                  snapshot: snapshot,
                  textColor: textColor,
                  accentColor: accentColor,
                ),
              ),
            if (currentError != null && currentError!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _CurrentErrorCard(
                  error: currentError!,
                  textColor: textColor,
                ),
              ),
            Expanded(
              child: events.isEmpty
                  ? _EmptyStory(textColor: textColor, accentColor: accentColor)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) => _StoryEventRow(
                        event: events[index],
                        isLast: index == events.length - 1,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final VpnStatus status;
  final Color accentColor;

  const _StatusPill({required this.status, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      VpnStatus.connected => ('LIVE', const Color(0xFF20E870)),
      VpnStatus.connecting ||
      VpnStatus.disconnecting => ('WORKING', const Color(0xFFFFB020)),
      VpnStatus.error => ('ATTENTION', const Color(0xFFFF5C6C)),
      VpnStatus.disconnected => ('IDLE', accentColor),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.bold,
          fontSize: 9,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _LocalHealthSummary extends StatelessWidget {
  final ConnectionHealthSnapshot snapshot;
  final Color textColor;
  final Color accentColor;

  const _LocalHealthSummary({
    required this.snapshot,
    required this.textColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: textColor.withValues(alpha: .1)),
      ),
      child: Row(
        children: [
          _Metric(
            label: 'HEALTH',
            value: snapshot.scoreLabel,
            color: accentColor,
            textColor: textColor,
          ),
          _VerticalDivider(color: textColor),
          _Metric(
            label: 'LATEST',
            value: snapshot.latestLatencyMs == null
                ? '—'
                : '${snapshot.latestLatencyMs}ms',
            color: textColor,
            textColor: textColor,
          ),
          _VerticalDivider(color: textColor),
          _Metric(
            label: 'SUCCESS',
            value: snapshot.attempts == 0
                ? '—'
                : '${(snapshot.successRate * 100).round()}%',
            color: const Color(0xFF20E870),
            textColor: textColor,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color textColor;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: .45),
              fontFamily: 'JetBrainsMono',
              fontSize: 8.5,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final Color color;
  const _VerticalDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 29, color: color.withValues(alpha: .12));
}

class _CurrentErrorCard extends StatelessWidget {
  final String error;
  final Color textColor;
  const _CurrentErrorCard({required this.error, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C6C).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF5C6C).withValues(alpha: .36),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFFF5C6C),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor.withValues(alpha: .76),
                fontFamily: 'JetBrainsMono',
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryEventRow extends StatelessWidget {
  final ConnectionHealthEvent event;
  final bool isLast;
  final Color textColor;
  final Color accentColor;

  const _StoryEventRow({
    required this.event,
    required this.isLast,
    required this.textColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final descriptor = _descriptor(event.type, accentColor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 35,
          child: Column(
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: descriptor.color.withValues(alpha: .13),
                  shape: BoxShape.circle,
                ),
                child: Icon(descriptor.icon, color: descriptor.color, size: 15),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 36,
                  color: textColor.withValues(alpha: .11),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        descriptor.title,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'JetBrainsMono',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(event.at),
                      style: TextStyle(
                        color: textColor.withValues(alpha: .4),
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  event.reason ??
                      (event.latencyMs == null
                          ? descriptor.detail
                          : '${event.latencyMs} ms local latency'),
                  style: TextStyle(
                    color: textColor.withValues(alpha: .54),
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

({String title, String detail, IconData icon, Color color}) _descriptor(
  ConnectionEventType type,
  Color accent,
) {
  return switch (type) {
    ConnectionEventType.connected => (
      title: 'Route protected',
      detail: 'Tunnel connected successfully',
      icon: Icons.shield_rounded,
      color: const Color(0xFF20E870),
    ),
    ConnectionEventType.failed => (
      title: 'Connection failed',
      detail: 'The route could not be established',
      icon: Icons.error_outline_rounded,
      color: const Color(0xFFFF5C6C),
    ),
    ConnectionEventType.dropped => (
      title: 'Tunnel dropped',
      detail: 'An unexpected disconnect was recorded',
      icon: Icons.link_off_rounded,
      color: const Color(0xFFFFB020),
    ),
    ConnectionEventType.probeSuccess => (
      title: 'Health check passed',
      detail: 'A local latency test completed',
      icon: Icons.speed_rounded,
      color: accent,
    ),
    ConnectionEventType.probeFailure => (
      title: 'Health check failed',
      detail: 'The latency test did not complete',
      icon: Icons.speed_rounded,
      color: const Color(0xFFFF5C6C),
    ),
  };
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

class _EmptyStory extends StatelessWidget {
  final Color textColor;
  final Color accentColor;
  const _EmptyStory({required this.textColor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_graph_rounded, color: accentColor, size: 46),
            const SizedBox(height: 14),
            Text(
              'Your local connection story starts here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Run a latency check or connect once. This timeline never uploads configuration URLs or credentials.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: .52),
                fontFamily: 'JetBrainsMono',
                fontSize: 10.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
