import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Haptic Feedback Types
enum HapticType { light, medium, heavy, selection, success, warning, error }

/// Haptic Feedback Service
class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  static const String _boxName = 'haptic_settings';
  static const String _enabledKey = 'haptic_enabled';
  static const String _intensityKey = 'haptic_intensity';

  Box? _box;
  bool _isEnabled = true;
  double _intensity = 1.0; // 0.0 to 1.0

  bool get isEnabled => _isEnabled;
  double get intensity => _intensity;

  /// Initialize Haptic Service
  Future<void> initialize() async {
    if (kIsWeb) return; // No haptics on web

    _box = await Hive.openBox(_boxName);
    _isEnabled = _box?.get(_enabledKey, defaultValue: true) as bool? ?? true;
    _intensity = _box?.get(_intensityKey, defaultValue: 1.0) as double? ?? 1.0;
  }

  /// Enable/Disable haptic feedback
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _box?.put(_enabledKey, enabled);
  }

  /// Set haptic intensity (0.0 - 1.0)
  Future<void> setIntensity(double intensity) async {
    _intensity = intensity.clamp(0.0, 1.0);
    await _box?.put(_intensityKey, _intensity);
  }

  /// Trigger haptic feedback
  Future<void> trigger(HapticType type) async {
    if (!_isEnabled || kIsWeb) return;

    try {
      switch (type) {
        case HapticType.light:
          await HapticFeedback.lightImpact();
          break;
        case HapticType.medium:
          await HapticFeedback.mediumImpact();
          break;
        case HapticType.heavy:
          await HapticFeedback.heavyImpact();
          break;
        case HapticType.selection:
          await HapticFeedback.selectionClick();
          break;
        case HapticType.success:
          // Double light impact for success
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.mediumImpact();
          break;
        case HapticType.warning:
          // Medium impact for warning
          await HapticFeedback.mediumImpact();
          break;
        case HapticType.error:
          // Heavy impact pattern for error
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Haptic feedback error: $e');
      }
    }
  }

  /// Quick access methods
  Future<void> light() => trigger(HapticType.light);
  Future<void> medium() => trigger(HapticType.medium);
  Future<void> heavy() => trigger(HapticType.heavy);
  Future<void> selection() => trigger(HapticType.selection);
  Future<void> success() => trigger(HapticType.success);
  Future<void> warning() => trigger(HapticType.warning);
  Future<void> error() => trigger(HapticType.error);

  /// VPN-specific haptics
  Future<void> onConnect() async {
    if (!_isEnabled || kIsWeb) return;
    // Satisfying connect pattern
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }

  Future<void> onDisconnect() async {
    if (!_isEnabled || kIsWeb) return;
    // Disconnect pattern
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    await HapticFeedback.lightImpact();
  }

  Future<void> onConnectionEstablished() async {
    if (!_isEnabled || kIsWeb) return;
    // Celebratory pattern for successful connection
    for (int i = 0; i < 3; i++) {
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await HapticFeedback.mediumImpact();
  }

  Future<void> onError() async {
    if (!_isEnabled || kIsWeb) return;
    // Error pattern
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.heavyImpact();
  }

  Future<void> onButtonTap() async {
    if (!_isEnabled || kIsWeb) return;
    await HapticFeedback.selectionClick();
  }

  Future<void> onSliderChange() async {
    if (!_isEnabled || kIsWeb) return;
    await HapticFeedback.selectionClick();
  }

  Future<void> onSwitch() async {
    if (!_isEnabled || kIsWeb) return;
    await HapticFeedback.lightImpact();
  }

  Future<void> onDelete() async {
    if (!_isEnabled || kIsWeb) return;
    await HapticFeedback.mediumImpact();
  }

  Future<void> onRefresh() async {
    if (!_isEnabled || kIsWeb) return;
    await HapticFeedback.lightImpact();
  }
}

/// Extension for easy haptic access in widgets
extension HapticExtension on HapticService {
  /// Wrap a callback with haptic feedback
  VoidCallback? withHaptic(
    VoidCallback? callback, {
    HapticType type = HapticType.selection,
  }) {
    if (callback == null) return null;
    return () {
      trigger(type);
      callback();
    };
  }

  /// Wrap an async callback with haptic feedback
  Future<void> Function()? withHapticAsync(
    Future<void> Function()? callback, {
    HapticType type = HapticType.selection,
  }) {
    if (callback == null) return null;
    return () async {
      await trigger(type);
      await callback();
    };
  }
}
