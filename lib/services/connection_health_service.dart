import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/vpn_config.dart';
import 'storage_service.dart';

enum ConnectionEventType {
  connected,
  failed,
  dropped,
  probeSuccess,
  probeFailure,
}

enum ConnectionHealthLevel { excellent, good, caution, unavailable, unverified }

class ConnectionHealthEvent {
  final String configId;
  final ConnectionEventType type;
  final DateTime at;
  final int? latencyMs;
  final String? reason;

  const ConnectionHealthEvent({
    required this.configId,
    required this.type,
    required this.at,
    this.latencyMs,
    this.reason,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'configId': configId,
    'type': type.name,
    'at': at.toUtc().toIso8601String(),
    'latencyMs': latencyMs,
    'reason': reason,
  };

  factory ConnectionHealthEvent.fromJson(Map<dynamic, dynamic> json) {
    return ConnectionHealthEvent(
      configId: json['configId']?.toString() ?? '',
      type: ConnectionEventType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => ConnectionEventType.failed,
      ),
      at:
          DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      latencyMs: json['latencyMs'] as int?,
      reason: json['reason']?.toString(),
    );
  }
}

class ConnectionHealthSnapshot {
  final int score;
  final ConnectionHealthLevel level;
  final int attempts;
  final int successes;
  final int failures;
  final int? latestLatencyMs;
  final DateTime? lastCheckedAt;
  final List<String> reasons;

  const ConnectionHealthSnapshot({
    required this.score,
    required this.level,
    required this.attempts,
    required this.successes,
    required this.failures,
    required this.latestLatencyMs,
    required this.lastCheckedAt,
    required this.reasons,
  });

  bool get isVerified => attempts > 0;
  double get successRate => attempts == 0 ? 0 : successes / attempts;
  String get scoreLabel => '$score/100';
  String get latencyLabel =>
      latestLatencyMs == null ? 'Not measured' : '$latestLatencyMs ms';
  String get levelLabel {
    switch (level) {
      case ConnectionHealthLevel.excellent:
        return 'Excellent path health';
      case ConnectionHealthLevel.good:
        return 'Healthy path';
      case ConnectionHealthLevel.caution:
        return 'Use with caution';
      case ConnectionHealthLevel.unavailable:
        return 'Recently unreliable';
      case ConnectionHealthLevel.unverified:
        return 'Needs a first check';
    }
  }
}

/// Local-only, explainable connection intelligence.
///
/// It never uploads a profile URL, credential, IP history, or diagnostic event.
/// The score is rule-based so every recommendation can be explained in the UI.
class ConnectionHealthService extends ChangeNotifier {
  static final ConnectionHealthService _instance =
      ConnectionHealthService._internal();
  factory ConnectionHealthService() => _instance;
  ConnectionHealthService._internal();

  static const _storageKey = 'connection_health_events_v1';
  static const _retention = Duration(days: 14);
  static const _maxEventsPerProfile = 30;

