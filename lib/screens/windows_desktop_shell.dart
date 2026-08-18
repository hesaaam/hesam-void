import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/windows_xray_service.dart';

class WindowsDesktopShell extends StatefulWidget {
  const WindowsDesktopShell({super.key});

  @override
  State<WindowsDesktopShell> createState() => _WindowsDesktopShellState();
}

class _WindowsDesktopShellState extends State<WindowsDesktopShell>
    with SingleTickerProviderStateMixin {
  final WindowsXrayService _core = WindowsXrayService.instance;
  late final AnimationController _ambientController;
  int _page = 0;
  String _query = '';
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _core.addListener(_syncAmbientMotion);
    _syncAmbientMotion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().initialize();
    });
  }

  void _syncAmbientMotion() {
    final shouldAnimate =
        _core.state == WindowsConnectionState.starting ||
        _core.state == WindowsConnectionState.connected;
    if (shouldAnimate && !_ambientController.isAnimating) {
      _ambientController.repeat();
    } else if (!shouldAnimate && _ambientController.isAnimating) {
      _ambientController.stop();
    }
  }

  @override
  void dispose() {
    _core.removeListener(_syncAmbientMotion);
    _ambientController.dispose();
    _core.disposeService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B13),
      body: RepaintBoundary(
        child: Stack(
          children: [
            _DesktopAtmosphere(animation: _ambientController),
            SafeArea(
              child: Row(
                children: [
                  _Rail(
                    selected: _page,
                    onSelect: (value) => setState(() => _page = value),
                    onImport: _openImport,
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1050;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 22, 28, 24),
                          child: _page == 0
                              ? _buildDeck(wide)
                              : _buildPlaceholderPage(wide),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeck(bool wide) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final selected =
            provider.selectedConfig ??
            (provider.configs.isNotEmpty ? provider.configs.first : null);
        final shown = provider.searchConfigs(_query);
        return Column(
          children: [
            _TopBar(
              core: _core,
              compact: _compact,
              onCompact: () => setState(() => _compact = !_compact),
              onImport: _openImport,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _connectionDeck(selected, provider),
                        ),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: _studio(provider, shown)),
                      ],
                    )
                  : ListView(
                      children: [
                        _connectionDeck(selected, provider),
                        const SizedBox(height: 20),
                        _studio(provider, shown),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _connectionDeck(VpnConfig? selected, ConfigProvider provider) {
    return AnimatedBuilder(
      animation: _core,
      builder: (context, _) {
        final state = _core.state;
        final isActive = state == WindowsConnectionState.connected;
        final isBusy = state == WindowsConnectionState.starting;
        final accent = _stateColor(state);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('LIVE TUNNEL', 'Windows TUN-first engine'),
              const SizedBox(height: 12),
              _GlassCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _StatusOrb(
                          color: accent,
                          active: isActive || isBusy,
                          size: 108,
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _stateTitle(state),
                                style: const TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _core.message ?? 'Choose a profile to begin',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .62),
                                  height: 1.45,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _SelectedProfileRow(
                      profile: selected,
                      onChange: () => _openProfilePicker(provider),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: const Color(0xFF061018),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: selected == null || isBusy
                            ? null
                            : () => _core.connect(selected),
                        icon: Icon(
                          isActive
                              ? Icons.power_settings_new_rounded
                              : Icons.bolt_rounded,
                        ),
                        label: Text(
                          isActive
                              ? 'DISCONNECT SAFELY'
                              : 'ENGAGE 4SUPER TUNNEL',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    if (state == WindowsConnectionState.failed) ...[
                      const SizedBox(height: 12),
                      _FailureHint(
                        text: _core.message ?? 'Core could not start.',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel(
                'CONNECTION INTELLIGENCE',
                'Quiet when idle · no polling loops',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.route_rounded,
                      label: 'ROUTE MODE',
                      value: 'FULL TUN',
                      color: const Color(0xFF73E6FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.memory_rounded,
                      label: 'IDLE LOAD',
                      value: 'ON-DEMAND',
                      color: const Color(0xFF9CFF80),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ActivityTimeline(core: _core),
            ],
          ),
        );
      },
    );
  }

  Widget _studio(ConfigProvider provider, List<VpnConfig> shown) {
    return _GlassCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 640,
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.dashboard_customize_rounded,
                  color: Color(0xFFB5FF5F),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'SERVER STUDIO',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: Colors.white,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _Pill(text: '${provider.configCount} profiles'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Filter profiles…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: .35),
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .045),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .09),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .09),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: shown.isEmpty
                  ? _EmptyStudio(onImport: _openImport)
                  : ListView.separated(
                      itemCount: shown.length,
                      physics: const BouncingScrollPhysics(),
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 9),
                      itemBuilder: (context, index) => _ProfileCard(
                        profile: shown[index],
                        selected:
                            provider.selectedConfig?.id == shown[index].id,
                        compact: _compact,
                        testing: provider.testingConfigId == shown[index].id,
                        onSelect: () => provider.selectConfig(shown[index]),
                        onPing: () => provider.testPing(shown[index].id),
                        onDelete: () => _confirmDelete(provider, shown[index]),
                        onValidate: () => _validateProfile(shown[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPage(bool wide) {
    final page = switch (_page) {
      1 => 'CONNECTION STORY',
      2 => 'POLICIES',
      _ => 'SETTINGS',
    };
    return Center(
      child: _GlassCard(
        padding: const EdgeInsets.all(42),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _page == 1 ? Icons.timeline_rounded : Icons.tune_rounded,
                color: const Color(0xFFB5FF5F),
                size: 48,
              ),
              const SizedBox(height: 18),
              Text(
                page,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _page == 1
                    ? 'Connection events will appear here after the first active TUN session.'
                    : 'Desktop controls are intentionally compact in Preview. The live connection deck remains the primary workspace.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openImport() {
    final input = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101827),
        title: const Text(
          'QUICK IMPORT',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            color: Colors.white,
            letterSpacing: 1.1,
          ),
        ),
        content: SizedBox(
          width: 580,
          child: TextField(
            controller: input,
            minLines: 7,
            maxLines: 10,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
            ),
            decoration: const InputDecoration(
              hintText:
                  'Paste VLESS, VMess, Trojan, Shadowsocks or SOCKS links…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              final result = await context
                  .read<ConfigProvider>()
                  .importFromClipboard(input.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) _toast(result.message, result.success);
            },
            child: const Text('IMPORT'),
          ),
        ],
      ),
    );
  }

  void _openProfilePicker(ConfigProvider provider) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101827),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: provider.configs
              .map(
                (config) => ListTile(
                  leading: _ProtocolBadge(protocol: config.protocolString),
                  title: Text(
                    config.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    config.address,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .48),
                    ),
                  ),
                  onTap: () {
                    provider.selectConfig(config);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _validateProfile(VpnConfig config) async {
    final result = await _core.validate(config);
    if (mounted) _toast(result.message, result.isValid);
  }

  Future<void> _confirmDelete(ConfigProvider provider, VpnConfig config) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101827),
        title: const Text(
          'Remove profile?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '“${config.name}” is stored locally and will be removed from this device.',
          style: TextStyle(color: Colors.white.withValues(alpha: .68)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (accepted == true) await provider.deleteConfig(config.id);
  }

  void _toast(String text, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success
            ? const Color(0xFF173721)
            : const Color(0xFF492228),
        content: Text(text),
      ),
    );
  }

  Widget _sectionLabel(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Color(0xFFB5FF5F),
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .42),
          fontSize: 12,
        ),
      ),
    ],
  );

  Color _stateColor(WindowsConnectionState state) => switch (state) {
    WindowsConnectionState.connected => const Color(0xFFB5FF5F),
    WindowsConnectionState.starting => const Color(0xFF73E6FF),
    WindowsConnectionState.failed => const Color(0xFFFF7B86),
    WindowsConnectionState.disconnected => const Color(0xFFFFB86B),
  };

  String _stateTitle(WindowsConnectionState state) => switch (state) {
    WindowsConnectionState.connected => 'PROTECTED · FULL TUN ACTIVE',
    WindowsConnectionState.starting => 'BUILDING YOUR PRIVATE ROUTE',
    WindowsConnectionState.failed => 'ROUTE NEEDS ATTENTION',
    WindowsConnectionState.disconnected => 'YOUR NETWORK IS WAITING',
  };
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.onSelect,
    required this.onImport,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    const items = <({IconData icon, String label})>[
      (icon: Icons.space_dashboard_rounded, label: 'COMMAND'),
      (icon: Icons.timeline_rounded, label: 'STORY'),
      (icon: Icons.shield_outlined, label: 'POLICY'),
      (icon: Icons.tune_rounded, label: 'SETTINGS'),
    ];
    return Container(
      width: 218,
      decoration: BoxDecoration(
        color: const Color(0xFF0B111D).withValues(alpha: .88),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: .07)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB5FF5F), Color(0xFF55D9FF)],
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Color(0xFF07101A),
                  ),
                ),
                const SizedBox(width: 11),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HESAM VOID',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '4SUPER · WINDOWS',
                      style: TextStyle(
                        color: Color(0xFFB5FF5F),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: _RailItem(
                icon: items[index].icon,
                label: items[index].label,
                active: selected == index,
                onTap: () => onSelect(index),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('QUICK IMPORT'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB5FF5F),
                  side: const BorderSide(color: Color(0xFF4E7E3D)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(13),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFB5FF5F).withValues(alpha: .13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active
              ? const Color(0xFFB5FF5F).withValues(alpha: .35)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: active
                ? const Color(0xFFB5FF5F)
                : Colors.white.withValues(alpha: .45),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w800,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: .55),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.core,
    required this.compact,
    required this.onCompact,
    required this.onImport,
  });
  final WindowsXrayService core;
  final bool compact;
  final VoidCallback onCompact;
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMMAND DECK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                letterSpacing: .3,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'A calm desktop for decisive connections.',
              style: TextStyle(color: Color(0xFF94A1B9)),
            ),
          ],
        ),
      ),
      _Pill(icon: Icons.verified_user_outlined, text: 'LOCAL-FIRST'),
      const SizedBox(width: 10),
      IconButton(
        tooltip: compact ? 'Relax card density' : 'Compact Server Studio',
        onPressed: onCompact,
        icon: Icon(
          compact
              ? Icons.view_agenda_outlined
              : Icons.view_compact_alt_outlined,
        ),
        color: Colors.white70,
      ),
      const SizedBox(width: 6),
      FilledButton.icon(
        onPressed: onImport,
        icon: const Icon(Icons.add_rounded),
        label: const Text('ADD PROFILE'),
      ),
    ],
  );
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xFF101827).withValues(alpha: .78),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .22),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: child,
  );
}

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({
    required this.color,
    required this.active,
    required this.size,
  });
  final Color color;
  final bool active;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: .13),
      border: Border.all(color: color.withValues(alpha: .65), width: 2),
      boxShadow: active
          ? [
              BoxShadow(
                color: color.withValues(alpha: .35),
                blurRadius: 26,
                spreadRadius: 5,
              ),
            ]
          : [],
    ),
    child: Icon(
      active ? Icons.shield_rounded : Icons.shield_outlined,
      color: color,
      size: size * .42,
    ),
  );
}

