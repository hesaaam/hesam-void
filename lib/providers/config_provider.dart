import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/config_parser_service.dart';
import '../services/ping_service.dart';

/// State Management Provider for VPN Configurations
class ConfigProvider extends ChangeNotifier {
  List<VpnConfig> _configs = [];
  bool _isLoading = false;
  String? _error;
  bool _isTestingPing = false;
  String? _testingConfigId;
  VpnConfig? _selectedConfig;

  // Getters
  List<VpnConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTestingPing => _isTestingPing;
  String? get testingConfigId => _testingConfigId;
  VpnConfig? get selectedConfig => _selectedConfig;
  int get configCount => _configs.length;
  bool get hasConfigs => _configs.isNotEmpty;

  /// Initialize and load configs from storage
  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await StorageService.initialize();
      _configs = StorageService.getAllConfigs();
      
      // Sort by creation date (newest first)
      _configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      _error = 'Failed to load configurations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import config from clipboard text
  Future<ImportResult> importFromClipboard(String text) async {
    if (text.trim().isEmpty) {
      return ImportResult(success: false, message: 'Clipboard is empty');
    }

    final configs = ConfigParserService.parseMultipleConfigs(text);
    
    if (configs.isEmpty) {
      return ImportResult(
        success: false,
        message: 'No valid configurations found',
      );
    }

    int imported = 0;
    int skipped = 0;

    for (final config in configs) {
      if (!StorageService.configExistsByUrl(config.rawUrl)) {
        await StorageService.saveConfig(config);
        _configs.insert(0, config);
        imported++;
      } else {
        skipped++;
      }
    }

    notifyListeners();

    if (imported > 0) {
      return ImportResult(
        success: true,
        message: 'Imported $imported config(s)${skipped > 0 ? ', $skipped skipped (duplicates)' : ''}',
        importedCount: imported,
        skippedCount: skipped,
      );
    } else {
      return ImportResult(
        success: false,
        message: 'All configurations already exist',
        skippedCount: skipped,
      );
    }
  }

  /// Add a single config
  Future<bool> addConfig(VpnConfig config) async {
    try {
      if (StorageService.configExistsByUrl(config.rawUrl)) {
        return false;
      }
      
      await StorageService.saveConfig(config);
      _configs.insert(0, config);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add configuration: $e';
      notifyListeners();
      return false;
    }
  }

  /// Delete a config
  Future<void> deleteConfig(String id) async {
    try {
      await StorageService.deleteConfig(id);
      _configs.removeWhere((c) => c.id == id);
      if (_selectedConfig?.id == id) {
        _selectedConfig = null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete configuration: $e';
      notifyListeners();
    }
  }

  /// Delete all configs
  Future<void> deleteAllConfigs() async {
    try {
      await StorageService.deleteAllConfigs();
      _configs.clear();
      _selectedConfig = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete all configurations: $e';
      notifyListeners();
    }
  }

  /// Select a config
  void selectConfig(VpnConfig config) {
    _selectedConfig = config;
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedConfig = null;
    notifyListeners();
  }

  /// Test ping for a single config
  Future<int?> testPing(String id) async {
    _testingConfigId = id;
    _isTestingPing = true;
    notifyListeners();

    try {
      final config = _configs.firstWhere((c) => c.id == id);
      final ping = await PingService.testPing(config);
      
      // Update the config with new ping
      final index = _configs.indexWhere((c) => c.id == id);
      if (index != -1) {
        final updated = config.copyWith(
          ping: ping,
          lastTestedAt: DateTime.now(),
        );
        _configs[index] = updated;
        await StorageService.updateConfig(updated);
      }
      
      return ping;
    } catch (e) {
      _error = 'Failed to test ping: $e';
      return null;
    } finally {
      _isTestingPing = false;
      _testingConfigId = null;
      notifyListeners();
    }
  }

  /// Test ping for all configs - OPTIMIZED with concurrent testing
  Future<void> testAllPings() async {
    _isTestingPing = true;
    notifyListeners();

    try {
      // Use optimized concurrent ping testing
      final results = await PingService.testMultiplePings(
        _configs,
        concurrency: 10, // Test 10 at a time for speed
        onProgress: (completed, total) {
          // Update progress - show which config is being tested
          if (completed < _configs.length) {
            _testingConfigId = _configs[completed].id;
            notifyListeners();
          }
        },
      );
      
      // Update all configs with results
      for (int i = 0; i < _configs.length; i++) {
        final ping = results[_configs[i].id];
        final updated = _configs[i].copyWith(
          ping: ping,
          lastTestedAt: DateTime.now(),
        );
        _configs[i] = updated;
        // Batch save for better performance
      }
      
      // Save all updates at once
      await StorageService.saveConfigs(_configs);
      
    } catch (e) {
      _error = 'Failed to test pings: $e';
    } finally {
      _isTestingPing = false;
      _testingConfigId = null;
      notifyListeners();
    }
  }
  
  /// Find and select fastest config automatically
  Future<VpnConfig?> selectFastest() async {
    _isTestingPing = true;
    notifyListeners();
    
    try {
      final fastest = await PingService.findFastest(_configs);
      if (fastest != null) {
        _selectedConfig = fastest;
        notifyListeners();
      }
      return fastest;
    } finally {
      _isTestingPing = false;
      notifyListeners();
    }
  }

  /// Sort configs by ping (fastest first)
  void sortByPing() {
    _configs = PingService.sortByPing(_configs);
    notifyListeners();
  }

  /// Sort configs by name
  void sortByName() {
    _configs.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  /// Sort configs by date (newest first)
  void sortByDate() {
    _configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Sort configs by protocol
  void sortByProtocol() {
    _configs.sort((a, b) => a.protocolString.compareTo(b.protocolString));
    notifyListeners();
  }

  /// Get configs filtered by protocol
  List<VpnConfig> getConfigsByProtocol(VpnProtocol protocol) {
    return _configs.where((c) => c.protocol == protocol).toList();
  }

  /// Search configs by name or address
  List<VpnConfig> searchConfigs(String query) {
    if (query.isEmpty) return _configs;
    
    final lowerQuery = query.toLowerCase();
    return _configs.where((c) =>
      c.name.toLowerCase().contains(lowerQuery) ||
      c.address.toLowerCase().contains(lowerQuery) ||
      c.protocolString.toLowerCase().contains(lowerQuery)
    ).toList();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Update config name
  Future<void> updateConfigName(String id, String name) async {
    final index = _configs.indexWhere((c) => c.id == id);
    if (index != -1) {
      final updated = _configs[index].copyWith(name: name);
      _configs[index] = updated;
      await StorageService.updateConfig(updated);
      notifyListeners();
    }
  }
}

/// Result of import operation
class ImportResult {
  final bool success;
  final String message;
  final int importedCount;
  final int skippedCount;

  ImportResult({
    required this.success,
    required this.message,
    this.importedCount = 0,
    this.skippedCount = 0,
  });
}
