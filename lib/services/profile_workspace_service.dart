import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// Local-only workspace preferences for the Server Studio.
///
/// This service stores only profile identifiers; it never duplicates or uploads
/// configuration URLs, credentials, or protocol secrets.
class ProfileWorkspaceService extends ChangeNotifier {
  static final ProfileWorkspaceService _instance =
      ProfileWorkspaceService._internal();

  factory ProfileWorkspaceService() => _instance;

  ProfileWorkspaceService._internal();

  static const _favoritesKey = 'profile_workspace_favorites_v1';
  final Set<String> _favoriteIds = <String>{};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  Set<String> get favoriteIds => Set<String>.unmodifiable(_favoriteIds);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await StorageService.initialize();
    final raw = StorageService.getSetting<dynamic>(
      _favoritesKey,
      defaultValue: <dynamic>[],
    );
    if (raw is List<dynamic>) {
      _favoriteIds
        ..clear()
        ..addAll(
          raw.map((value) => value.toString()).where((id) => id.isNotEmpty),
        );
    }
    _isInitialized = true;
    notifyListeners();
  }

  bool isFavorite(String configId) => _favoriteIds.contains(configId);

  Future<void> toggleFavorite(String configId) async {
    await initialize();
    if (_favoriteIds.contains(configId)) {
      _favoriteIds.remove(configId);
    } else {
      _favoriteIds.add(configId);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> forget(String configId) async {
    await initialize();
    if (!_favoriteIds.remove(configId)) return;
    await _persist();
    notifyListeners();
  }

  Future<void> reconcile(Iterable<String> existingIds) async {
    await initialize();
    final valid = existingIds.toSet();
    final countBefore = _favoriteIds.length;
    _favoriteIds.removeWhere((id) => !valid.contains(id));
    if (_favoriteIds.length != countBefore) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() {
    return StorageService.setSetting<dynamic>(
      _favoritesKey,
      _favoriteIds.toList(growable: false),
    );
  }
}
