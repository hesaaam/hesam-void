import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// App info model for split tunneling
class InstalledApp {
  final String packageName;
  final String appName;
  final bool isSystemApp;
  bool bypassVpn;

  InstalledApp({
    required this.packageName,
    required this.appName,
    this.isSystemApp = false,
    this.bypassVpn = false,
  });

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'appName': appName,
    'isSystemApp': isSystemApp,
    'bypassVpn': bypassVpn,
  };

  factory InstalledApp.fromJson(Map<String, dynamic> json) => InstalledApp(
    packageName: json['packageName'] as String,
    appName: json['appName'] as String,
    isSystemApp: json['isSystemApp'] as bool? ?? false,
    bypassVpn: json['bypassVpn'] as bool? ?? false,
  );

  InstalledApp copyWith({bool? bypassVpn}) => InstalledApp(
    packageName: packageName,
    appName: appName,
    isSystemApp: isSystemApp,
    bypassVpn: bypassVpn ?? this.bypassVpn,
  );
}

/// Split Tunneling Mode
enum SplitTunnelMode {
  disabled,      // All apps use VPN
  bypass,        // Selected apps bypass VPN
  onlySelected,  // Only selected apps use VPN
}

/// Split Tunneling Service
class SplitTunnelingService extends ChangeNotifier {
  static final SplitTunnelingService _instance = SplitTunnelingService._internal();
  factory SplitTunnelingService() => _instance;
  SplitTunnelingService._internal();

  static const String _boxName = 'split_tunneling';
  static const String _modeKey = 'mode';
  static const String _bypassAppsKey = 'bypass_apps';
  static const String _selectedAppsKey = 'selected_apps';

  Box? _box;
  SplitTunnelMode _mode = SplitTunnelMode.disabled;
  List<InstalledApp> _installedApps = [];
  Set<String> _bypassPackages = {};
  Set<String> _selectedPackages = {};
  bool _isLoading = false;

  SplitTunnelMode get mode => _mode;
  List<InstalledApp> get installedApps => _installedApps;
  Set<String> get bypassPackages => _bypassPackages;
  Set<String> get selectedPackages => _selectedPackages;
  bool get isLoading => _isLoading;

  /// Popular apps for quick bypass
  static final Map<String, String> popularApps = {
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.instagram.android': 'Instagram',
    'com.twitter.android': 'Twitter/X',
    'com.google.android.youtube': 'YouTube',
    'com.spotify.music': 'Spotify',
    'com.netflix.mediaclient': 'Netflix',
    'com.pubg.krmobile': 'PUBG Mobile',
    'com.mobile.legends': 'Mobile Legends',
    'com.supercell.clashofclans': 'Clash of Clans',
    'com.king.candycrushsaga': 'Candy Crush',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.facebook.katana': 'Facebook',
    'com.facebook.orca': 'Messenger',
    'com.snapchat.android': 'Snapchat',
    'com.discord': 'Discord',
    'com.skype.raider': 'Skype',
    'jp.naver.line.android': 'LINE',
    'com.viber.voip': 'Viber',
    'com.google.android.apps.maps': 'Google Maps',
    'com.waze': 'Waze',
    'com.ubercab': 'Uber',
    'ir.snapp.passenger': 'Snapp',
    'cab.snapp.passenger': 'Snapp (Alt)',
    'ir.tapsi.passenger': 'Tapsi',
    'com.amazon.mShop.android.shopping': 'Amazon',
    'com.alibaba.aliexpresshd': 'AliExpress',
    'com.digikala.app': 'Digikala',
    'com.android.chrome': 'Chrome',
    'org.mozilla.firefox': 'Firefox',
    'com.brave.browser': 'Brave',
    'com.microsoft.office.outlook': 'Outlook',
    'com.google.android.gm': 'Gmail',
  };

