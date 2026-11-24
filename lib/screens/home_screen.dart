import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/ssh_config.dart';
import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/vpn_service.dart';
import '../services/haptic_service.dart';
import '../services/auto_reconnect_service.dart';
import '../services/connection_health_service.dart';
import '../services/profile_workspace_service.dart';
import '../services/experience_preferences_service.dart';
import '../services/connection_error_explainer.dart';
import '../services/smart_connect_service.dart';
import '../utils/theme_manager.dart';
import '../widgets/config_card.dart';
import '../widgets/qr_dialog.dart';
import '../widgets/quick_connect_sheet.dart';
import '../widgets/connection_story_sheet.dart';
import '../widgets/super_launch_sheet.dart';
import '../widgets/add_subscription_sheet.dart';
import '../widgets/subscription_folder_card.dart' show formatDataSize;
import '../widgets/night/night_controls.dart';
import '../widgets/night/route_widgets.dart';
import '../widgets/night/signal_scene.dart';
import '../utils/night_signal.dart';
import '../services/session_history_service.dart';
import 'config_edit_screen.dart';
import 'ssh_form_screen.dart';
import 'ssh_tab.dart';
import 'insights_tab.dart';
import 'smart_connect_radar_screen.dart';
import '../services/subscription_service.dart';
import 'qr_scanner_screen.dart';
import 'subscription_screen.dart';
import 'settings_screen.dart';

