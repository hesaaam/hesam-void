import 'package:hive_flutter/hive_flutter.dart';
import '../models/vpn_config.dart';

/// Secure Local Storage Service using Hive
class StorageService {
  static const String _configBoxName = 'vpn_configs';
  static const String _settingsBoxName = 'app_settings';
  
  static Box<VpnConfig>? _configBox;
  static Box<dynamic>? _settingsBox;

  /// Initialize Hive storage
  static Future<void> initialize() async {
    await Hive.initFlutter();
    
    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VpnConfigAdapter());
    }
    
    // Open boxes
    _configBox = await Hive.openBox<VpnConfig>(_configBoxName);
    _settingsBox = await Hive.openBox<dynamic>(_settingsBoxName);
  }

  /// Get all stored configs
  static List<VpnConfig> getAllConfigs() {
    return _configBox?.values.toList() ?? [];
  }

  /// Get config by ID
  static VpnConfig? getConfig(String id) {
    return _configBox?.values.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Config not found'),
    );
  }

  /// Save a new config
  static Future<void> saveConfig(VpnConfig config) async {
    await _configBox?.put(config.id, config);
  }

  /// Save multiple configs
  static Future<void> saveConfigs(List<VpnConfig> configs) async {
    for (final config in configs) {
      await _configBox?.put(config.id, config);
    }
  }

  /// Update an existing config
  static Future<void> updateConfig(VpnConfig config) async {
    await _configBox?.put(config.id, config);
  }

  /// Delete a config
  static Future<void> deleteConfig(String id) async {
    await _configBox?.delete(id);
  }

  /// Delete all configs
  static Future<void> deleteAllConfigs() async {
    await _configBox?.clear();
  }

  /// Get active config
  static VpnConfig? getActiveConfig() {
    return _configBox?.values.firstWhere(
      (c) => c.isActive,
      orElse: () => throw Exception('No active config'),
    );
  }

  /// Set active config (deactivates all others)
  static Future<void> setActiveConfig(String id) async {
    final configs = getAllConfigs();
    for (final config in configs) {
      final newConfig = config.copyWith(isActive: config.id == id);
      await _configBox?.put(config.id, newConfig);
    }
  }

  /// Clear active config
  static Future<void> clearActiveConfig() async {
    final configs = getAllConfigs();
    for (final config in configs) {
      if (config.isActive) {
        final newConfig = config.copyWith(isActive: false);
        await _configBox?.put(config.id, newConfig);
      }
    }
  }

  /// Update ping for a config
  static Future<void> updatePing(String id, int ping) async {
    final config = getConfig(id);
    if (config != null) {
      final updated = config.copyWith(
        ping: ping,
        lastTestedAt: DateTime.now(),
      );
      await updateConfig(updated);
    }
  }

  // Settings methods
  static T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox?.get(key, defaultValue: defaultValue) as T?;
  }

  static Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox?.put(key, value);
  }

  /// Check if this is first launch
  static bool isFirstLaunch() {
    return getSetting<bool>('first_launch', defaultValue: true) ?? true;
  }

  /// Mark first launch complete
  static Future<void> markFirstLaunchComplete() async {
    await setSetting('first_launch', false);
  }

  /// Get configs count
  static int get configCount => _configBox?.length ?? 0;

  /// Check if config exists by URL
  static bool configExistsByUrl(String url) {
    return _configBox?.values.any((c) => c.rawUrl == url) ?? false;
  }

  /// Close all boxes
  static Future<void> close() async {
    await _configBox?.close();
    await _settingsBox?.close();
  }
}
