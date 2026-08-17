import 'package:flutter/foundation.dart';

import 'storage_service.dart';

enum MotionPreference { standard, reduced, off }

/// Local presentation preferences for 4SUPER.
///
/// These preferences affect only rendering and interaction feedback. They do
/// not change VPN routing, protocol settings, or network behavior.
class ExperiencePreferencesService extends ChangeNotifier {
  static final ExperiencePreferencesService _instance =
      ExperiencePreferencesService._internal();

  factory ExperiencePreferencesService() => _instance;

  ExperiencePreferencesService._internal();

  static const _motionKey = 'experience_motion_preference_v1';
  static const _compactStudioKey = 'experience_compact_studio_v1';
  static const _superTourSeenKey = 'experience_4super_tour_seen_v1';

  bool _isInitialized = false;
  MotionPreference _motionPreference = MotionPreference.standard;
  bool _compactStudio = false;
  bool _hasSeenSuperTour = false;

  bool get isInitialized => _isInitialized;
  MotionPreference get motionPreference => _motionPreference;
  bool get compactStudio => _compactStudio;
  bool get hasSeenSuperTour => _hasSeenSuperTour;
  bool get reduceMotion => _motionPreference != MotionPreference.standard;
  bool get disableMotion => _motionPreference == MotionPreference.off;

  String get motionLabel {
    switch (_motionPreference) {
      case MotionPreference.standard:
        return 'Standard';
      case MotionPreference.reduced:
        return 'Reduced';
      case MotionPreference.off:
        return 'Off';
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await StorageService.initialize();
    final storedMotion = StorageService.getSetting<String>(
      _motionKey,
      defaultValue: MotionPreference.standard.name,
    );
    _motionPreference = MotionPreference.values.firstWhere(
      (value) => value.name == storedMotion,
      orElse: () => MotionPreference.standard,
    );
    _compactStudio =
        StorageService.getSetting<bool>(
          _compactStudioKey,
          defaultValue: false,
        ) ??
        false;
    _hasSeenSuperTour =
        StorageService.getSetting<bool>(
          _superTourSeenKey,
          defaultValue: false,
        ) ??
        false;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> completeSuperTour() async {
    await initialize();
    if (_hasSeenSuperTour) return;
    _hasSeenSuperTour = true;
    await StorageService.setSetting<bool>(_superTourSeenKey, true);
    notifyListeners();
  }

  Future<void> setMotionPreference(MotionPreference value) async {
    await initialize();
    if (_motionPreference == value) return;
    _motionPreference = value;
    await StorageService.setSetting<String>(_motionKey, value.name);
    notifyListeners();
  }

  Future<void> setCompactStudio(bool value) async {
    await initialize();
    if (_compactStudio == value) return;
    _compactStudio = value;
    await StorageService.setSetting<bool>(_compactStudioKey, value);
    notifyListeners();
  }
}