/// Main Home Screen with VPN Connect functionality
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final Set<String> _openFolders = <String>{};
  final VpnService _vpnService = VpnService();
  final HapticService _hapticService = HapticService();
  final AutoReconnectService _autoReconnectService = AutoReconnectService();
  final ThemeManager _themeManager = ThemeManager();
  final ProfileWorkspaceService _profileWorkspace = ProfileWorkspaceService();
  final ExperiencePreferencesService _experiencePreferences =
      ExperiencePreferencesService();
  final SmartConnectService _smartConnect = SmartConnectService();
  VpnStatus? _lastHapticStatus;

  @override
  void initState() {
    super.initState();

    // Initialize providers and services
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final configProvider = context.read<ConfigProvider>();
      await configProvider.initialize();
      await _vpnService.initialize();
      await SessionHistoryService().initialize();
      SessionHistoryService().attach(_vpnService);
      await _hapticService.initialize();
      await _themeManager.initialize();
      await _profileWorkspace.initialize();
      await _profileWorkspace.reconcile(
        configProvider.configs.map((config) => config.id),
      );
      await _experiencePreferences.initialize();
      await _autoReconnectService.initialize(
        _vpnService,
        onFailover: configProvider.selectConfig,
      );
      // Bring subscriptions whose automatic update is due up to date.
      unawaited(configProvider.refreshDueSubscriptions());
      final restored = configProvider.selectedConfig;
      if (restored != null) {
        _autoReconnectService.setServerQueue(
          configProvider.configs,
          activeConfigId: restored.id,
        );
      }
      if (mounted) setState(() {});
      if (!_experiencePreferences.hasSeenSuperTour) {
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (mounted && !_experiencePreferences.hasSeenSuperTour) {
            _showSuperLaunch();
          }
        });
      }
    });

    // Listen to VPN service changes
    _vpnService.addListener(_onVpnStatusChanged);
    _themeManager.addListener(_onThemeChanged);
    _profileWorkspace.addListener(_onThemeChanged);
    _experiencePreferences.addListener(_onThemeChanged);
    _smartConnect.addListener(_onThemeChanged);
  }

  void _onVpnStatusChanged() {
    if (!mounted) return;
    setState(() {});

    // Haptics belong to state transitions only. The engine reports its state
    // every second, so reacting to every notification would vibrate
    // continuously while connected.
    final status = _vpnService.status;
    if (status == _lastHapticStatus) return;
    final previous = _lastHapticStatus;
    _lastHapticStatus = status;
    if (previous == null && status == VpnStatus.disconnected) return;
    // Smart Connect drives its own feedback while it tries several routes.
    if (_smartConnect.isRunning) return;

    switch (status) {
      case VpnStatus.connected:
        _hapticService.onConnectionEstablished();
      case VpnStatus.disconnected:
        _hapticService.onDisconnect();
      case VpnStatus.error:
        _hapticService.onError();
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        break;
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vpnService.removeListener(_onVpnStatusChanged);
    _themeManager.removeListener(_onThemeChanged);
    _profileWorkspace.removeListener(_onThemeChanged);
    _experiencePreferences.removeListener(_onThemeChanged);
    _smartConnect.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themeManager.currentTheme;
    final accent = theme.primaryColor;
    final glow = _vpnService.isConnected
        ? accent.withValues(alpha: 0.16)
        : (_vpnService.isConnecting || _smartConnect.isRunning
              ? NightSignal.warning.withValues(alpha: 0.10)
              : const Color(0x0F8C9AAB));

    return Scaffold(
      backgroundColor: NightSignal.background,
      extendBody: true,
      body: Stack(
        children: [
          Positioned(
            left: -120,
            top: -160,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                width: 520,
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [glow, glow.withValues(alpha: 0)],
                    stops: const [0, 0.65],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _tab,
              children: [
                _buildConnectTab(theme),
                _buildConfigsTab(theme),
                SshTab(
                  accent: accent,
                  rowBuilder: (ctx, provider, config) =>
                      _routeRow(ctx, provider, config, theme, divider: true),
                  onAdd: () => _openSshForm(theme),
                  onPasteLink: () => _pasteSshLink(theme),
                  onCheckAll: (routes) => _runHealthChecks(
                    context.read<ConfigProvider>(),
                    theme,
                    routes,
                  ),
                ),
                InsightsTab(
                  accent: accent,
                  animate: !_experiencePreferences.reduceMotion,
                ),
                const SettingsScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NightNavBar(
        index: _tab,
        accent: accent,
        onSelect: _selectTab,
        items: const [
          NightNavItem(Icons.power_settings_new_rounded, 'Connect'),
          NightNavItem(Icons.folder_open_rounded, 'Routes'),
          NightNavItem(Icons.terminal_rounded, 'SSH'),
          NightNavItem(Icons.bar_chart_rounded, 'Insights'),
          NightNavItem(Icons.settings_rounded, 'Settings'),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    if (_tab == index) return;
    _hapticService.selection();
    setState(() => _tab = index);
  }

  String _statusLabel() {
    if (_smartConnect.isRunning) return 'Smart';
    switch (_vpnService.status) {
      case VpnStatus.connected:
        return 'Protected';
      case VpnStatus.connecting:
        return 'Connecting';
      case VpnStatus.disconnecting:
        return 'Closing';
      case VpnStatus.error:
        return 'Attention';
      case VpnStatus.disconnected:
        return 'Off';
    }
  }

  Color _statusColor(Color accent) {
    if (_smartConnect.isRunning) return NightSignal.warning;
    switch (_vpnService.status) {
      case VpnStatus.connected:
        return accent;
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return NightSignal.warning;
      case VpnStatus.error:
        return NightSignal.danger;
      case VpnStatus.disconnected:
        return NightSignal.muted;
    }
  }

  (String, String) _sceneText(VpnConfig? route) {
    if (_smartConnect.isRunning) {
      return ('Smart Connect', _smartConnect.headline);
    }
    switch (_vpnService.status) {
      case VpnStatus.connected:
        final eyebrow = switch (_vpnService.tunnelCheck) {
          TunnelCheck.verified => 'Internet verified',
          TunnelCheck.failed => 'No internet through the tunnel',
          _ => 'Checking internet',
        };
        return (eyebrow, 'You are protected');
      case VpnStatus.connecting:
        return ('Securing route', 'Finding the path…');
      case VpnStatus.disconnecting:
        return ('Closing route', 'Disconnecting…');
      case VpnStatus.error:
        return ('Needs attention', 'Connection did not complete');
      case VpnStatus.disconnected:
        return ('Ready', route == null ? 'Pick a route' : 'Not connected');
    }
  }

  void _onPower(ConfigProvider provider, AppThemeData theme) {
    _hapticService.onConnect();
    if (_smartConnect.isRunning) {
      _smartConnect.cancel();
      return;
    }
    if (_vpnService.isConnecting) {
      _autoReconnectService.notifyUserDisconnecting();
      _vpnService.disconnect();
      return;
    }
    if (!_vpnService.isConnected && provider.selectedConfig == null) {
      if (provider.hasConfigs) {
        _runSmartConnect(provider, theme);
      } else {
        _showImportDialog(context);
      }
      return;
    }
    _handleConnect(provider);
  }

  Widget _buildConnectTab(AppThemeData theme) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final accent = theme.primaryColor;
        final status = _vpnService.status;
        final route = provider.selectedConfig ?? _vpnService.currentConfig;
        final connected = _vpnService.isConnected;
        final busy =
            _smartConnect.isRunning ||
            status == VpnStatus.connecting ||
            status == VpnStatus.disconnecting;
        final (eyebrow, headline) = _sceneText(route);
        final statusColor = _statusColor(accent);
        final folder = route?.subscriptionId == null
            ? null
            : provider.subscriptionById(route!.subscriptionId!);
        final hint = _smartConnect.isRunning
            ? _smartConnect.message
            : connected
            ? 'Tap to disconnect'
            : status == VpnStatus.connecting
            ? 'Tap to cancel'
            : route == null
            ? (provider.hasConfigs
                  ? 'Tap for Smart Connect'
                  : 'Add a route to start')
            : 'Tap to protect';

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 120),
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NightSignal.surface,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: NightSignal.line),
                  ),
                  child: Icon(Icons.shield_outlined, color: accent, size: 19),
                ),
                const SizedBox(width: 10),
                Text('Hesam Void', style: NightSignal.title(size: 18)),
                const Spacer(),
                IconButton(
                  tooltip: 'Connection Story',
                  onPressed: () {
                    _hapticService.selection();
                    _showConnectionStory(provider, theme);
                  },
                  icon: const Icon(
                    Icons.history_rounded,
                    color: NightSignal.muted,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: NightSignal.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: NightSignal.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _statusLabel(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SignalScene(
              status: _smartConnect.isRunning ? VpnStatus.connecting : status,
              stats: _vpnService.statsListenable,
              accent: accent,
              eyebrow: eyebrow,
              headline: headline,
              serverLabel: route == null ? 'Server' : _shortRouteName(route),
              latencyLabel: connected && _vpnService.tunnelLatencyMs != null
                  ? '${_vpnService.tunnelLatencyMs} ms'
                  : null,
              animate: !_experiencePreferences.disableMotion,
            ),
            const SizedBox(height: 22),
            Center(
              child: PowerButton(
                status: status,
                busy: busy,
                accent: accent,
                semanticLabel: connected
                    ? 'Disconnect'
                    : (busy ? 'Cancel' : 'Connect'),
                onPressed: status == VpnStatus.disconnecting
                    ? null
                    : () => _onPower(provider, theme),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NightSignal.muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: provider.hasConfigs
                    ? () {
                        _hapticService.selection();
                        _showQuickConnect(provider, theme);
                      }
                    : () => _showImportDialog(context),
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  decoration: NightSignal.card(),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              (route == null
                                      ? NightSignal.muted
                                      : RouteRow.protocolColor(
                                          route.protocol,
                                          accent,
                                        ))
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: route == null
                            ? const Icon(
                                Icons.add_rounded,
                                color: NightSignal.muted,
                              )
                            : Text(
                                route.protocol.shortName,
                                style: NightSignal.number(
                                  size: 11,
                                  color: RouteRow.protocolColor(
                                    route.protocol,
                                    accent,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route?.name ??
                                  (provider.hasConfigs
                                      ? 'No route selected'
                                      : 'No routes yet'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: NightSignal.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              route == null
                                  ? (provider.hasConfigs
                                        ? 'Tap to choose'
                                        : 'Paste a link or add a subscription')
                                  : '${folder?.name ?? 'My route'} · ${route.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: NightSignal.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (provider.hasConfigs)
                        TextButton.icon(
                          onPressed: _smartConnect.isRunning
                              ? () => _openRadar('All routes', theme)
                              : () => _runSmartConnect(provider, theme),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                          ),
                          label: const Text('Smart'),
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            backgroundColor: const Color(0x0FFFFFFF),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCell(
                    label: 'Session',
                    value: ValueListenableBuilder<VpnStats>(
                      valueListenable: _vpnService.statsListenable,
                      builder: (context, stats, _) => Text(
                        connected ? stats.duration : '—',
                        style: NightSignal.number(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCell(
                    label: 'Data',
                    value: ValueListenableBuilder<VpnStats>(
                      valueListenable: _vpnService.statsListenable,
                      builder: (context, stats, _) => Text(
                        connected
                            ? formatDataSize(
                                stats.totalDownload + stats.totalUpload,
                              )
                            : '—',
                        maxLines: 1,
                        style: NightSignal.number(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCell(
                    label: 'Internet',
                    value: Text(
                      !connected
                          ? '—'
                          : switch (_vpnService.tunnelCheck) {
                              TunnelCheck.verified => 'Verified',
                              TunnelCheck.failed => 'No access',
                              _ => 'Checking',
                            },
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: !connected
                            ? NightSignal.muted
                            : switch (_vpnService.tunnelCheck) {
                                TunnelCheck.verified => accent,
                                TunnelCheck.failed => NightSignal.warning,
                                _ => NightSignal.soft,
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (connected && _vpnService.tunnelCheck == TunnelCheck.failed) ...[
              const SizedBox(height: 12),
              _buildNoInternetCard(provider, theme),
            ],
            if (_smartConnect.phase == SmartConnectPhase.failed ||
                _smartConnect.phase == SmartConnectPhase.succeeded) ...[
              const SizedBox(height: 12),
              _buildSmartResult(theme),
            ],
            if (_vpnService.errorMessage != null && !_smartConnect.isRunning)
              _buildErrorCard(provider, theme),
            if (_autoReconnectService.isEnabled &&
                !connected &&
                provider.hasConfigs) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.autorenew_rounded,
                    color: accent.withValues(alpha: 0.8),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Auto-reconnect is on',
                    style: TextStyle(color: NightSignal.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  String _shortRouteName(VpnConfig route) {
    final name = route.name.trim();
    if (name.length <= 9) return name;
    return '${name.substring(0, 8)}…';
  }

  void _showSuperLaunch() {
    final theme = _themeManager.currentTheme;
    SuperLaunchSheet.show(
      context,
      accentColor: theme.primaryColor,
      surfaceColor: theme.surfaceColor,
      textColor: theme.textColor,
      onStart: () async {
        await _experiencePreferences.completeSuperTour();
        _hapticService.success();
      },
    );
  }

  void _showQuickConnect(ConfigProvider provider, AppThemeData theme) {
    final health = ConnectionHealthService();
    final recommended = health.recommend(provider.configs);

    QuickConnectSheet.show(
      context,
      configs: provider.configs,
      selectedConfig: provider.selectedConfig,
      recommendedConfig: recommended,
      accentColor: theme.primaryColor,
      surfaceColor: theme.surfaceColor,
      textColor: theme.textColor,
      onSelect: (config) {
        provider.selectConfig(config);
        _autoReconnectService.setServerQueue(
          provider.configs,
          activeConfigId: config.id,
        );
        if (mounted) setState(() {});
      },
      onConnect: (config) {
        provider.selectConfig(config);
        _autoReconnectService.setServerQueue(
          provider.configs,
          activeConfigId: config.id,
        );
        _vpnService.connect(config);
      },
      onRunChecks: () => _runHealthChecks(provider, theme),
      onSmartConnect: () {
        Navigator.of(context).pop();
        _runSmartConnect(provider, theme);
      },
    );
  }

  void _showConnectionStory(ConfigProvider provider, AppThemeData theme) {
    ConnectionStorySheet.show(
      context,
      config: provider.selectedConfig ?? _vpnService.currentConfig,
      status: _vpnService.status,
      currentError: _vpnService.errorMessage,
      accentColor: theme.primaryColor,
      surfaceColor: theme.surfaceColor,
      textColor: theme.textColor,
    );
  }

  Widget _buildConfigsTab(AppThemeData theme) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return _buildLoadingState(theme);
        }

        if (!provider.hasConfigs) {
          return EmptyConfigsWidget(
            onAddConfig: () => _showImportDialog(context),
            primaryColor: theme.primaryColor,
            textColor: NightSignal.text,
          );
        }

        final accent = theme.primaryColor;
        final subscriptions = provider.subscriptions;
        final manual = provider.manualConfigs;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 120),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Routes', style: NightSignal.title()),
                        const SizedBox(height: 3),
                        Text(
                          '${subscriptions.length} folder${subscriptions.length == 1 ? '' : 's'} · '
                          '${provider.configCount} route${provider.configCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: NightSignal.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sort routes',
                    onPressed: () {
                      _hapticService.selection();
                      _showSortOptions(context, theme);
                    },
                    icon: const Icon(
                      Icons.sort_rounded,
                      color: NightSignal.muted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Add routes',
                    onPressed: () => _showImportDialog(context),
                    style: IconButton.styleFrom(
                      backgroundColor: accent,
                      fixedSize: const Size(46, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(
                      Icons.add_rounded,
                      color: NightSignal.background,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutlinedButton.icon(
                onPressed: provider.isTestingPing || _smartConnect.isRunning
                    ? null
                    : () => _runHealthChecks(provider, theme),
                icon: provider.isTestingPing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : const Icon(Icons.speed_rounded, size: 18),
                label: Text(
                  provider.isTestingPing && provider.checkTotal > 0
                      ? 'Checking ${provider.checkCompleted} of ${provider.checkTotal}'
                      : 'Check all routes',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  minimumSize: const Size(double.infinity, 46),
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            if (subscriptions.isNotEmpty) ...[
              _buildSectionLabel('SUBSCRIPTIONS', theme),
              for (final subscription in subscriptions)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: _buildFolder(provider, subscription.id, theme),
                ),
            ],
            if (manual.isNotEmpty) ...[
              _buildSectionLabel('MY ROUTES', theme),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: NightSignal.card(radius: 22),
                child: Column(
                  children: [
                    for (var i = 0; i < manual.length; i++)
                      _routeRow(
                        context,
                        provider,
                        manual[i],
                        theme,
                        divider: i > 0,
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFolder(
    ConfigProvider provider,
    String subscriptionId,
    AppThemeData theme,
  ) {
    final subscription = provider.subscriptionById(subscriptionId)!;
    final routes = provider.configsFor(subscriptionId);
    final pings = routes
        .map((c) => c.ping)
        .whereType<int>()
        .where((p) => p >= 0)
        .toList();
    final open = _openFolders.contains(subscriptionId);
    return FolderTile(
      key: ValueKey(subscriptionId),
      subscription: subscription,
      routeCount: routes.length,
      bestPing: pings.isEmpty ? null : pings.reduce((a, b) => a < b ? a : b),
      open: open,
      refreshing: provider.isRefreshing(subscriptionId),
      containsSelection:
          provider.selectedConfig?.subscriptionId == subscriptionId,
      accent: theme.primaryColor,
      onToggle: () {
        _hapticService.selection();
        setState(() {
          open
              ? _openFolders.remove(subscriptionId)
              : _openFolders.add(subscriptionId);
        });
      },
      onManage: () => _openSubscription(subscriptionId, theme),
      children: [
        for (var i = 0; i < routes.length; i++)
          _routeRow(context, provider, routes[i], theme, divider: true),
      ],
    );
  }

  Widget _buildSectionLabel(String label, AppThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 8),
      child: Text(label, style: NightSignal.eyebrow()),
    );
  }

  void _openSubscription(String id, AppThemeData theme) {
    _hapticService.selection();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionScreen(
          subscriptionId: id,
          theme: theme,
          cardBuilder: (ctx, provider, config) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(color: NightSignal.surface),
            child: _routeRow(ctx, provider, config, theme, divider: true),
          ),
          onRunChecks: (routes) =>
              _runHealthChecks(context.read<ConfigProvider>(), theme, routes),
          onSmartConnect: (routes) {
            _selectTab(0);
            _runSmartConnect(
              context.read<ConfigProvider>(),
              theme,
              configs: routes,
              scope: context.read<ConfigProvider>().subscriptionById(id)?.name,
            );
          },
          onMessage: (message, {bool success = true}) {
            if (mounted) _showResult(message, success, theme);
          },
        ),
      ),
    );
  }

  /// Adds or edits an SSH server; connects when the check asked to.
  Future<void> _openSshForm(
    AppThemeData theme, {
    VpnConfig? existing,
    BuildContext? from,
  }) async {
    _hapticService.selection();
    final result = await SshFormScreen.open(
      from ?? context,
      existing: existing,
      accent: theme.primaryColor,
    );
    if (result == null || !mounted) return;
    _hapticService.success();
    if (result.connect) {
      await _connectTo(result.config);
      return;
    }
    final inUse =
        existing != null &&
        _vpnService.currentConfig?.id == existing.id &&
        (_vpnService.status == VpnStatus.connected ||
            _vpnService.status == VpnStatus.connecting);
    _showSnackBar(
      existing == null
          ? 'SSH server saved'
          : inUse
          ? 'SSH server updated. Reconnect to use the changes.'
          : 'SSH server updated',
      icon: Icons.check_circle,
      theme: theme,
    );
  }

  /// Selects [config] and connects to it from the Connect tab.
  Future<void> _connectTo(VpnConfig config) async {
    final provider = context.read<ConfigProvider>();
    provider.selectConfig(config);
    _autoReconnectService.setServerQueue(
      provider.configs,
      activeConfigId: config.id,
    );
    _selectTab(0);
    if (_vpnService.isConnected || _vpnService.isConnecting) {
      _autoReconnectService.notifyUserDisconnecting();
      await _vpnService.disconnect();
    }
    await _vpnService.connect(config);
  }

  Future<void> _pasteSshLink(AppThemeData theme) async {
    final provider = context.read<ConfigProvider>();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final links = text
        .split(RegExp(r'\s+'))
        .where(SshConfig.isSshLink)
        .join('\n');
    if (links.isEmpty) {
      _showSnackBar(
        'Copy an ssh:// or npvt-ssh:// link first',
        icon: Icons.content_paste_off_rounded,
        color: Colors.orange,
        theme: theme,
      );
      return;
    }
    final result = await provider.importFromClipboard(links);
    if (!mounted) return;
    _showResult(result.message, result.success, theme);
  }

  void _showResult(String message, bool success, AppThemeData theme) {
    _showSnackBar(
      message,
      icon: success ? Icons.check_circle : Icons.error_outline,
      color: success ? theme.primaryColor : Colors.orange,
      theme: theme,
    );
    success ? _hapticService.success() : _hapticService.error();
  }

  /// A route line with all its actions; shared by the Routes tab and the
  /// subscription management screen.
  Widget _routeRow(
    BuildContext rowContext,
    ConfigProvider provider,
    VpnConfig config,
    AppThemeData theme, {
    bool divider = true,
  }) {
    return RouteRow(
      key: ValueKey(config.id),
      config: config,
      selected: provider.selectedConfig?.id == config.id,
      favorite: _profileWorkspace.isFavorite(config.id),
      testing: provider.isConfigTesting(config.id),
      accent: theme.primaryColor,
      divider: divider,
      actions: RouteActions(
        onSelect: () {
          _hapticService.selection();
          provider.selectConfig(config);
          _autoReconnectService.setServerQueue(
            provider.configs,
            activeConfigId: config.id,
          );
          _showSnackBar('${config.name} selected', theme: theme);
        },
        onTest: () {
          _hapticService.light();
          provider.testPing(config.id);
        },
        onToggleFavorite: () async {
          await _profileWorkspace.toggleFavorite(config.id);
          if (!mounted) return;
          _showSnackBar(
            _profileWorkspace.isFavorite(config.id)
                ? 'Added to Favorites'
                : 'Removed from Favorites',
            icon: Icons.star_rounded,
            color: NightSignal.warning,
            theme: theme,
          );
        },
        onEdit: () async {
          _hapticService.selection();
          if (config.isSsh) {
            await _openSshForm(theme, existing: config, from: rowContext);
            return;
          }
          final updated = await ConfigEditScreen.open(
            rowContext,
            config,
            accent: theme.primaryColor,
          );
          if (updated == null || !mounted) return;
          _hapticService.success();
          final inUse =
              _vpnService.currentConfig?.id == updated.id &&
              (_vpnService.status == VpnStatus.connected ||
                  _vpnService.status == VpnStatus.connecting);
          _showSnackBar(
            inUse
                ? 'Route updated. Reconnect to use the changes.'
                : 'Route updated',
            icon: Icons.check_circle,
            theme: theme,
          );
        },
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: config.rawUrl));
          if (!mounted) return;
          _hapticService.success();
          _showSnackBar(
            'Copied to clipboard',
            icon: Icons.check_circle,
            theme: theme,
          );
        },
        onShowQr: () {
          _hapticService.selection();
          // QR codes hold about 2.9 KB; large JSON profiles do not fit.
          if (config.rawUrl.length > 2000) {
            _showSnackBar(
              'This profile is too large for a QR code. Use Copy instead.',
              icon: Icons.qr_code_2_rounded,
              color: Colors.orange,
              theme: theme,
            );
            return;
          }
          QRDisplayDialog.show(rowContext, config);
        },
        onDelete: () async {
          _hapticService.warning();
          final confirm = await DeleteConfirmDialog.show(rowContext, config);
          if (confirm == true) {
            _hapticService.onDelete();
            await provider.deleteConfig(config.id);
            await _profileWorkspace.forget(config.id);
            if (!mounted) return;
            _showSnackBar(
              config.isFromSubscription
                  ? 'Route deleted. It returns on the next update if the '
                        'provider still lists it.'
                  : 'Config deleted',
              icon: Icons.delete_outline,
              theme: theme,
            );
          }
        },
      ),
    );
  }

  Widget _buildLoadingState(AppThemeData theme) {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: 3,
        color: theme.primaryColor,
      ),
    );
  }

  void _handleConnect(ConfigProvider provider) {
    final config =
        provider.selectedConfig ??
        (_vpnService.isConnected ? _vpnService.currentConfig : null);

    if (_vpnService.isConnected) {
      _autoReconnectService.notifyUserDisconnecting();
      _vpnService.disconnect();
      return;
    }

    if (config == null) {
      if (provider.hasConfigs) {
        // Auto-select first config if none selected
        provider.selectConfig(provider.configs.first);
        _autoReconnectService.setServerQueue(
          provider.configs,
          activeConfigId: provider.configs.first.id,
        );
        _vpnService.connect(provider.configs.first);
      } else {
        final theme = _themeManager.currentTheme;
        _showSnackBar(
          'Please add a server first',
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          theme: theme,
        );
        _selectTab(1);
      }
      return;
    }

    _autoReconnectService.setServerQueue(
      provider.configs,
      activeConfigId: config.id,
    );
    _vpnService.connect(config);
  }

  void _showImportDialog(BuildContext context) {
    _hapticService.selection();
    ImportOptionsDialog.show(
      context,
      onClipboardImport: () => _importFromClipboard(context),
      onQRScan: () => _scanQRCode(context),
      onSubscription: _addSubscription,
    );
  }

  Future<void> _addSubscription() async {
    final theme = _themeManager.currentTheme;
    final result = await AddSubscriptionSheet.show(
      context,
      accentColor: theme.primaryColor,
      surfaceColor: theme.surfaceColor,
      textColor: theme.textColor,
    );
    if (result == null || !mounted) return;
    _showResult(result.message, true, theme);
    _selectTab(1);
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final provider = context.read<ConfigProvider>();
    final theme = _themeManager.currentTheme;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) {
        _showSnackBar(
          'Clipboard is empty',
          icon: Icons.warning_amber_rounded,
          theme: theme,
        );
        return;
      }

      // A copied subscription link opens the subscription sheet, which
      // shows download progress and lets the user name the folder.
      if (SubscriptionService.parseUrl(data.text!) != null) {
        await _addSubscription();
        return;
      }

      final result = await provider.importFromClipboard(data.text!);

      _showSnackBar(
        result.message,
        icon: result.success ? Icons.check_circle : Icons.error_outline,
        color: result.success ? theme.primaryColor : Colors.red,
        theme: theme,
      );

      if (result.success) {
        _hapticService.success();
      } else {
        _hapticService.error();
      }
    } catch (e) {
      _hapticService.error();
      _showSnackBar(
        'Failed to import: $e',
        icon: Icons.error_outline,
        theme: theme,
      );
    }
  }

  Future<void> _scanQRCode(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );

    if (result != null && context.mounted) {
      final provider = context.read<ConfigProvider>();
      final theme = _themeManager.currentTheme;
      if (SubscriptionService.parseUrl(result) != null) {
        _showSnackBar(
          'Downloading subscription…',
          icon: Icons.download_rounded,
          theme: theme,
        );
      }
      final importResult = await provider.importFromClipboard(result);

      _showSnackBar(
        importResult.message,
        icon: importResult.success ? Icons.check_circle : Icons.error_outline,
        color: importResult.success ? theme.primaryColor : Colors.red,
        theme: theme,
      );

      if (importResult.success) {
        _hapticService.success();
      } else {
        _hapticService.error();
      }
    }
  }

  void _showSortOptions(BuildContext context, AppThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sort Servers',
              style: TextStyle(
                color: theme.primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 20),
            _buildSortOption(
              icon: Icons.speed_rounded,
              title: 'By Ping (Fastest)',
              theme: theme,
              onTap: () {
                _hapticService.selection();
                context.read<ConfigProvider>().sortByPing();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha_rounded,
              title: 'By Name',
              theme: theme,
              onTap: () {
                _hapticService.selection();
                context.read<ConfigProvider>().sortByName();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.schedule_rounded,
              title: 'By Date Added',
              theme: theme,
              onTap: () {
                _hapticService.selection();
                context.read<ConfigProvider>().sortByDate();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.category_rounded,
              title: 'By Protocol',
              theme: theme,
              onTap: () {
                _hapticService.selection();
                context.read<ConfigProvider>().sortByProtocol();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption({
    required IconData icon,
    required String title,
    required AppThemeData theme,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: theme.primaryColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(color: theme.textColor, fontFamily: 'JetBrainsMono'),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _openRadar(String scope, AppThemeData theme) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => SmartConnectRadarScreen(
          scopeLabel: scope,
          accent: theme.primaryColor,
          animate: !_experiencePreferences.disableMotion,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _runSmartConnect(
    ConfigProvider provider,
    AppThemeData theme, {
    List<VpnConfig>? configs,
    String? scope,
  }) async {
    if (_smartConnect.isRunning) {
      _openRadar(scope ?? 'All routes', theme);
      return;
    }
    _hapticService.selection();
    final run = _smartConnect.run(
      configs: configs ?? provider.configs,
      vpn: _vpnService,
      autoReconnect: _autoReconnectService,
      onSelect: provider.selectConfig,
      onMeasured: provider.applyMeasurements,
    );
    _openRadar(scope ?? 'All routes', theme);
    final connected = await run;
    if (!mounted) return;
    if (connected != null) {
      _hapticService.success();
    } else if (_smartConnect.phase == SmartConnectPhase.failed) {
      // The Smart Connect summary replaces the last per-route error.
      _vpnService.clearError();
      _hapticService.error();
    }
  }

  Future<void> _runHealthChecks(
    ConfigProvider provider,
    AppThemeData theme, [
    List<VpnConfig>? only,
  ]) async {
    _hapticService.selection();
    final results = await provider.testAllPings(only: only);
    if (!mounted || results.isEmpty) return;
    final answered = results.values.where((ping) => ping != null).length;
    _showSnackBar(
      '$answered of ${results.length} routes answered',
      icon: answered == 0 ? Icons.portable_wifi_off_rounded : Icons.speed,
      color: answered == 0 ? Colors.orange : theme.primaryColor,
      theme: theme,
    );
  }

  Widget _buildSmartResult(AppThemeData theme) {
    final succeeded = _smartConnect.phase == SmartConnectPhase.succeeded;
    final color = succeeded ? const Color(0xFF20E870) : Colors.orange;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            succeeded ? Icons.auto_awesome_rounded : Icons.route_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _smartConnect.headline,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _smartConnect.message,
                  style: TextStyle(
                    color: theme.textColor.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: _smartConnect.dismiss,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: theme.textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoInternetCard(ConfigProvider provider, AppThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: NightSignal.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NightSignal.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: NightSignal.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'The tunnel is up, but no internet passes through it.',
              style: TextStyle(color: NightSignal.text, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => _runSmartConnect(provider, theme),
            style: TextButton.styleFrom(foregroundColor: NightSignal.warning),
            child: const Text('Try another'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ConfigProvider provider, AppThemeData theme) {
    final insight = ConnectionErrorExplainer.explain(_vpnService.errorMessage);
    const color = Color(0xFFFF5C6C);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.error_outline, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: const TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      insight.hint,
                      style: TextStyle(
                        color: theme.textColor.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: _vpnService.clearError,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (insight.suggestOtherRoute && provider.configs.length > 1)
                TextButton.icon(
                  onPressed: () => _runSmartConnect(provider, theme),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('FIND A WORKING ROUTE'),
                ),
              TextButton(
                onPressed: () => _showConnectionStory(provider, theme),
                child: const Text('DETAILS'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  void _showSnackBar(
    String message, {
    IconData icon = Icons.info_outline,
    Color? color,
    required AppThemeData theme,
  }) {
    final snackColor = color ?? theme.primaryColor;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: snackColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
            ),
          ],
        ),
        backgroundColor: theme.surfaceColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: snackColor.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
