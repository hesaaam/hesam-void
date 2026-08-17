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
import 'qr_scanner_screen.dart';
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
  }

  void _onVpnStatusChanged() {
    if (mounted) {
      setState(() {});

      // Trigger haptic feedback based on status
      switch (_vpnService.status) {
        case VpnStatus.connected:
          _hapticService.onConnectionEstablished();
          break;
        case VpnStatus.disconnected:
          _hapticService.onDisconnect();
          break;
        case VpnStatus.error:
          _hapticService.onError();
          break;
        default:
          break;
      }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themeManager.currentTheme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: AnimatedBackground(
        primaryColor: theme.primaryColor,
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
              AliveSignalCanvas(
                status: _vpnService.status,
                config: selectedConfig ?? _vpnService.currentConfig,
                stats: _vpnService.stats,
                accentColor: theme.primaryColor,
                surfaceColor: theme.surfaceColor,
                textColor: theme.textColor,
                onPrimaryAction: () {
                  _hapticService.onConnect();
                  if (!_vpnService.isConnected && selectedConfig == null) {
                    _showQuickConnect(provider, theme);
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
              const SizedBox(height: 16),
              _buildSuperContextStrip(provider, theme),
              const SizedBox(height: 20),

              // Tunnel Active Badge (when connected) - Moved outside stats
              if (_vpnService.isConnected) ...[
                const SizedBox(height: 16),
                _buildTunnelActiveBadge(theme),
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
                  // Simple stats
                  ConnectionStats(
                    stats: _vpnService.stats,
                    primaryColor: theme.primaryColor,
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

              // Error message
              if (_vpnService.errorMessage != null)
                Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _vpnService.errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontFamily: 'JetBrainsMono',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .shake(duration: 500.ms, hz: 2),
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
      onRunChecks: () async {
        await provider.testAllPings();
        if (!mounted) return;
        _showSnackBar(
          'Local health checks refreshed',
          icon: Icons.speed_rounded,
          color: theme.primaryColor,
          theme: theme,
        );
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
              'Go to SERVERS tab to add your first config',
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.5),
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _hapticService.selection();
                _tabController.animateTo(1);
              },
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

            // Config list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: provider.configs.length,
                itemBuilder: (context, index) {
                  final config = provider.configs[index];
                  final isTesting =
                      provider.isTestingPing &&
                      provider.testingConfigId == config.id;

                  final snapshot = ConnectionHealthService().snapshotFor(
                    config.id,
                  );
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
                    child: ServerStudioCard(
                      config: config,
                      snapshot: snapshot,
                      isTesting: isTesting,
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
                        final confirm = await DeleteConfirmDialog.show(
                          context,
                          config,
                        );
                        if (confirm == true) {
                          _hapticService.onDelete();
                          await provider.deleteConfig(config.id);
                          await _profileWorkspace.forget(config.id);
                          if (!mounted) return;
                          _showSnackBar(
                            'Config deleted',
                            icon: Icons.delete_outline,
                            theme: theme,
                          );
                        }
                      },
                      onCopy: () async {
                        await Clipboard.setData(
                          ClipboardData(text: config.rawUrl),
                        );
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
                        QRDisplayDialog.show(context, config);
                      },
                      onTest: () {
                        _hapticService.light();
                        provider.testPing(config.id);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
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
                  onPressed: provider.isTestingPing
                      ? null
                      : () {
                          _hapticService.selection();
                          provider.testAllPings();
                        },
                  icon: const Icon(Icons.speed_rounded, size: 17),
                  label: Text(
                    provider.isTestingPing
                        ? 'CHECKING ROUTES…'
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
    );
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

  Widget _buildTunnelActiveBadge(AppThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: theme.primaryColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'TUNNEL ACTIVE',
            style: TextStyle(
              color: theme.primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrainsMono',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
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
