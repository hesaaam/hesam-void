import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/config_parser_service.dart';
import '../services/ping_service.dart';
import '../services/connection_health_service.dart';

/// State Management Provider for VPN Configurations
class ConfigProvider extends ChangeNotifier {
  static const _selectedConfigKey = 'selected_config_id_v1';

  List<VpnConfig> _configs = [];
  bool _isLoading = false;
  String? _error;
  bool _isTestingPing = false;
  String? _testingConfigId;
  final Set<String> _testingIds = <String>{};
  int _checkCompleted = 0;
  int _checkTotal = 0;
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

  /// Progress of the current "check all" run, e.g. 7 of 20.
  int get checkCompleted => _checkCompleted;
  int get checkTotal => _checkTotal;

  /// Whether a latency check for [id] is currently in flight.
  bool isConfigTesting(String id) => _testingIds.contains(id);

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

      // Restore the route the user chose last time.
      final selectedId = StorageService.getSetting<String>(_selectedConfigKey);
      if (selectedId != null) {
        for (final config in _configs) {
          if (config.id == selectedId) {
            _selectedConfig = config;
            break;
          }
        }
      }
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
        message:
            'Imported $imported config(s)${skipped > 0 ? ', $skipped skipped (duplicates)' : ''}',
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
        await StorageService.setSetting<String?>(_selectedConfigKey, null);
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
      await StorageService.setSetting<String?>(_selectedConfigKey, null);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete all configurations: $e';
      notifyListeners();
    }
  }

  /// Select a config
  void selectConfig(VpnConfig config) {
    _selectedConfig = config;
    unawaited(StorageService.setSetting<String>(_selectedConfigKey, config.id));
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedConfig = null;
    unawaited(StorageService.setSetting<String?>(_selectedConfigKey, null));
    notifyListeners();
  }

  /// Test ping for a single config
  Future<int?> testPing(String id) async {
    final index = _configs.indexWhere((c) => c.id == id);
    if (index == -1) return null;
    final config = _configs[index];

    _testingIds.add(id);
    _testingConfigId = id;
    _isTestingPing = true;
    notifyListeners();

    try {
      final ping = await PingService.testPing(config, useCache: false);
      await ConnectionHealthService().recordProbe(config.id, ping);
      _applyLatency(config.id, ping);
      await _persistConfig(config.id);
      return ping;
    } catch (e) {
      _error = 'Failed to test ping: $e';
      return null;
    } finally {
      _testingIds.remove(id);
      _isTestingPing = _testingIds.isNotEmpty;
      _testingConfigId = _testingIds.isEmpty ? null : _testingIds.first;
      notifyListeners();
    }
  }

  /// Tests every profile concurrently and shows each result as it arrives.
  Future<Map<String, int?>> testAllPings() async {
    if (_configs.isEmpty) return <String, int?>{};
    final targets = List<VpnConfig>.from(_configs);
    _isTestingPing = true;
    _testingIds
      ..clear()
      ..addAll(targets.map((c) => c.id));
    _checkCompleted = 0;
    _checkTotal = targets.length;
    notifyListeners();

    try {
      final results = await PingService.testMultiplePings(
        targets,
        concurrency: 12,
        onResult: (config, ping) {
          _testingIds.remove(config.id);
          _checkCompleted++;
          _applyLatency(config.id, ping);
          notifyListeners();
        },
      );

      // One write for health history and one for profiles.
      await ConnectionHealthService().recordProbes(results);
      await StorageService.saveConfigs(_configs);
      return results;
    } catch (e) {
      _error = 'Failed to test pings: $e';
      return <String, int?>{};
    } finally {
      _isTestingPing = false;
      _testingConfigId = null;
      _testingIds.clear();
      _checkCompleted = 0;
      _checkTotal = 0;
      notifyListeners();
    }
  }

  /// Stores latency values measured elsewhere (for example by Smart Connect).
  Future<void> applyMeasurements(Map<String, int?> latencies) async {
    if (latencies.isEmpty) return;
    for (final entry in latencies.entries) {
      _applyLatency(entry.key, entry.value);
    }
    notifyListeners();
    await StorageService.saveConfigs(_configs);
  }

  void _applyLatency(String id, int? ping) {
    final index = _configs.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final updated = _configs[index].copyWith(
      ping: ping,
      clearPing: ping == null || ping < 0,
      lastTestedAt: DateTime.now(),
    );
    _configs[index] = updated;
    if (_selectedConfig?.id == id) _selectedConfig = updated;
  }

  Future<void> _persistConfig(String id) async {
    final index = _configs.indexWhere((c) => c.id == id);
    if (index != -1) await StorageService.updateConfig(_configs[index]);
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
    return _configs
        .where(
          (c) =>
              c.name.toLowerCase().contains(lowerQuery) ||
              c.address.toLowerCase().contains(lowerQuery) ||
              c.protocolString.toLowerCase().contains(lowerQuery),
        )
        .toList();
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
