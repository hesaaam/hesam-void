import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../utils/app_theme.dart';
import '../utils/theme_manager.dart';
import '../widgets/animated_background.dart';
import '../widgets/config_card.dart';
import '../widgets/qr_dialog.dart';
import '../widgets/connect_button.dart';
import '../widgets/speed_graph.dart';
import '../widgets/connection_health_card.dart';
import '../widgets/alive_signal_canvas.dart';
import '../widgets/quick_connect_sheet.dart';
import '../widgets/connection_story_sheet.dart';
import '../widgets/server_studio_card.dart';
import '../widgets/super_launch_sheet.dart';
import '../widgets/add_subscription_sheet.dart';
import '../widgets/subscription_folder_card.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final VpnService _vpnService = VpnService();
  final HapticService _hapticService = HapticService();
  final AutoReconnectService _autoReconnectService = AutoReconnectService();
  final ThemeManager _themeManager = ThemeManager();
  final ProfileWorkspaceService _profileWorkspace = ProfileWorkspaceService();
  final ExperiencePreferencesService _experiencePreferences =
      ExperiencePreferencesService();
  final SmartConnectService _smartConnect = SmartConnectService();
  VpnStatus? _lastHapticStatus;

  // Track if showing advanced stats
  bool _showAdvancedStats = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Initialize providers and services
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final configProvider = context.read<ConfigProvider>();
      await configProvider.initialize();
      await _vpnService.initialize();
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
    _tabController.dispose();
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

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: AnimatedBackground(
        primaryColor: theme.primaryColor,
        animate: !_experiencePreferences.reduceMotion,
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              _buildAppBar(theme),

              // Tab Bar
              _buildTabBar(theme),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildConnectTab(theme), _buildConfigsTab(theme)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(AppThemeData theme) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Logo and title
              Row(
                children: [
                  Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _vpnService.isConnected
                              ? theme.primaryColor.withValues(alpha: 0.2)
                              : theme.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _vpnService.isConnected
                                ? theme.primaryColor
                                : theme.primaryColor.withValues(alpha: 0.3),
                          ),
                          boxShadow: _vpnService.isConnected
                              ? [
                                  BoxShadow(
                                    color: theme.primaryColor.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.shield_rounded,
                          color: _vpnService.isConnected
                              ? theme.primaryColor
                              : theme.primaryColor.withValues(alpha: 0.7),
                          size: 24,
                        ),
                      )
                      .animate(target: _vpnService.isConnected ? 1 : 0)
                      .shimmer(
                        duration: 2000.ms,
                        color: theme.primaryColor.withValues(alpha: 0.5),
                      ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HESAM VOID 4SUPER',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'JetBrainsMono',
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        _vpnService.isConnected
                            ? 'Protected • Alive Signal'
                            : 'Alive Signal • Ready to protect',
                        style: TextStyle(
                          color: _vpnService.isConnected
                              ? theme.primaryColor
                              : theme.textColor.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              // Settings button
              IconButton(
                icon: Icon(Icons.settings, color: theme.primaryColor),
                onPressed: () {
                  _hapticService.selection();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),

              const SizedBox(width: 8),

              // Connection indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _vpnService.isConnected
                      ? theme.primaryColor.withValues(alpha: 0.15)
                      : theme.surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _vpnService.isConnected
                        ? theme.primaryColor
                        : theme.textColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _vpnService.isConnected
                                ? theme.primaryColor
                                : Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_vpnService.isConnected
                                            ? theme.primaryColor
                                            : Colors.red)
                                        .withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        )
                        .animate(
                          onPlay: (c) =>
                              _vpnService.isConnected ? c.repeat() : c.stop(),
                        )
                        .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1.3, 1.3),
                          duration: 1000.ms,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1.3, 1.3),
                          end: const Offset(1, 1),
                          duration: 1000.ms,
                        ),
                    const SizedBox(width: 8),
                    Text(
                      _vpnService.isConnected ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: _vpnService.isConnected
                            ? theme.primaryColor
                            : theme.textColor.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: -0.3, end: 0, duration: 500.ms);
  }

  Widget _buildTabBar(AppThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.primaryColor),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: theme.primaryColor,
        unselectedLabelColor: theme.textColor.withValues(alpha: 0.5),
        labelStyle: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        onTap: (_) => _hapticService.selection(),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.power_settings_new_rounded, size: 18),
                SizedBox(width: 8),
                Text('CONNECT'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.list_alt_rounded, size: 18),
                SizedBox(width: 8),
                Text('SERVERS'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectTab(AppThemeData theme) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final selectedConfig = provider.selectedConfig;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 100,
          ),
          child: Column(
            children: [
              ValueListenableBuilder<VpnStats>(
                valueListenable: _vpnService.statsListenable,
                builder: (context, stats, _) => AliveSignalCanvas(
                  status: _vpnService.status,
                  config: selectedConfig ?? _vpnService.currentConfig,
                  stats: stats,
                  accentColor: theme.primaryColor,
                  surfaceColor: theme.surfaceColor,
                  textColor: theme.textColor,
                  smartActive: _smartConnect.isRunning,
                  smartHeadline: _smartConnect.headline,
                  smartDetail: _smartConnect.message,
                  smartProgress: _smartProgressValue,
                  onSmartConnect: provider.hasConfigs
                      ? () => _runSmartConnect(provider, theme)
                      : null,
                  onCancelSmart: () {
                    _hapticService.selection();
                    _smartConnect.cancel();
                  },
                  onPrimaryAction: () {
                    _hapticService.onConnect();
                    if (!_vpnService.isConnected && selectedConfig == null) {
                      if (provider.hasConfigs) {
                        _runSmartConnect(provider, theme);
                      } else {
                        _showImportDialog(context);
                      }
                      return;
                    }
                    _handleConnect(provider);
                  },
                  onChooseRoute: () {
                    _hapticService.selection();
                    _showQuickConnect(provider, theme);
                  },
                  onOpenStory: () {
                    _hapticService.selection();
                    _showConnectionStory(provider, theme);
                  },
                  reduceMotion: _experiencePreferences.reduceMotion,
                  disableMotion: _experiencePreferences.disableMotion,
                ),
              ),
              const SizedBox(height: 16),
              _buildSuperContextStrip(provider, theme),

              if (_smartConnect.phase == SmartConnectPhase.failed ||
                  _smartConnect.phase == SmartConnectPhase.succeeded) ...[
                const SizedBox(height: 16),
                _buildSmartResult(theme),
              ],

              const SizedBox(height: 20),

              // Proof that traffic really passes the tunnel.
              if (_vpnService.isConnected) ...[
                _buildTunnelCheckBadge(provider, theme),
                const SizedBox(height: 16),
              ],

              // Connection Stats (when connected)
              if (_vpnService.isConnected) ...[
                // Toggle advanced stats
                GestureDetector(
                  onTap: () {
                    _hapticService.selection();
                    setState(() => _showAdvancedStats = !_showAdvancedStats);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showAdvancedStats
                              ? Icons.bar_chart
                              : Icons.show_chart,
                          color: theme.primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _showAdvancedStats ? 'SIMPLE VIEW' : 'DETAILED VIEW',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 11,
                            fontFamily: 'JetBrainsMono',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_showAdvancedStats)
                  // Speed Graph - with better height control
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SpeedGraphWidget(
                      vpnService: _vpnService,
                      primaryColor: theme.primaryColor,
                      backgroundColor: theme.surfaceColor,
                    ),
                  )
                else
                  // Simple stats, rebuilt only by the live stats ticks.
                  ValueListenableBuilder<VpnStats>(
                    valueListenable: _vpnService.statsListenable,
                    builder: (context, stats, _) => ConnectionStats(
                      stats: stats,
                      primaryColor: theme.primaryColor,
                    ),
                  ),
              ],

              // Connection Navigator is local-only and explains the current
              // profile health before the user starts a tunnel.
              if (!_vpnService.isConnected &&
                  !_vpnService.isConnecting &&
                  provider.hasConfigs) ...[
                const SizedBox(height: 20),
                _buildConnectionNavigator(provider, theme),
              ],

              // Server Selection (when disconnected)
              if (!_vpnService.isConnected && !_vpnService.isConnecting) ...[
                const SizedBox(height: 16),
                _buildServerSelector(provider, theme),
              ],

              // Auto-reconnect indicator
              if (_autoReconnectService.isEnabled && !_vpnService.isConnected)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.autorenew,
                        color: theme.primaryColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Auto-reconnect enabled',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 12,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ],
                  ),
                ),

              // Error message, explained in plain language.
              if (_vpnService.errorMessage != null && !_smartConnect.isRunning)
                _buildErrorCard(provider, theme),
            ],
          ),
        );
      },
    );
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

  Widget _buildSuperContextStrip(ConfigProvider provider, AppThemeData theme) {
    final focused = provider.selectedConfig ?? _vpnService.currentConfig;
    final snapshot = focused == null
        ? null
        : ConnectionHealthService().snapshotFor(focused.id);
    final isRecovering =
        _vpnService.status == VpnStatus.connecting ||
        _vpnService.status == VpnStatus.disconnecting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.surfaceColor.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withValues(alpha: .1)),
      ),
      child: Row(
        children: [
          _buildSuperMetric(
            icon: Icons.auto_awesome_rounded,
            label: 'HEALTH',
            value: snapshot?.scoreLabel ?? '—',
            color: snapshot == null
                ? theme.textColor.withValues(alpha: .55)
                : theme.primaryColor,
            theme: theme,
          ),
          _buildSuperDivider(theme),
          _buildSuperMetric(
            icon: Icons.bolt_rounded,
            label: 'ROUTE',
            value: focused?.protocol.shortName ?? 'NONE',
            color: theme.primaryColor,
            theme: theme,
          ),
          _buildSuperDivider(theme),
          _buildSuperMetric(
            icon: Icons.autorenew_rounded,
            label: 'RECOVER',
            value: isRecovering
                ? 'WORKING'
                : _autoReconnectService.isEnabled
                ? 'READY'
                : 'OFF',
            color: isRecovering
                ? const Color(0xFFFFB020)
                : _autoReconnectService.isEnabled
                ? const Color(0xFF20E870)
                : theme.textColor.withValues(alpha: .55),
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildSuperMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required AppThemeData theme,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: .43),
                  fontFamily: 'JetBrainsMono',
                  fontSize: 8,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuperDivider(AppThemeData theme) {
    return Container(
      width: 1,
      height: 31,
      color: theme.textColor.withValues(alpha: .12),
    );
  }

  Widget _buildConnectionNavigator(
    ConfigProvider provider,
    AppThemeData theme,
  ) {
    final health = ConnectionHealthService();
    return AnimatedBuilder(
      animation: health,
      builder: (context, child) {
        final recommended = health.recommend(provider.configs);
        final focused =
            provider.selectedConfig ?? recommended ?? provider.configs.first;
        final snapshot = health.snapshotFor(focused.id);
        final canChooseRecommendation =
            recommended != null &&
            recommended.id != provider.selectedConfig?.id;

        return ConnectionHealthCard(
          profileName: focused.name,
          snapshot: snapshot,
          isRecommended: recommended?.id == focused.id,
          onChooseRecommended: canChooseRecommendation
              ? () {
                  provider.selectConfig(recommended);
                  _autoReconnectService.setServerQueue(
                    provider.configs,
                    activeConfigId: recommended.id,
                  );
                  _showSnackBar(
                    'Recommended profile selected: ${recommended.name}',
                    icon: Icons.auto_awesome_rounded,
                    color: theme.primaryColor,
                    theme: theme,
                  );
                }
              : null,
        );
      },
    );
  }

  Widget _buildServerSelector(ConfigProvider provider, AppThemeData theme) {
    if (!provider.hasConfigs) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 48,
              color: theme.textColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Servers Added',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste a link or scan a QR code to add your first route',
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.5),
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showImportDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('ADD SERVER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    final selectedConfig = provider.selectedConfig;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedConfig != null
              ? theme.primaryColor.withValues(alpha: 0.3)
              : theme.primaryColor.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_rounded, color: theme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Selected Server',
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _hapticService.selection();
                  _tabController.animateTo(1);
                },
                child: Text(
                  'Change',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selectedConfig != null)
            Row(
              children: [
                // Protocol badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.getProtocolColor(
                      selectedConfig.protocolString,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    selectedConfig.protocol.shortName,
                    style: TextStyle(
                      color: AppTheme.getProtocolColor(
                        selectedConfig.protocolString,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Server info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedConfig.name,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'JetBrainsMono',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${selectedConfig.address}:${selectedConfig.port}',
                        style: TextStyle(
                          color: theme.textColor.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ],
                  ),
                ),
                // Ping
                if (selectedConfig.ping != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.getPingColor(
                        selectedConfig.ping,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${selectedConfig.ping}ms',
                      style: TextStyle(
                        color: AppTheme.getPingColor(selectedConfig.ping),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ),
              ],
            )
          else
            Text(
              'Tap "Change" to select a server',
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.5),
                fontSize: 13,
                fontFamily: 'JetBrainsMono',
              ),
            ),
        ],
      ),
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
            textColor: theme.textColor,
          );
        }

        return Column(
          children: [
            // Action bar
            _buildConfigActionBar(provider, theme),

            // Subscription folders first, then routes added by hand.
            Expanded(child: _buildRouteList(provider, theme)),
          ],
        );
      },
    );
  }

  Widget _buildRouteList(ConfigProvider provider, AppThemeData theme) {
    final subscriptions = provider.subscriptions;
    final manual = provider.manualConfigs;
    final items = <Widget>[];

    if (subscriptions.isNotEmpty) {
      items.add(_buildSectionLabel('SUBSCRIPTIONS', theme));
      for (final subscription in subscriptions) {
        final routes = provider.configsFor(subscription.id);
        final pings = routes
            .map((c) => c.ping)
            .whereType<int>()
            .where((p) => p >= 0)
            .toList();
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: SubscriptionFolderCard(
              subscription: subscription,
              routeCount: routes.length,
              bestPing: pings.isEmpty
                  ? null
                  : pings.reduce((a, b) => a < b ? a : b),
              isRefreshing: provider.isRefreshing(subscription.id),
              containsSelection:
                  provider.selectedConfig?.subscriptionId == subscription.id,
              accentColor: theme.primaryColor,
              surfaceColor: theme.surfaceColor,
              textColor: theme.textColor,
              onOpen: () => _openSubscription(subscription.id, theme),
              onRefresh: () async {
                _hapticService.selection();
                final result = await provider.refreshSubscription(
                  subscription.id,
                );
                if (!mounted) return;
                _showResult(result.message, result.success, theme);
              },
            ),
          ),
        );
      }
      if (manual.isNotEmpty) {
        items.add(_buildSectionLabel('MY ROUTES', theme));
      }
    }

    for (final config in manual) {
      items.add(_buildServerCard(context, provider, config, theme));
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      children: items,
    );
  }

  Widget _buildSectionLabel(String label, AppThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text(
        label,
        style: TextStyle(
          color: theme.textColor.withValues(alpha: 0.5),
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 1.4,
        ),
      ),
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
          cardBuilder: (ctx, provider, config) =>
              _buildServerCard(ctx, provider, config, theme),
          onRunChecks: (routes) =>
              _runHealthChecks(context.read<ConfigProvider>(), theme, routes),
          onSmartConnect: (routes) {
            _tabController.animateTo(0);
            _runSmartConnect(
              context.read<ConfigProvider>(),
              theme,
              configs: routes,
            );
          },
          onMessage: (message, {bool success = true}) {
            if (mounted) _showResult(message, success, theme);
          },
        ),
      ),
    );
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

  /// A route card with all its actions; shared by the Servers tab and
  /// subscription folders.
  Widget _buildServerCard(
    BuildContext cardContext,
    ConfigProvider provider,
    VpnConfig config,
    AppThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
      child: ServerStudioCard(
        config: config,
        snapshot: ConnectionHealthService().snapshotFor(config.id),
        isTesting: provider.isConfigTesting(config.id),
        compact: _experiencePreferences.compactStudio,
        isSelected: provider.selectedConfig?.id == config.id,
        isFavorite: _profileWorkspace.isFavorite(config.id),
        accentColor: theme.primaryColor,
        surfaceColor: theme.surfaceColor,
        textColor: theme.textColor,
        onSelect: () {
          _hapticService.selection();
          provider.selectConfig(config);
          _autoReconnectService.setServerQueue(
            provider.configs,
            activeConfigId: config.id,
          );
          _showSnackBar('${config.name} selected', theme: theme);
        },
        onToggleFavorite: () async {
          await _profileWorkspace.toggleFavorite(config.id);
          if (!mounted) return;
          _showSnackBar(
            _profileWorkspace.isFavorite(config.id)
                ? 'Added to Favorites'
                : 'Removed from Favorites',
            icon: Icons.star_rounded,
            color: const Color(0xFFFFC857),
            theme: theme,
          );
        },
        onDelete: () async {
          _hapticService.warning();
          final confirm = await DeleteConfirmDialog.show(cardContext, config);
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
          QRDisplayDialog.show(cardContext, config);
        },
        onTest: () {
          _hapticService.light();
          provider.testPing(config.id);
        },
      ),
    );
  }

  Widget _buildConfigActionBar(ConfigProvider provider, AppThemeData theme) {
    final favoriteCount = provider.configs
        .where((config) => _profileWorkspace.isFavorite(config.id))
        .length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfaceColor.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primaryColor.withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  color: theme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SERVER STUDIO',
                      style: TextStyle(
                        color: theme.textColor,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${provider.configCount} routes  •  $favoriteCount favorites  •  local health only',
                      style: TextStyle(
                        color: theme.textColor.withValues(alpha: .48),
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              _buildActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Import route',
                theme: theme,
                onTap: () {
                  _hapticService.selection();
                  _showImportDialog(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: provider.isTestingPing || _smartConnect.isRunning
                      ? null
                      : () => _runHealthChecks(provider, theme),
                  icon: const Icon(Icons.speed_rounded, size: 17),
                  label: Text(
                    provider.isTestingPing
                        ? (provider.checkTotal > 0
                              ? 'CHECKING ${provider.checkCompleted}/${provider.checkTotal}'
                              : 'CHECKING ROUTES…')
                        : 'RUN HEALTH CHECKS',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.primaryColor,
                    side: BorderSide(
                      color: theme.primaryColor.withValues(alpha: .55),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              _buildActionButton(
                icon: Icons.sort_rounded,
                tooltip: 'Sort routes',
                theme: theme,
                onTap: () {
                  _hapticService.selection();
                  _showSortOptions(context, theme);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required AppThemeData theme,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(icon, color: theme.primaryColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildLoadingState(AppThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(theme.primaryColor),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading configurations...',
            style: TextStyle(
              color: theme.textColor.withValues(alpha: 0.5),
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ],
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
        _tabController.animateTo(1);
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
    _tabController.animateTo(1);
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

    if (result != null && mounted) {
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

  double? get _smartProgressValue {
    final total = _smartConnect.progressTotal;
    if (_smartConnect.phase == SmartConnectPhase.scanning ||
        _smartConnect.phase == SmartConnectPhase.measuring) {
      return total == 0 ? null : _smartConnect.progressDone / total;
    }
    return null;
  }

  Future<void> _runSmartConnect(
    ConfigProvider provider,
    AppThemeData theme, {
    List<VpnConfig>? configs,
  }) async {
    if (_smartConnect.isRunning) return;
    _hapticService.selection();
    final connected = await _smartConnect.run(
      configs: configs ?? provider.configs,
      vpn: _vpnService,
      autoReconnect: _autoReconnectService,
      onSelect: provider.selectConfig,
      onMeasured: provider.applyMeasurements,
    );
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

  Widget _buildTunnelCheckBadge(ConfigProvider provider, AppThemeData theme) {
    final check = _vpnService.tunnelCheck;
    late final Color color;
    late final IconData icon;
    late final String label;
    switch (check) {
      case TunnelCheck.verified:
        color = const Color(0xFF20E870);
        icon = Icons.verified_rounded;
        label = _vpnService.tunnelLatencyMs == null
            ? 'Internet verified'
            : 'Internet verified • ${_vpnService.tunnelLatencyMs} ms';
      case TunnelCheck.failed:
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        label = 'Tunnel is up, but no internet';
      case TunnelCheck.checking:
      case TunnelCheck.idle:
        color = theme.primaryColor;
        icon = Icons.radar_rounded;
        label = 'Checking internet access…';
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (check == TunnelCheck.checking || check == TunnelCheck.idle)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
            if (check == TunnelCheck.failed) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _runSmartConnect(provider, theme),
                child: const Text('TRY ANOTHER'),
              ),
            ],
          ],
        ),
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