  /// Initialize Split Tunneling Service
  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
    await _loadSettings();
    await _loadInstalledApps();
  }

  /// Load saved settings
  Future<void> _loadSettings() async {
    final modeIndex = _box?.get(_modeKey, defaultValue: 0) as int? ?? 0;
    _mode = SplitTunnelMode.values[modeIndex.clamp(0, SplitTunnelMode.values.length - 1)];

    final bypassList = _box?.get(_bypassAppsKey) as List<dynamic>?;
    if (bypassList != null) {
      _bypassPackages = bypassList.cast<String>().toSet();
    }

    final selectedList = _box?.get(_selectedAppsKey) as List<dynamic>?;
    if (selectedList != null) {
      _selectedPackages = selectedList.cast<String>().toSet();
    }
  }

  /// Load installed apps (simulated for now - real implementation needs platform channel)
  Future<void> _loadInstalledApps() async {
    _isLoading = true;
    notifyListeners();

    try {
      // For now, use popular apps list
      // In real implementation, use platform channel to get installed apps
      _installedApps = popularApps.entries.map((e) => InstalledApp(
        packageName: e.key,
        appName: e.value,
        isSystemApp: e.key.startsWith('com.android') || e.key.startsWith('com.google.android'),
        bypassVpn: _bypassPackages.contains(e.key) || _selectedPackages.contains(e.key),
      )).toList();

      // Sort: non-system apps first, then alphabetically
      _installedApps.sort((a, b) {
        if (a.isSystemApp != b.isSystemApp) {
          return a.isSystemApp ? 1 : -1;
        }
        return a.appName.compareTo(b.appName);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading installed apps: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set split tunnel mode
  Future<void> setMode(SplitTunnelMode mode) async {
    _mode = mode;
    await _box?.put(_modeKey, mode.index);
    notifyListeners();
  }

  /// Toggle app bypass
  Future<void> toggleAppBypass(String packageName) async {
    if (_bypassPackages.contains(packageName)) {
      _bypassPackages.remove(packageName);
    } else {
      _bypassPackages.add(packageName);
    }
    
    // Update installed apps list
    final index = _installedApps.indexWhere((a) => a.packageName == packageName);
    if (index != -1) {
      _installedApps[index] = _installedApps[index].copyWith(
        bypassVpn: _bypassPackages.contains(packageName),
      );
    }

    await _box?.put(_bypassAppsKey, _bypassPackages.toList());
    notifyListeners();
  }

  /// Toggle app selection (for onlySelected mode)
  Future<void> toggleAppSelection(String packageName) async {
    if (_selectedPackages.contains(packageName)) {
      _selectedPackages.remove(packageName);
    } else {
      _selectedPackages.add(packageName);
    }
    
    // Update installed apps list
    final index = _installedApps.indexWhere((a) => a.packageName == packageName);
    if (index != -1) {
      _installedApps[index] = _installedApps[index].copyWith(
        bypassVpn: _selectedPackages.contains(packageName),
      );
    }

    await _box?.put(_selectedAppsKey, _selectedPackages.toList());
    notifyListeners();
  }

  /// Add bypass package
  Future<void> addBypassPackage(String packageName) async {
    _bypassPackages.add(packageName);
    await _box?.put(_bypassAppsKey, _bypassPackages.toList());
    notifyListeners();
  }

  /// Remove bypass package
  Future<void> removeBypassPackage(String packageName) async {
    _bypassPackages.remove(packageName);
    await _box?.put(_bypassAppsKey, _bypassPackages.toList());
    notifyListeners();
  }

  /// Clear all bypass packages
  Future<void> clearBypassPackages() async {
    _bypassPackages.clear();
    for (var app in _installedApps) {
      app.bypassVpn = false;
    }
    await _box?.put(_bypassAppsKey, <String>[]);
    notifyListeners();
  }

  /// Get bypass packages for V2Ray
  List<String> getBypassPackagesForV2Ray() {
    if (_mode == SplitTunnelMode.disabled) {
      return [];
    }
    
    if (_mode == SplitTunnelMode.bypass) {
      return _bypassPackages.toList();
    }

    // For onlySelected mode, return all packages EXCEPT selected
    // (This inverts the selection)
    return _installedApps
        .where((a) => !_selectedPackages.contains(a.packageName))
        .map((a) => a.packageName)
        .toList();
  }

  /// Search apps
  List<InstalledApp> searchApps(String query) {
    if (query.isEmpty) return _installedApps;
    
    final lowercaseQuery = query.toLowerCase();
    return _installedApps.where((app) {
      return app.appName.toLowerCase().contains(lowercaseQuery) ||
             app.packageName.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Get apps by category
  List<InstalledApp> getAppsByCategory(String category) {
    switch (category.toLowerCase()) {
      case 'social':
        return _installedApps.where((a) => 
          a.packageName.contains('whatsapp') ||
          a.packageName.contains('telegram') ||
          a.packageName.contains('instagram') ||
          a.packageName.contains('twitter') ||
          a.packageName.contains('facebook') ||
          a.packageName.contains('snapchat') ||
          a.packageName.contains('tiktok') ||
          a.packageName.contains('discord')
        ).toList();
      
      case 'games':
        return _installedApps.where((a) =>
          a.packageName.contains('pubg') ||
          a.packageName.contains('legends') ||
          a.packageName.contains('clash') ||
          a.packageName.contains('candy')
        ).toList();
      
      case 'streaming':
        return _installedApps.where((a) =>
          a.packageName.contains('youtube') ||
          a.packageName.contains('netflix') ||
          a.packageName.contains('spotify')
        ).toList();
      
      case 'transport':
        return _installedApps.where((a) =>
          a.packageName.contains('uber') ||
          a.packageName.contains('snapp') ||
          a.packageName.contains('tapsi') ||
          a.packageName.contains('maps') ||
          a.packageName.contains('waze')
        ).toList();
      
      default:
        return _installedApps;
    }
  }

  /// Refresh installed apps
  Future<void> refresh() async {
    await _loadInstalledApps();
  }
}
