import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/vpn_config.dart';

/// Local, encrypted persistence for profiles and user preferences.
///
/// The AES-256 key is generated locally once and is protected by the platform
/// secure-storage provider (Android Keystore on Android). Raw configuration
/// URLs and SSH credentials never need to leave the device.
class StorageService {
  static const String _configBoxName = 'vpn_configs_v4';
  static const String _settingsBoxName = 'app_settings_v4';
  static const String _legacyConfigBoxName = 'vpn_configs';
  static const String _legacySettingsBoxName = 'app_settings';
  static const String _keyAlias = 'hesam_void_hive_key_v4';
  static const String _migrationFlag = 'legacy_migration_complete';

  static Box<VpnConfig>? _configBox;
  static Box<dynamic>? _settingsBox;
  static bool _isInitialized = false;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VpnConfigAdapter());
    }

    final cipher = HiveAesCipher(await _getOrCreateEncryptionKey());
    _configBox = await Hive.openBox<VpnConfig>(
      _configBoxName,
      encryptionCipher: cipher,
    );
    _settingsBox = await Hive.openBox<dynamic>(
      _settingsBoxName,
      encryptionCipher: cipher,
    );

    await _migrateLegacyData();
    _isInitialized = true;
  }

  static Future<Uint8List> _getOrCreateEncryptionKey() async {
    final stored = await _secureStorage.read(key: _keyAlias);
    if (stored != null) {
      final key = base64Url.decode(stored);
      if (key.length == 32) return Uint8List.fromList(key);
      throw StateError(
        'Invalid encrypted storage key. Reset local data to continue.',
      );
    }

    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _secureStorage.write(key: _keyAlias, value: base64Url.encode(key));
    return key;
  }

  /// One-time copy into encrypted boxes. Existing plaintext boxes are removed
  /// only after their data has been written to the encrypted stores.
  static Future<void> _migrateLegacyData() async {
    if (_settingsBox?.get(_migrationFlag, defaultValue: false) == true) return;

    try {
      if (await Hive.boxExists(_legacyConfigBoxName)) {
        final legacyConfigs = await Hive.openBox<VpnConfig>(
          _legacyConfigBoxName,
        );
        final values = legacyConfigs.values.toList();
        if (values.isNotEmpty) {
          await _configBox?.putAll({
            for (final config in values) config.id: config,
          });
        }
        await legacyConfigs.close();
        await Hive.deleteBoxFromDisk(_legacyConfigBoxName);
      }

      if (await Hive.boxExists(_legacySettingsBoxName)) {
        final legacySettings = await Hive.openBox<dynamic>(
          _legacySettingsBoxName,
        );
        final values = <dynamic, dynamic>{
          for (final key in legacySettings.keys) key: legacySettings.get(key),
        };
        if (values.isNotEmpty) await _settingsBox?.putAll(values);
        await legacySettings.close();
        await Hive.deleteBoxFromDisk(_legacySettingsBoxName);
      }

      await _settingsBox?.put(_migrationFlag, true);
    } catch (error) {
      // Preserve old storage for retry if migration cannot finish safely.
      if (kDebugMode)
        debugPrint('[Storage] Encrypted migration failed: $error');
      rethrow;
    }
  }

  static List<VpnConfig> getAllConfigs() => _configBox?.values.toList() ?? [];

  static VpnConfig? getConfig(String id) {
    try {
      return _configBox?.values.firstWhere((config) => config.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(VpnConfig config) async {
    await _configBox?.put(config.id, config);
  }

  static Future<void> saveConfigs(List<VpnConfig> configs) async {
    await _configBox?.putAll({for (final config in configs) config.id: config});
  }

  static Future<void> updateConfig(VpnConfig config) async =>
      saveConfig(config);

  static Future<void> deleteConfig(String id) async {
    await _configBox?.delete(id);
  }

  static Future<void> deleteAllConfigs() async {
    await _configBox?.clear();
  }

  static VpnConfig? getActiveConfig() {
    try {
      return _configBox?.values.firstWhere((config) => config.isActive);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActiveConfig(String id) async {
    final updates = {
      for (final config in getAllConfigs())
        config.id: config.copyWith(isActive: config.id == id),
    };
    await _configBox?.putAll(updates);
  }

  static Future<void> clearActiveConfig() async {
    final updates = {
      for (final config in getAllConfigs().where((config) => config.isActive))
        config.id: config.copyWith(isActive: false),
    };
    await _configBox?.putAll(updates);
  }

  static Future<void> updatePing(String id, int ping) async {
    final config = getConfig(id);
    if (config == null) return;
    await updateConfig(
      config.copyWith(ping: ping, lastTestedAt: DateTime.now()),
    );
  }

  static T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox?.get(key, defaultValue: defaultValue) as T?;
  }

  static Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox?.put(key, value);
  }

  static bool isFirstLaunch() {
    return getSetting<bool>('first_launch', defaultValue: true) ?? true;
  }

  static Future<void> markFirstLaunchComplete() {
    return setSetting('first_launch', false);
  }

  static int get configCount => _configBox?.length ?? 0;

  static bool configExistsByUrl(String url) {
    return _configBox?.values.any((config) => config.rawUrl == url) ?? false;
  }

  /// Permanently removes all local encrypted data and its wrapping key.
  static Future<void> factoryReset() async {
    await _configBox?.deleteFromDisk();
    await _settingsBox?.deleteFromDisk();
    await _secureStorage.delete(key: _keyAlias);
    _configBox = null;
    _settingsBox = null;
    _isInitialized = false;
  }

  static Future<void> close() async {
    await _configBox?.close();
    await _settingsBox?.close();
    _isInitialized = false;
  }
}