class _SelectedProfileRow extends StatelessWidget {
  const _SelectedProfileRow({required this.profile, required this.onChange});
  final VpnConfig? profile;
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .045),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        _ProtocolBadge(protocol: profile?.protocolString ?? '—'),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile?.name ?? 'No profile selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                profile?.address ?? 'Import a link to begin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .46),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('CHANGE')),
      ],
    ),
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.all(15),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .43),
                  fontSize: 9,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.core});
  final WindowsXrayService core;
  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SESSION STORY',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .52),
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 15),
        _storyRow(
          Icons.power_settings_new_rounded,
          'Ready',
          'No background traffic while disconnected',
          const Color(0xFFFFB86B),
        ),
        _storyRow(
          Icons.account_tree_outlined,
          'TUN ownership',
          'One native Core process owns the Windows route',
          const Color(0xFF73E6FF),
        ),
        _storyRow(
          Icons.lock_outline_rounded,
          'Profile privacy',
          'Configuration stays on this device',
          const Color(0xFFB5FF5F),
        ),
      ],
    ),
  );
  Widget _storyRow(IconData icon, String title, String caption, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .47),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.compact,
    required this.testing,
    required this.onSelect,
    required this.onPing,
    required this.onDelete,
    required this.onValidate,
  });
  final VpnConfig profile;
  final bool selected;
  final bool compact;
  final bool testing;
  final VoidCallback onSelect;
  final VoidCallback onPing;
  final VoidCallback onDelete;
  final VoidCallback onValidate;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onSelect,
    borderRadius: BorderRadius.circular(15),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFB5FF5F).withValues(alpha: .10)
            : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: selected
              ? const Color(0xFFB5FF5F).withValues(alpha: .45)
              : Colors.white.withValues(alpha: .07),
        ),
      ),
      child: Row(
        children: [
          _ProtocolBadge(protocol: profile.protocolString),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .43),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (profile.ping != null)
            _Pill(
              text: '${profile.ping}ms',
              tint: profile.ping! < 180
                  ? const Color(0xFFB5FF5F)
                  : const Color(0xFFFFB86B),
            ),
          PopupMenuButton<String>(
            iconColor: Colors.white54,
            color: const Color(0xFF172133),
            onSelected: (value) {
              if (value == 'ping') onPing();
              if (value == 'validate') onValidate();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'ping',
                child: Text(testing ? 'Testing…' : 'Measure latency'),
              ),
              const PopupMenuItem(
                value: 'validate',
                child: Text('Validate Xray JSON'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Remove profile'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _EmptyStudio extends StatelessWidget {
  const _EmptyStudio({required this.onImport});
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome_mosaic_outlined,
          color: Colors.white.withValues(alpha: .28),
          size: 42,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your studio is quiet.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          'Import a profile to create a route.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .44),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 15),
        OutlinedButton(
          onPressed: onImport,
          child: const Text('IMPORT PROFILE'),
        ),
      ],
    ),
  );
}

