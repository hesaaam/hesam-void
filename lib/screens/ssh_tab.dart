import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ssh_config.dart';
import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/ssh_tunnel_service.dart';
import '../services/vpn_service.dart';
import '../utils/night_signal.dart';

/// The SSH tab: the server in use and every saved SSH server.
///
/// Connecting stays on the Connect tab; here servers are added, checked
/// and chosen.
class SshTab extends StatelessWidget {
  final Color accent;
  final Widget Function(BuildContext, ConfigProvider, VpnConfig) rowBuilder;
  final VoidCallback onAdd;
  final VoidCallback onPasteLink;
  final void Function(List<VpnConfig> routes) onCheckAll;

  const SshTab({
    super.key,
    required this.accent,
    required this.rowBuilder,
    required this.onAdd,
    required this.onPasteLink,
    required this.onCheckAll,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final routes = provider.configs.where((c) => c.isSsh).toList();
        return ListenableBuilder(
          listenable: Listenable.merge([VpnService(), SshTunnelService()]),
          builder: (context, _) {
            final vpn = VpnService();
            final active = vpn.currentConfig;
            final inUse =
                active != null &&
                active.isSsh &&
                (vpn.status == VpnStatus.connected ||
                    vpn.status == VpnStatus.connecting);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: _header(routes.length, inUse ? 1 : 0),
                  ),
                ),
                if (inUse)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _ActiveCard(config: active, accent: accent),
                    ),
                  ),
                if (routes.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(child: _empty()),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ALL SSH SERVERS',
                              style: NightSignal.eyebrow(),
                            ),
                          ),
                          TextButton(
                            onPressed: () => onCheckAll(routes),
                            child: const Text(
                              'Check all',
                              style: TextStyle(color: NightSignal.soft),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: NightSignal.card(),
                        child: Column(
                          children: [
                            for (final route in routes)
                              rowBuilder(context, provider, route),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  sliver: SliverToBoxAdapter(
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: NightSignal.background,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Add SSH server',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(int count, int inUse) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SSH SERVERS', style: NightSignal.eyebrow()),
              const SizedBox(height: 6),
              Text('SSH', style: NightSignal.title(size: 28)),
              const SizedBox(height: 4),
              Text(
                count == 0
                    ? 'No servers yet'
                    : '$count ${count == 1 ? 'server' : 'servers'}'
                          '${inUse > 0 ? ' · 1 in use' : ''}',
                style: const TextStyle(color: NightSignal.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Import SSH link from clipboard',
          child: Material(
            color: NightSignal.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: NightSignal.lineStrong),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPasteLink,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(
                  Icons.content_paste_go_rounded,
                  size: 20,
                  color: NightSignal.text,
                  semanticLabel: 'Import SSH link from clipboard',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: NightSignal.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.terminal_rounded, color: accent, size: 28),
          const SizedBox(height: 12),
          Text('Add your first SSH server', style: NightSignal.title(size: 18)),
          const SizedBox(height: 6),
          const Text(
            'Enter the host, port, user name and password from your provider, '
            'or paste an ssh:// or npvt-ssh:// link.',
            style: TextStyle(
              color: NightSignal.soft,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onPasteLink,
            style: OutlinedButton.styleFrom(
              foregroundColor: NightSignal.text,
              side: const BorderSide(color: NightSignal.lineStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Paste link'),
          ),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final VpnConfig config;
  final Color accent;

  const _ActiveCard({required this.config, required this.accent});

  @override
  Widget build(BuildContext context) {
    final vpn = VpnService();
    final ssh = SshTunnelService();
    final profile = SshConfig.tryParse(config.rawUrl, config.id);
    final reconnecting = ssh.isReconnecting;
    final connecting = vpn.status == VpnStatus.connecting;
    final color = reconnecting || connecting ? NightSignal.warning : accent;
    final label = reconnecting
        ? 'RECONNECTING SSH…'
        : connecting
        ? 'CONNECTING THROUGH SSH…'
        : 'CONNECTED THROUGH SSH';
    final udp = profile?.udpEnabled ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NightSignal.scene,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: NightSignal.eyebrow(color: color)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            config.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NightSignal.title(size: 18),
          ),
          const SizedBox(height: 4),
          Text(
            [
              '${config.address}:${config.port}',
              if (profile != null && profile.configType != SshConfigType.direct)
                profile.configType == SshConfigType.ssl
                    ? 'SNI ${profile.tlsServerName}'
                    : 'WebSocket',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NightSignal.muted,
              fontSize: 12,
              fontFamily: NightSignal.mono,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _cell(
                  'Session',
                  Text(ssh.stats.duration, style: NightSignal.number(size: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cell(
                  'Calls & games',
                  Text(
                    udp ? 'UDP on' : 'TCP only',
                    style: TextStyle(
                      color: udp ? accent : NightSignal.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cell(
                  'DNS',
                  Text(
                    'In tunnel',
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (ssh.banner != null) ...[
            const SizedBox(height: 12),
            Text(
              ssh.banner!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NightSignal.soft,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(String label, Widget value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NightSignal.raised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: NightSignal.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
  }
}
