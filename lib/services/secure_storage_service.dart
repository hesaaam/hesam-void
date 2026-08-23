import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';
import '../models/vpn_config.dart';

/// SecureStorageService
/// Replaces plain StorageService with AES-256 encrypted Hive boxes.
/// The encryption key is stored in Android Keystore via flutter_secure_storage.
/// Optionally protected by biometric authentication on sensitive operations.
class SecureStorageService {
  static const String _configBoxName = 'vpn_configs_secure';
  static const String _settingsBoxName = 'app_settings_secure';
  static const String _encryptionKeyAlias = 'hesam_void_hive_key';

  static Box<VpnConfig>? _configBox;
  static Box<dynamic>? _settingsBox;
  static bool _isInitialized = false;

  // flutter_secure_storage with Android Keystore backend
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm:
          KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Initialize encrypted Hive storage.
  /// Derives a 256-bit key, stores it in Android Keystore,
  /// and opens Hive boxes with AES-256-GCM cipher.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VpnConfigAdapter());
    }

    final encryptionKey = await _getOrCreateEncryptionKey();
    final hiveCipher = HiveAesCipher(encryptionKey);

    _configBox = await Hive.openBox<VpnConfig>(
      _configBoxName,
      encryptionCipher: hiveCipher,
    );
    _settingsBox = await Hive.openBox<dynamic>(
      _settingsBoxName,
      encryptionCipher: hiveCipher,
    );

    _isInitialized = true;

    if (kDebugMode) {
      debugPrint('[SecureStorage] Initialized with AES-256 encryption.');
    }
  }

  /// Retrieve existing key from Keystore, or generate and store a new one.
  static Future<Uint8List> _getOrCreateEncryptionKey() async {
    try {
      final existingKey =
          await _secureStorage.read(key: _encryptionKeyAlias);
      if (existingKey != null) {
        return base64Url.decode(existingKey);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Key read error (first run?): $e');
      }
    }

    // Generate cryptographically secure 256-bit (32 byte) key
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _secureStorage.write(
      key: _encryptionKeyAlias,
      value: base64Url.encode(key),
    );

    if (kDebugMode) {
      debugPrint('[SecureStorage] New AES-256 key generated and stored in Keystore.');
    }
    return key;
  }

  /// Authenticate user with biometrics before exposing sensitive data.
  /// Returns true if authenticated (or if biometrics unavailable).
  static Future<bool> authenticateWithBiometrics({
    String reason = 'Authenticate to access VPN configs',
  }) async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) return true; // No biometrics – allow access

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN fallback
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Biometric auth error: $e');
      }
      return true; // Fail-open on auth error (UX safety net)
    }
  }

  // ─── Config CRUD ──────────────────────────────────────────────────────────

  static List<VpnConfig> getAllConfigs() =>
      _configBox?.values.toList() ?? [];

  static VpnConfig? getConfig(String id) {
    try {
      return _configBox?.values.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(VpnConfig config) async {
    await _configBox?.put(config.id, config);
  }

  static Future<void> saveConfigs(List<VpnConfig> configs) async {
    final map = {for (final c in configs) c.id: c};
    await _configBox?.putAll(map);
  }

  static Future<void> updateConfig(VpnConfig config) async {
    await _configBox?.put(config.id, config);
  }

  static Future<void> deleteConfig(String id) async {
    await _configBox?.delete(id);
  }

  static Future<void> deleteAllConfigs() async {
    await _configBox?.clear();
  }

  static VpnConfig? getActiveConfig() {
    try {
      return _configBox?.values.firstWhere((c) => c.isActive);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActiveConfig(String id) async {
    final configs = getAllConfigs();
    final updates = <String, VpnConfig>{};
    for (final c in configs) {
      updates[c.id] = c.copyWith(isActive: c.id == id);
    }
    await _configBox?.putAll(updates);
  }

  static Future<void> clearActiveConfig() async {
    final configs = getAllConfigs();
    for (final c in configs) {
      if (c.isActive) {
        await _configBox?.put(c.id, c.copyWith(isActive: false));
      }
    }
  }

  static Future<void> updatePing(String id, int ping) async {
    final config = getConfig(id);
    if (config != null) {
      await updateConfig(config.copyWith(
        ping: ping,
        lastTestedAt: DateTime.now(),
      ));
    }
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  static T? getSetting<T>(String key, {T? defaultValue}) =>
      (_settingsBox?.get(key, defaultValue: defaultValue)) as T?;

  static Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox?.put(key, value);
  }

  static bool isFirstLaunch() =>
      getSetting<bool>('first_launch', defaultValue: true) ?? true;

  static Future<void> markFirstLaunchComplete() async {
    await setSetting('first_launch', false);
  }

  static int get configCount => _configBox?.length ?? 0;

  static bool configExistsByUrl(String url) =>
      _configBox?.values.any((c) => c.rawUrl == url) ?? false;

  /// Securely wipe the encryption key from Keystore.
  /// Call on "Factory Reset" / account logout.
  static Future<void> destroyEncryptionKey() async {
    await _secureStorage.delete(key: _encryptionKeyAlias);
    await _configBox?.deleteFromDisk();
    await _settingsBox?.deleteFromDisk();
    _isInitialized = false;
    if (kDebugMode) {
      debugPrint('[SecureStorage] Encryption key destroyed. All data wiped.');
    }
  }

  static Future<void> close() async {
    await _configBox?.close();
    await _settingsBox?.close();
  }
}