  final List<ConnectionHealthEvent> _events = <ConnectionHealthEvent>[];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await StorageService.initialize();
    final stored = StorageService.getSetting<dynamic>(
      _storageKey,
      defaultValue: <dynamic>[],
    );
    if (stored is List<dynamic>) {
      for (final item in stored.whereType<Map<dynamic, dynamic>>()) {
        final event = ConnectionHealthEvent.fromJson(item);
        if (event.configId.isNotEmpty) _events.add(event);
      }
    }
    _prune();
    _isInitialized = true;
    await _persist();
    notifyListeners();
  }

  List<ConnectionHealthEvent> eventsFor(String configId) {
    return _events.where((event) => event.configId == configId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  ConnectionHealthSnapshot snapshotFor(String configId) {
    final events = eventsFor(configId);
    if (events.isEmpty) {
      return const ConnectionHealthSnapshot(
        score: 50,
        level: ConnectionHealthLevel.unverified,
        attempts: 0,
        successes: 0,
        failures: 0,
        latestLatencyMs: null,
        lastCheckedAt: null,
        reasons: <String>[
          'No local connection data yet. Run a latency test or connect once.',
        ],
      );
    }

    final successful = events.where((event) {
      return event.type == ConnectionEventType.connected ||
          event.type == ConnectionEventType.probeSuccess;
    }).toList();
    final failed = events.where((event) {
      return event.type == ConnectionEventType.failed ||
          event.type == ConnectionEventType.probeFailure ||
          event.type == ConnectionEventType.dropped;
    }).toList();
    final attempts = successful.length + failed.length;
    final latestLatency = successful
        .where((event) => event.latencyMs != null && event.latencyMs! >= 0)
        .map((event) => event.latencyMs!)
        .cast<int?>()
        .firstOrNull;

    final successComponent = attempts == 0
        ? 0.0
        : successful.length / attempts * 50;
    final latencyComponent = latestLatency == null
        ? 8.0
        : ((900 - latestLatency).clamp(0, 900) / 900) * 25;
    final recentHours =
        DateTime.now().difference(events.first.at).inMinutes / 60;
    final recencyComponent = (20 - recentHours.clamp(0, 20)) / 20 * 15;
    final drops = events
        .where((event) => event.type == ConnectionEventType.dropped)
        .length;
    final dropPenalty = math.min(15, drops * 5);
    final score =
        (10 +
                successComponent +
                latencyComponent +
                recencyComponent -
                dropPenalty)
            .round()
            .clamp(0, 100);

    final level = score >= 80
        ? ConnectionHealthLevel.excellent
        : score >= 62
        ? ConnectionHealthLevel.good
        : score >= 40
        ? ConnectionHealthLevel.caution
        : ConnectionHealthLevel.unavailable;
    final reasons = <String>[
      '${successful.length}/$attempts successful local checks',
      if (latestLatency != null) 'Latest measured latency: $latestLatency ms',
      if (events.first.type == ConnectionEventType.failed ||
          events.first.type == ConnectionEventType.probeFailure)
        'Latest result was a failure${events.first.reason == null ? '' : ': ${events.first.reason}'}',
      if (drops > 0)
        '$drops unexpected tunnel drop${drops == 1 ? '' : 's'} recorded',
    ];

    return ConnectionHealthSnapshot(
      score: score,
      level: level,
      attempts: attempts,
      successes: successful.length,
      failures: failed.length,
      latestLatencyMs: latestLatency,
      lastCheckedAt: events.first.at,
      reasons: reasons,
    );
  }

  VpnConfig? recommend(List<VpnConfig> configs) {
    final verified = configs
        .where((config) => snapshotFor(config.id).isVerified)
        .toList();
    if (verified.isEmpty) return null;
    verified.sort((left, right) {
      final score = snapshotFor(
        right.id,
      ).score.compareTo(snapshotFor(left.id).score);
      if (score != 0) return score;
      return (left.ping ?? 999999).compareTo(right.ping ?? 999999);
    });
    return verified.first;
  }

  Future<void> recordConnected(String configId, {int? latencyMs}) {
    return _record(
      configId,
      ConnectionEventType.connected,
      latencyMs: latencyMs,
    );
  }

  Future<void> recordFailure(String configId, String reason) {
    return _record(
      configId,
      ConnectionEventType.failed,
      reason: _safeReason(reason),
    );
  }

  Future<void> recordDrop(String configId, {String? reason}) {
    return _record(
      configId,
      ConnectionEventType.dropped,
      reason: _safeReason(reason),
    );
  }

  Future<void> recordProbe(String configId, int? latencyMs) {
    if (latencyMs != null && latencyMs >= 0) {
      return _record(
        configId,
        ConnectionEventType.probeSuccess,
        latencyMs: latencyMs,
      );
    }
    return _record(
      configId,
      ConnectionEventType.probeFailure,
      reason: 'Latency test failed',
    );
  }

  Future<void> forget(String configId) async {
    _events.removeWhere((event) => event.configId == configId);
    await _persist();
    notifyListeners();
  }

  Future<void> _record(
    String configId,
    ConnectionEventType type, {
    int? latencyMs,
    String? reason,
  }) async {
    if (configId.isEmpty) return;
    await initialize();
    _events.add(
      ConnectionHealthEvent(
        configId: configId,
        type: type,
        at: DateTime.now(),
        latencyMs: latencyMs,
        reason: reason,
      ),
    );
    _trimProfile(configId);
    _prune();
    await _persist();
    notifyListeners();
  }

  void _trimProfile(String configId) {
    final profileEvents = eventsFor(configId);
    if (profileEvents.length <= _maxEventsPerProfile) return;
    final removable = profileEvents.skip(_maxEventsPerProfile).toSet();
    _events.removeWhere(removable.contains);
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(_retention);
    _events.removeWhere((event) => event.at.isBefore(cutoff));
  }

  Future<void> _persist() {
    return StorageService.setSetting<dynamic>(
      _storageKey,
      _events.map((event) => event.toJson()).toList(),
    );
  }

  String _safeReason(String? value) {
    if (value == null || value.trim().isEmpty) return 'Connection failed';
    // Never persist raw configuration URLs or credential-like strings in local history.
    final sanitized = value
        .replaceAll(
          RegExp(r'(vless|vmess|trojan|ss|ssh)://\S+', caseSensitive: false),
          '[redacted config]',
        )
        .replaceAll(
          RegExp(r'password\s*[:=]\s*\S+', caseSensitive: false),
          'password=[redacted]',
        );
    return sanitized.substring(0, math.min(sanitized.length, 160));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
