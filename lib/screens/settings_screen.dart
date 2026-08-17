import 'package:flutter/material.dart';
import '../utils/theme_manager.dart';
import '../services/haptic_service.dart';
import '../services/split_tunneling_service.dart';
import '../services/config_optimizer_service.dart';
import '../services/fragment_service.dart';
import '../services/auto_reconnect_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _themeManager = ThemeManager();
  final _hapticService = HapticService();
  final _splitTunnelingService = SplitTunnelingService();
  final _configOptimizer = ConfigOptimizerService();
  final _fragmentService = FragmentService();
  final _autoReconnect = AutoReconnectService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _themeManager.initialize();
    await _hapticService.initialize();
    await _splitTunnelingService.initialize();
    // These services are already initialized in main.dart with Hive
    // but we add listeners for UI updates
    _configOptimizer.addListener(_onSettingsChanged);
    _fragmentService.addListener(_onSettingsChanged);
    _autoReconnect.addListener(_onSettingsChanged);
    if (mounted) setState(() {});
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _configOptimizer.removeListener(_onSettingsChanged);
    _fragmentService.removeListener(_onSettingsChanged);
    _autoReconnect.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themeManager.currentTheme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        title: Text(
          'SETTINGS',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontWeight: FontWeight.bold,
            color: theme.primaryColor,
            letterSpacing: 2,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.primaryColor),
          onPressed: () {
            _hapticService.light();
            Navigator.pop(context);
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.primaryColor,
          labelColor: theme.primaryColor,
          unselectedLabelColor: theme.textColor.withValues(alpha: 0.5),
          tabs: const [
            Tab(icon: Icon(Icons.palette), text: 'THEME'),
            Tab(icon: Icon(Icons.tune), text: 'OPTIMIZE'),
            Tab(icon: Icon(Icons.alt_route), text: 'SPLIT'),
            Tab(icon: Icon(Icons.settings), text: 'GENERAL'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildThemeTab(theme),
          _buildOptimizeTab(theme),
          _buildSplitTunnelTab(theme),
          _buildGeneralTab(theme),
        ],
      ),
    );
  }

  Widget _buildThemeTab(AppThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('SELECT THEME', theme),
        const SizedBox(height: 12),
        ...PredefinedThemes.all.map((t) => _buildThemeCard(t, theme)),
        const SizedBox(height: 24),
        _buildSectionHeader('CUSTOM THEMES', theme),
        const SizedBox(height: 12),
        if (_themeManager.customThemes.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No custom themes yet',
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: 0.5),
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          )
        else
          ..._themeManager.customThemes.map(
            (t) => _buildThemeCard(t, theme, isCustom: true),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _showCreateThemeDialog(theme),
          icon: const Icon(Icons.add),
          label: const Text('CREATE CUSTOM THEME'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        // Extra padding at bottom to ensure last item is visible
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildThemeCard(
    AppThemeData t,
    AppThemeData currentTheme, {
    bool isCustom = false,
  }) {
    final isSelected = _themeManager.currentTheme.id == t.id;

    return GestureDetector(
      onTap: () {
        _hapticService.selection();
        _themeManager.setTheme(t);
        setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: currentTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? t.primaryColor
                : currentTheme.primaryColor.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: t.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Color preview circles
            Row(
              children: [
                _colorCircle(t.primaryColor),
                _colorCircle(t.secondaryColor),
                _colorCircle(t.backgroundColor),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: TextStyle(
                      color: currentTheme.textColor,
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    t.brightness == Brightness.dark
                        ? 'Dark Mode'
                        : 'Light Mode',
                    style: TextStyle(
                      color: currentTheme.textColor.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: t.primaryColor),
            if (isCustom)
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Colors.red.withValues(alpha: 0.7),
                ),
                onPressed: () {
                  _hapticService.warning();
                  _themeManager.removeCustomTheme(t.id);
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _colorCircle(Color color) {
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  Widget _buildOptimizeTab(AppThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('CONFIG OPTIMIZATION', theme),
        const SizedBox(height: 12),
        _buildSettingCard(
          icon: Icons.speed,
          title: 'Auto Optimize Speed',
          subtitle: 'Automatically adjust MTU, buffer size, DNS',
          theme: theme,
          trailing: Switch(
            value: _configOptimizer.settings.autoOptimize,
            onChanged: (v) {
              _hapticService.onSwitch();
              _configOptimizer.settings = _configOptimizer.settings.copyWith(
                autoOptimize: v,
              );
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),
        _buildSettingCard(
          icon: Icons.dns,
          title: 'DNS Provider',
          subtitle: _configOptimizer.settings.preferredDns,
          theme: theme,
          onTap: () => _showDnsSelector(theme),
        ),
        _buildSettingCard(
          icon: Icons.network_check,
          title: 'MTU Size',
          subtitle: '${_configOptimizer.settings.mtuSize} bytes',
          theme: theme,
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _configOptimizer.settings.mtuSize.toDouble(),
              min: 1200,
              max: 1500,
              divisions: 30,
              activeColor: theme.primaryColor,
              onChanged: (v) {
                _hapticService.onSliderChange();
                _configOptimizer.settings = _configOptimizer.settings.copyWith(
                  mtuSize: v.toInt(),
                );
                setState(() {});
              },
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('ANTI-FILTERING', theme),
        const SizedBox(height: 12),
        _buildSettingCard(
          icon: Icons.shield,
          title: 'Fragment Injection',
          subtitle: 'Break packets to bypass DPI',
          theme: theme,
          trailing: Switch(
            value: _fragmentService.settings.fragmentEnabled,
            onChanged: (v) {
              _hapticService.onSwitch();
              _fragmentService.settings = _fragmentService.settings.copyWith(
                fragmentEnabled: v,
              );
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),
        _buildSettingCard(
          icon: Icons.security,
          title: 'TLS Padding',
          subtitle: 'Add random padding to TLS packets',
          theme: theme,
          trailing: Switch(
            value: _fragmentService.settings.tlsPaddingEnabled,
            onChanged: (v) {
              _hapticService.onSwitch();
              _fragmentService.settings = _fragmentService.settings.copyWith(
                tlsPaddingEnabled: v,
              );
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),
        _buildSettingCard(
          icon: Icons.shuffle,
          title: 'SNI Randomization',
          subtitle: 'Randomize Server Name Indication',
          theme: theme,
          trailing: Switch(
            value: _fragmentService.settings.sniRandomizationEnabled,
            onChanged: (v) {
              _hapticService.onSwitch();
              _fragmentService.settings = _fragmentService.settings.copyWith(
                sniRandomizationEnabled: v,
              );
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),
        _buildSettingCard(
          icon: Icons.fingerprint,
          title: 'TLS Fingerprint',
          subtitle: _fragmentService.settings.tlsFingerprint,
          theme: theme,
          onTap: () => _showFingerprintSelector(theme),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('AUTO-RECONNECT', theme),
        const SizedBox(height: 12),
        _buildSettingCard(
          icon: Icons.autorenew,
          title: 'Auto Reconnect',
          subtitle: 'Automatically reconnect on disconnect',
          theme: theme,
          trailing: Switch(
            value: _autoReconnect.isEnabled,
            onChanged: (v) {
              _hapticService.onSwitch();
              _autoReconnect.setEnabled(v);
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),
        _buildSettingCard(
          icon: Icons.timer,
          title: 'Reconnect Delay',
          subtitle: '${_autoReconnect.reconnectDelay.inSeconds} seconds',
          theme: theme,
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _autoReconnect.reconnectDelay.inSeconds.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              activeColor: theme.primaryColor,
              onChanged: (v) {
                _hapticService.onSliderChange();
                _autoReconnect.setReconnectDelay(Duration(seconds: v.toInt()));
                setState(() {});
              },
            ),
          ),
        ),
        _buildSettingCard(
          icon: Icons.repeat,
          title: 'Max Retries',
          subtitle: '${_autoReconnect.maxRetries} attempts',
          theme: theme,
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _autoReconnect.maxRetries.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: theme.primaryColor,
              onChanged: (v) {
                _hapticService.onSliderChange();
                _autoReconnect.setMaxRetries(v.toInt());
                setState(() {});
              },
            ),
          ),
        ),
        // Extra padding at bottom
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSplitTunnelTab(AppThemeData theme) {
    return Column(
      children: [
        // Mode selector
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('SPLIT TUNNEL MODE', theme),
              const SizedBox(height: 12),
              _buildModeSelector(theme),
            ],
          ),
        ),

        // Apps list
        if (_splitTunnelingService.mode != SplitTunnelMode.disabled)
          Expanded(
            child: _splitTunnelingService.isLoading
                ? Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 100,
                    ),
                    itemCount: _splitTunnelingService.installedApps.length,
                    itemBuilder: (context, index) {
                      final app = _splitTunnelingService.installedApps[index];
                      return _buildAppItem(app, theme);
                    },
                  ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.alt_route,
                    size: 64,
                    color: theme.primaryColor.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Split Tunneling Disabled',
                    style: TextStyle(
                      color: theme.textColor,
                      fontFamily: 'JetBrainsMono',
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All traffic will go through VPN',
                    style: TextStyle(
                      color: theme.textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildModeSelector(AppThemeData theme) {
    return Row(
      children: [
        _buildModeChip(
          'Disabled',
          SplitTunnelMode.disabled,
          Icons.block,
          theme,
        ),
        const SizedBox(width: 8),
        _buildModeChip(
          'Bypass',
          SplitTunnelMode.bypass,
          Icons.fast_forward,
          theme,
        ),
        const SizedBox(width: 8),
        _buildModeChip(
          'Only VPN',
          SplitTunnelMode.onlySelected,
          Icons.vpn_lock,
          theme,
        ),
      ],
    );
  }

  Widget _buildModeChip(
    String label,
    SplitTunnelMode mode,
    IconData icon,
    AppThemeData theme,
  ) {
    final isSelected = _splitTunnelingService.mode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          _hapticService.selection();
          _splitTunnelingService.setMode(mode);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : theme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.primaryColor
                  : theme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.black : theme.primaryColor,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : theme.textColor,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppItem(InstalledApp app, AppThemeData theme) {
    final isSelected = _splitTunnelingService.mode == SplitTunnelMode.bypass
        ? _splitTunnelingService.bypassPackages.contains(app.packageName)
        : _splitTunnelingService.selectedPackages.contains(app.packageName);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.primaryColor
              : theme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            app.isSystemApp ? Icons.android : Icons.apps,
            color: theme.primaryColor,
          ),
        ),
        title: Text(
          app.appName,
          style: TextStyle(
            color: theme.textColor,
            fontFamily: 'JetBrainsMono',
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          app.packageName,
          style: TextStyle(
            color: theme.textColor.withValues(alpha: 0.5),
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: isSelected,
          onChanged: (v) {
            _hapticService.onSwitch();
            if (_splitTunnelingService.mode == SplitTunnelMode.bypass) {
              _splitTunnelingService.toggleAppBypass(app.packageName);
            } else {
              _splitTunnelingService.toggleAppSelection(app.packageName);
            }
            setState(() {});
          },
          activeThumbColor: theme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildGeneralTab(AppThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('HAPTIC FEEDBACK', theme),
        const SizedBox(height: 12),
        _buildSettingCard(
          icon: Icons.vibration,
          title: 'Haptic Feedback',
          subtitle: 'Vibration on touch interactions',
          theme: theme,
          trailing: Switch(
            value: _hapticService.isEnabled,
            onChanged: (v) {
              _hapticService.setEnabled(v);
              if (v) _hapticService.success();
              setState(() {});
            },
            activeThumbColor: theme.primaryColor,
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('ABOUT', theme),
        const SizedBox(height: 12),
        _buildSettingCard(
          icon: Icons.info,
          title: 'Version',
          subtitle: '3.0.1',
          theme: theme,
        ),
        _buildSettingCard(
          icon: Icons.code,
          title: 'Developer',
          subtitle: 'Hesam',
          theme: theme,
        ),
        _buildSettingCard(
          icon: Icons.memory,
          title: 'Xray Core',
          subtitle: '25.3.6',
          theme: theme,
        ),
        _buildSettingCard(
          icon: Icons.flutter_dash,
          title: 'Flutter',
          subtitle: '3.35.4',
          theme: theme,
        ),
        // Extra padding at bottom
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSectionHeader(String title, AppThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        color: theme.primaryColor,
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        fontSize: 12,
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppThemeData theme,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.primaryColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.textColor,
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.textColor.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null && trailing == null)
              Icon(
                Icons.chevron_right,
                color: theme.primaryColor.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  void _showDnsSelector(AppThemeData theme) {
    final dnsOptions = ['1.1.1.1', '8.8.8.8', '9.9.9.9', 'DoH', 'DoT'];

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELECT DNS',
              style: TextStyle(
                color: theme.primaryColor,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            ...dnsOptions.map(
              (dns) => ListTile(
                leading: Icon(Icons.dns, color: theme.primaryColor),
                title: Text(dns, style: TextStyle(color: theme.textColor)),
                trailing: _configOptimizer.settings.preferredDns == dns
                    ? Icon(Icons.check_circle, color: theme.primaryColor)
                    : null,
                onTap: () {
                  _hapticService.selection();
                  _configOptimizer.settings = _configOptimizer.settings
                      .copyWith(preferredDns: dns);
                  setState(() {});
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFingerprintSelector(AppThemeData theme) {
    final fingerprintOptions = [
      'chrome',
      'firefox',
      'safari',
      'edge',
      'ios',
      'android',
      'random',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELECT TLS FINGERPRINT',
              style: TextStyle(
                color: theme.primaryColor,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            ...fingerprintOptions.map(
              (fp) => ListTile(
                leading: Icon(Icons.fingerprint, color: theme.primaryColor),
                title: Text(
                  fp.toUpperCase(),
                  style: TextStyle(color: theme.textColor),
                ),
                trailing: _fragmentService.settings.tlsFingerprint == fp
                    ? Icon(Icons.check_circle, color: theme.primaryColor)
                    : null,
                onTap: () {
                  _hapticService.selection();
                  _fragmentService.settings = _fragmentService.settings
                      .copyWith(tlsFingerprint: fp);
                  setState(() {});
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateThemeDialog(AppThemeData theme) {
    Color selectedColor = theme.primaryColor;
    final nameController = TextEditingController();
    bool isDark = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: theme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.3)),
          ),
          title: Text(
            'CREATE THEME',
            style: TextStyle(
              color: theme.primaryColor,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: theme.textColor),
                  decoration: InputDecoration(
                    labelText: 'Theme Name',
                    labelStyle: TextStyle(
                      color: theme.textColor.withValues(alpha: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Primary Color', style: TextStyle(color: theme.textColor)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            Colors.red,
                            Colors.pink,
                            Colors.purple,
                            Colors.deepPurple,
                            Colors.indigo,
                            Colors.blue,
                            Colors.cyan,
                            Colors.teal,
                            Colors.green,
                            Colors.lime,
                            Colors.yellow,
                            Colors.orange,
                            Colors.deepOrange,
                          ]
                          .map(
                            (color) => GestureDetector(
                              onTap: () {
                                setDialogState(() => selectedColor = color);
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selectedColor == color
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dark Mode', style: TextStyle(color: theme.textColor)),
                    Switch(
                      value: isDark,
                      onChanged: (v) => setDialogState(() => isDark = v),
                      activeThumbColor: selectedColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'CANCEL',
                style: TextStyle(color: theme.textColor.withValues(alpha: 0.5)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final newTheme = _themeManager.createCustomTheme(
                    name: nameController.text,
                    primaryColor: selectedColor,
                    isDark: isDark,
                  );
                  _themeManager.addCustomTheme(newTheme);
                  _hapticService.success();
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('CREATE'),
            ),
          ],
        ),
      ),
    );
  }
}