class _FailureHint extends StatelessWidget {
  const _FailureHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFF7B86).withValues(alpha: .11),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFFFBBC2),
        fontSize: 12,
        height: 1.35,
      ),
    ),
  );
}

class _ProtocolBadge extends StatelessWidget {
  const _ProtocolBadge({required this.protocol});
  final String protocol;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 37),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF73E6FF).withValues(alpha: .13),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      protocol.toUpperCase().substring(0, math.min(protocol.length, 5)),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF73E6FF),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: .6,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({this.icon, required this.text, this.tint});
  final IconData? icon;
  final String text;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final color = tint ?? const Color(0xFFB5FF5F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopAtmosphere extends StatelessWidget {
  const _DesktopAtmosphere({required this.animation});
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) => CustomPaint(
        painter: _AtmospherePainter(animation.value),
        size: Size.infinite,
      ),
    ),
  );
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final sweep = (math.sin(progress * math.pi * 2) + 1) / 2;
    final left = Offset(size.width * (.22 + .16 * sweep), size.height * .05);
    final right = Offset(size.width * (.80 - .12 * sweep), size.height * .72);
    canvas.drawCircle(
      left,
      size.width * .35,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF55D9FF).withValues(alpha: .075),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: left, radius: size.width * .35)),
    );
    canvas.drawCircle(
      right,
      size.width * .30,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFB5FF5F).withValues(alpha: .055),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: right, radius: size.width * .30),
            ),
    );
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
