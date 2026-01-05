import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/vpn_service.dart';
import '../utils/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/config_card.dart';
import '../widgets/qr_dialog.dart';
import '../widgets/connect_button.dart';
import 'qr_scanner_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().initialize();
      _vpnService.initialize();
    });

    // Listen to VPN service changes
    _vpnService.addListener(_onVpnStatusChanged);
  }

  void _onVpnStatusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _vpnService.removeListener(_onVpnStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              _buildAppBar(),
              
              // Tab Bar
              _buildTabBar(),
              
              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildConnectTab(),
                    _buildConfigsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
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
                      ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                      : AppTheme.primaryGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _vpnService.isConnected
                        ? AppTheme.primaryGreen
                        : AppTheme.primaryGreen.withValues(alpha: 0.3),
                  ),
                  boxShadow: _vpnService.isConnected
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.shield_rounded,
                  color: _vpnService.isConnected
                      ? AppTheme.primaryGreen
                      : AppTheme.primaryGreen.withValues(alpha: 0.7),
                  size: 24,
                ),
              )
                  .animate(target: _vpnService.isConnected ? 1 : 0)
                  .shimmer(
                    duration: 2000.ms,
                    color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                  ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HESAM VOID',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'JetBrainsMono',
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    _vpnService.isConnected ? 'Protected' : 'Not Protected',
                    style: TextStyle(
                      color: _vpnService.isConnected
                          ? AppTheme.primaryGreen
                          : AppTheme.textMuted,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const Spacer(),
          
          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _vpnService.isConnected
                  ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                  : AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _vpnService.isConnected
                    ? AppTheme.primaryGreen
                    : AppTheme.textMuted.withValues(alpha: 0.3),
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
                        ? AppTheme.primaryGreen
                        : AppTheme.accentRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_vpnService.isConnected
                                ? AppTheme.primaryGreen
                                : AppTheme.accentRed)
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                )
                    .animate(
                      onPlay: (c) => _vpnService.isConnected ? c.repeat() : c.stop(),
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
                        ? AppTheme.primaryGreen
                        : AppTheme.textMuted,
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.backgroundElevated),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primaryGreen),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppTheme.primaryGreen,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
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

  Widget _buildConnectTab() {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final selectedConfig = provider.selectedConfig;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              
              // Connect Button
              ConnectButton(
                status: _vpnService.status,
                serverName: selectedConfig?.name ?? _vpnService.currentConfig?.name,
                onTap: () => _handleConnect(provider),
              ),
              
              const SizedBox(height: 30),
              
              // Connection Stats (when connected)
              if (_vpnService.isConnected)
                ConnectionStats(stats: _vpnService.stats),
              
              // Server Selection (when disconnected)
              if (!_vpnService.isConnected && !_vpnService.isConnecting) ...[
                const SizedBox(height: 20),
                _buildServerSelector(provider),
              ],
              
              // Error message
              if (_vpnService.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.accentRed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _vpnService.errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.accentRed,
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

  Widget _buildServerSelector(ConfigProvider provider) {
    if (!provider.hasConfigs) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.backgroundElevated),
        ),
        child: Column(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 48,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Servers Added',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Go to SERVERS tab to add your first config',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.add_rounded),
              label: const Text('ADD SERVER'),
            ),
          ],
        ),
      );
    }

    final selectedConfig = provider.selectedConfig;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedConfig != null
              ? AppTheme.primaryGreen.withValues(alpha: 0.3)
              : AppTheme.backgroundElevated,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_rounded,
                color: AppTheme.primaryGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Selected Server',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _tabController.animateTo(1),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.getProtocolColor(selectedConfig.protocolString)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    selectedConfig.protocol.shortName,
                    style: TextStyle(
                      color: AppTheme.getProtocolColor(selectedConfig.protocolString),
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
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'JetBrainsMono',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${selectedConfig.address}:${selectedConfig.port}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.getPingColor(selectedConfig.ping)
                          .withValues(alpha: 0.15),
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
            const Text(
              'Tap "Change" to select a server',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
                fontFamily: 'JetBrainsMono',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfigsTab() {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return _buildLoadingState();
        }
        
        if (!provider.hasConfigs) {
          return EmptyConfigsWidget(
            onAddConfig: () => _showImportDialog(context),
          );
        }
        
        return Column(
          children: [
            // Action bar
            _buildConfigActionBar(provider),
            
            // Config list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: provider.configs.length,
                itemBuilder: (context, index) {
                  final config = provider.configs[index];
                  final isTesting = provider.isTestingPing && 
                      provider.testingConfigId == config.id;
                  
                  return ConfigCard(
                    config: config,
                    index: index,
                    isTesting: isTesting,
                    isSelected: provider.selectedConfig?.id == config.id,
                    onTap: () {
                      provider.selectConfig(config);
                      _showSnackBar('${config.name} selected');
                    },
                    onDelete: () async {
                      final confirm = await DeleteConfirmDialog.show(context, config);
                      if (confirm == true) {
                        provider.deleteConfig(config.id);
                        _showSnackBar('Config deleted', icon: Icons.delete_outline);
                      }
                    },
                    onExportClipboard: () {
                      _showSnackBar('Copied to clipboard', icon: Icons.check_circle);
                    },
                    onExportQR: () {
                      QRDisplayDialog.show(context, config);
                    },
                    onTestPing: () {
                      provider.testPing(config.id);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigActionBar(ConfigProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '${provider.configCount} servers',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          const Spacer(),
          _buildActionButton(
            icon: Icons.add_rounded,
            tooltip: 'Add',
            onTap: () => _showImportDialog(context),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.speed_rounded,
            tooltip: 'Test All',
            onTap: () => provider.testAllPings(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.sort_rounded,
            tooltip: 'Sort',
            onTap: () => _showSortOptions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
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
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.backgroundElevated),
          ),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Loading configurations...',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ],
      ),
    );
  }

  void _handleConnect(ConfigProvider provider) {
    final config = provider.selectedConfig ?? 
        (_vpnService.isConnected ? _vpnService.currentConfig : null);
    
    if (_vpnService.isConnected) {
      _vpnService.disconnect();
      return;
    }
    
    if (config == null) {
      if (provider.hasConfigs) {
        // Auto-select first config if none selected
        provider.selectConfig(provider.configs.first);
        _vpnService.connect(provider.configs.first);
      } else {
        _showSnackBar(
          'Please add a server first',
          icon: Icons.warning_amber_rounded,
          color: AppTheme.accentOrange,
        );
        _tabController.animateTo(1);
      }
      return;
    }
    
    _vpnService.connect(config);
  }

  void _showImportDialog(BuildContext context) {
    ImportOptionsDialog.show(
      context,
      onClipboardImport: () => _importFromClipboard(context),
      onQRScan: () => _scanQRCode(context),
    );
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final provider = context.read<ConfigProvider>();
    
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) {
        _showSnackBar('Clipboard is empty', icon: Icons.warning_amber_rounded);
        return;
      }
      
      final result = await provider.importFromClipboard(data.text!);
      
      _showSnackBar(
        result.message,
        icon: result.success ? Icons.check_circle : Icons.error_outline,
        color: result.success ? AppTheme.primaryGreen : AppTheme.accentRed,
      );
    } catch (e) {
      _showSnackBar('Failed to import: $e', icon: Icons.error_outline);
    }
  }

  Future<void> _scanQRCode(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    
    if (result != null && mounted) {
      final provider = context.read<ConfigProvider>();
      final importResult = await provider.importFromClipboard(result);
      
      _showSnackBar(
        importResult.message,
        icon: importResult.success ? Icons.check_circle : Icons.error_outline,
        color: importResult.success ? AppTheme.primaryGreen : AppTheme.accentRed,
      );
    }
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sort Servers',
              style: TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 20),
            _buildSortOption(
              icon: Icons.speed_rounded,
              title: 'By Ping (Fastest)',
              onTap: () {
                context.read<ConfigProvider>().sortByPing();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha_rounded,
              title: 'By Name',
              onTap: () {
                context.read<ConfigProvider>().sortByName();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.schedule_rounded,
              title: 'By Date Added',
              onTap: () {
                context.read<ConfigProvider>().sortByDate();
                Navigator.pop(context);
              },
            ),
            _buildSortOption(
              icon: Icons.category_rounded,
              title: 'By Protocol',
              onTap: () {
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
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontFamily: 'JetBrainsMono',
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showSnackBar(
    String message, {
    IconData icon = Icons.info_outline,
    Color color = AppTheme.primaryGreen,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.backgroundElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
