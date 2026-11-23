import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/subscription_parser.dart';
import '../services/subscription_service.dart';
import '../services/ping_service.dart';
import '../services/connection_health_service.dart';

/// State Management Provider for VPN Configurations
class ConfigProvider extends ChangeNotifier {
  static const _selectedConfigKey = 'selected_config_id_v1';
  static const _subscriptionsKey = 'subscriptions_v1';

  List<VpnConfig> _configs = [];
  bool _isLoading = false;
  String? _error;
  bool _isTestingPing = false;
  String? _testingConfigId;
  final Set<String> _testingIds = <String>{};
  int _checkCompleted = 0;
  int _checkTotal = 0;
  VpnConfig? _selectedConfig;
  List<Subscription> _subscriptions = [];
  final Set<String> _refreshingSubscriptions = <String>{};

  // Getters
  List<VpnConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTestingPing => _isTestingPing;
  String? get testingConfigId => _testingConfigId;
  VpnConfig? get selectedConfig => _selectedConfig;
  int get configCount => _configs.length;
  bool get hasConfigs => _configs.isNotEmpty;

  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);
  bool get hasSubscriptions => _subscriptions.isNotEmpty;

  /// Routes added by hand (not part of any subscription folder).
  List<VpnConfig> get manualConfigs =>
      _configs.where((c) => c.subscriptionId == null).toList();

  /// Routes of one subscription, in the provider's order.
  List<VpnConfig> configsFor(String subscriptionId) =>
      _configs.where((c) => c.subscriptionId == subscriptionId).toList();

  Subscription? subscriptionById(String id) {
    for (final subscription in _subscriptions) {
      if (subscription.id == id) return subscription;
    }
    return null;
  }

  bool isRefreshing(String subscriptionId) =>
      _refreshingSubscriptions.contains(subscriptionId);

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

      final storedSubscriptions = StorageService.getSetting<dynamic>(
        _subscriptionsKey,
      );
      if (storedSubscriptions is List) {
        _subscriptions = storedSubscriptions
            .whereType<Map<dynamic, dynamic>>()
            .map(Subscription.fromJson)
            .whereType<Subscription>()
            .toList();
      }

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

  /// Imports pasted or scanned text. A single http(s) link is treated as a
  /// subscription; anything else may be links (plain or base64) or Xray JSON.
  Future<ImportResult> importFromClipboard(String text) async {
    if (text.trim().isEmpty) {
      return ImportResult(success: false, message: 'Clipboard is empty');
    }

    final subscriptionUrl = SubscriptionService.parseUrl(text);
    if (subscriptionUrl != null) {
      return addSubscription(subscriptionUrl.toString());
    }

    final parsed = SubscriptionParser.parse(text);
    if (parsed.configs.isEmpty) {
      return ImportResult(success: false, message: parsed.emptyReason);
    }

    int imported = 0;
    int skipped = 0;
    final fresh = <VpnConfig>[];
    for (final config in parsed.configs) {
      if (StorageService.configExistsByUrl(config.rawUrl)) {
        skipped++;
      } else {
        fresh.add(config);
        imported++;
      }
    }
    if (fresh.isNotEmpty) {
      await StorageService.saveConfigs(fresh);
      _configs.insertAll(0, fresh);
    }

    notifyListeners();

    final notes = <String>[
      if (skipped > 0) '$skipped already saved',
      if (parsed.unsupported > 0) '${parsed.unsupported} unsupported',
    ];
    final suffix = notes.isEmpty ? '' : ' (${notes.join(', ')})';
    if (imported > 0) {
      return ImportResult(
        success: true,
        message: 'Imported $imported route${imported == 1 ? '' : 's'}$suffix',
        importedCount: imported,
        skippedCount: skipped,
      );
    }
    return ImportResult(
      success: false,
      message: 'All routes are already saved$suffix',
      skippedCount: skipped,
    );
  }

  /// Downloads a subscription and stores its routes in a new folder.
  Future<ImportResult> addSubscription(String url, {String? name}) async {
    final uri = SubscriptionService.parseUrl(url);
    if (uri == null) {
      return ImportResult(
        success: false,
        message: 'Enter a subscription link that starts with https://',
      );
    }
    final normalized = uri.toString();
    for (final existing in _subscriptions) {
      if (existing.url == normalized) {
        return ImportResult(
          success: false,
          message: '"${existing.name}" already uses this link',
        );
      }
    }

    final SubscriptionResponse response;
    try {
      response = await SubscriptionService.fetch(uri);
    } on SubscriptionFetchException catch (error) {
      return ImportResult(success: false, message: error.message);
    }
    if (response.routes.configs.isEmpty) {
      return ImportResult(success: false, message: response.routes.emptyReason);
    }

    final customName = name?.trim();
    final id = const Uuid().v4();
    final now = DateTime.now();
    final info = response.userInfo;
    final subscription = Subscription(
      id: id,
      url: normalized,
      name: (customName != null && customName.isNotEmpty)
          ? customName
          : (response.title ?? uri.host),
      hasCustomName: customName != null && customName.isNotEmpty,
      createdAt: now,
      updatedAt: now,
      uploadBytes: info?.upload,
      downloadBytes: info?.download,
      totalBytes: info?.total,
      expiresAt: info?.expire,
      autoUpdateHours: response.updateIntervalHours ?? 12,
    );

    final routes = [
      for (final config in response.routes.configs)
        config.copyWith(subscriptionId: id),
    ];
    await StorageService.saveConfigs(routes);
    _configs.insertAll(0, routes);
    _subscriptions = [subscription, ..._subscriptions];
    await _persistSubscriptions();
    notifyListeners();

    final unsupported = response.routes.unsupported;
    return ImportResult(
      success: true,
      message:
          'Added "${subscription.name}" with ${routes.length} '
          'route${routes.length == 1 ? '' : 's'}'
          '${unsupported > 0 ? ' ($unsupported unsupported)' : ''}',
      importedCount: routes.length,
      subscriptionId: id,
    );
  }

  /// Downloads the latest routes of a subscription. Unchanged routes keep
  /// their latency and health history; removed ones are deleted.
  Future<ImportResult> refreshSubscription(String id) async {
    final subscription = subscriptionById(id);
    if (subscription == null) {
      return ImportResult(success: false, message: 'Subscription not found');
    }
    if (!_refreshingSubscriptions.add(id)) {
      return ImportResult(success: false, message: 'Already updating');
    }
    notifyListeners();

    try {
      final response = await SubscriptionService.fetch(
        Uri.parse(subscription.url),
      );
      if (response.routes.configs.isEmpty) {
        // Never wipe a working folder because of an empty or odd response.
        final reason = response.routes.emptyReason;
        _replaceSubscription(subscription.copyWith(lastError: reason));
        await _persistSubscriptions();
        return ImportResult(success: false, message: reason);
      }

      final merge = SubscriptionMerge.apply(
        subscriptionId: id,
        existing: configsFor(id),
        incoming: response.routes.configs,
      );
      for (final removed in merge.removed) {
        await StorageService.deleteConfig(removed.id);
        await ConnectionHealthService().forget(removed.id);
        if (_selectedConfig?.id == removed.id) {
          _selectedConfig = null;
          await StorageService.setSetting<String?>(_selectedConfigKey, null);
        }
      }
      await StorageService.saveConfigs(merge.routes);

      // Keep the folder's routes together, in provider order.
      final firstIndex = _configs.indexWhere((c) => c.subscriptionId == id);
      _configs.removeWhere((c) => c.subscriptionId == id);
      final insertAt = firstIndex < 0
          ? 0
          : firstIndex.clamp(0, _configs.length);
      _configs.insertAll(insertAt, merge.routes);
      final selectedId = _selectedConfig?.id;
      if (selectedId != null) {
        for (final route in merge.routes) {
          if (route.id == selectedId) _selectedConfig = route;
        }
      }

      final info = response.userInfo;
      _replaceSubscription(
        subscription.copyWith(
          name: subscription.hasCustomName ? null : response.title,
          updatedAt: DateTime.now(),
          clearError: true,
          clearUsage: info != null,
          uploadBytes: info?.upload,
          downloadBytes: info?.download,
          totalBytes: info?.total,
          expiresAt: info?.expire,
        ),
      );
      await _persistSubscriptions();

      final changes = <String>[
        if (merge.added.isNotEmpty) '${merge.added.length} new',
        if (merge.removed.isNotEmpty) '${merge.removed.length} removed',
      ];
      return ImportResult(
        success: true,
        message: changes.isEmpty
            ? '${subscription.name} is up to date'
            : '${subscription.name} updated: ${changes.join(', ')}',
        importedCount: merge.added.length,
      );
    } on SubscriptionFetchException catch (error) {
      _replaceSubscription(subscription.copyWith(lastError: error.message));
      await _persistSubscriptions();
      return ImportResult(success: false, message: error.message);
    } finally {
      _refreshingSubscriptions.remove(id);
      notifyListeners();
    }
  }

  /// Refreshes every subscription whose automatic update is due.
  Future<void> refreshDueSubscriptions() async {
    final due = _subscriptions.where((s) => s.isDue()).toList();
    for (final subscription in due) {
      await refreshSubscription(subscription.id);
    }
  }

  Future<void> renameSubscription(String id, String name) async {
    final subscription = subscriptionById(id);
    final value = name.trim();
    if (subscription == null || value.isEmpty) return;
    _replaceSubscription(
      subscription.copyWith(name: value, hasCustomName: true),
    );
    await _persistSubscriptions();
    notifyListeners();
  }

  Future<void> setSubscriptionAutoUpdate(String id, int hours) async {
    final subscription = subscriptionById(id);
    if (subscription == null) return;
    _replaceSubscription(subscription.copyWith(autoUpdateHours: hours));
    await _persistSubscriptions();
    notifyListeners();
  }

  /// Removes a subscription folder and every route in it.
  Future<void> deleteSubscription(String id) async {
    final routes = configsFor(id);
    for (final route in routes) {
      await StorageService.deleteConfig(route.id);
      await ConnectionHealthService().forget(route.id);
    }
    _configs.removeWhere((c) => c.subscriptionId == id);
    if (_selectedConfig?.subscriptionId == id) {
      _selectedConfig = null;
      await StorageService.setSetting<String?>(_selectedConfigKey, null);
    }
    _subscriptions = _subscriptions.where((s) => s.id != id).toList();
    await _persistSubscriptions();
    notifyListeners();
  }

  void _replaceSubscription(Subscription updated) {
    _subscriptions = [
      for (final subscription in _subscriptions)
        subscription.id == updated.id ? updated : subscription,
    ];
  }

  Future<void> _persistSubscriptions() {
    return StorageService.setSetting<dynamic>(
      _subscriptionsKey,
      _subscriptions.map((s) => s.toJson()).toList(),
    );
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
      _subscriptions = [];
      await _persistSubscriptions();
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

  /// Tests every profile (or only [only]) concurrently and shows each result
  /// as it arrives.
  Future<Map<String, int?>> testAllPings({List<VpnConfig>? only}) async {
    final targets = List<VpnConfig>.from(only ?? _configs);
    if (targets.isEmpty) return <String, int?>{};
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

  /// Replaces a saved route with its edited version (same id).
  Future<bool> replaceConfig(VpnConfig updated) async {
    final index = _configs.indexWhere((c) => c.id == updated.id);
    if (index == -1) return false;
    try {
      await StorageService.updateConfig(updated);
    } catch (e) {
      _error = 'Failed to save changes: $e';
      notifyListeners();
      return false;
    }
    _configs[index] = updated;
    if (_selectedConfig?.id == updated.id) _selectedConfig = updated;
    notifyListeners();
    return true;
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

  /// Set when the import created a subscription folder.
  final String? subscriptionId;

  ImportResult({
    required this.success,
    required this.message,
    this.importedCount = 0,
    this.skippedCount = 0,
    this.subscriptionId,
  });
}
