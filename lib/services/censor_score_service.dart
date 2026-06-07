import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'silent_ping_service.dart';
import '../models/vpn_config.dart';

/// CensorScoreService
/// Computes a 1–10 "Censor Score" for each server indicating how reliable
/// it is under current Iranian censorship conditions.
///
/// Score factors (weighted):
///   - Recent latency history   (40%) — high/inconsistent = DPI throttling
///   - Dropout rate             (30%) — frequent drops = pattern detected
///   - Protocol success rate    (20%) — blocks on specific protocols
///   - Last successful connect  (10%) — recency bonus
///
/// Score 8-10 → 🟢 Safe & fast
/// Score 5-7  → 🟡 Usable but watch
/// Score 1-4  → 🔴 Likely blocked
class CensorScoreService extends ChangeNotifier {
  static final CensorScoreService _instance = CensorScoreService._internal();
  factory CensorScoreService() => _instance;
  CensorScoreService._internal();

  // configId → score history
  final Map<String, _ScoreState> _scores = {};

  // ─── Public API ────────────────────────────────────────────────

  /// Get current score (1-10) for a config. Returns null if no data yet.
  double? getScore(String configId) => _scores[configId]?.score;

  /// Get score label + emoji
  ScoreLevel getLevel(String configId) {
    final score = getScore(configId);
    if (score == null) return ScoreLevel.unknown;
    if (score >= 8) return ScoreLevel.safe;
    if (score >= 5) return ScoreLevel.caution;
    return ScoreLevel.blocked;
  }

  /// Record a successful connection event
  void recordSuccess(String configId, int latencyMs) {
    final state = _getOrCreate(configId);
    state.recordSuccess(latencyMs);
    _recalculate(configId);
    notifyListeners();
  }

  /// Record a connection dropout (unexpected disconnect)
  void recordDropout(String configId) {
    final state = _getOrCreate(configId);
    state.recordDropout();
    _recalculate(configId);
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[CensorScore] Dropout recorded for $configId. New score: ${getScore(configId)?.toStringAsFixed(1)}');
    }
  }

  /// Record a failed connection attempt
  void recordFailure(String configId) {
    final state = _getOrCreate(configId);
    state.recordFailure();
    _recalculate(configId);
    notifyListeners();
  }

  /// Run a background scoring cycle for all saved configs.
  /// Should be called on app resume or after a fixed interval.
  Future<void> refreshAllScores() async {
    final configs = SecureStorageService.getAllConfigs();
    if (configs.isEmpty) return;

    // Build target map for silent ping
    final targets = <String, ({String host, int port, String? httpsUrl})>{};
    for (final c in configs) {
      targets[c.id] = (host: c.address, port: c.port, httpsUrl: null);
    }

    final pingResults = await SilentPingService.batchPing(
      targets,
      isInsideTunnel: false,
    );

    for (final entry in pingResults.entries) {
      final result = entry.value;
      if (result.isSuccess) {
        recordSuccess(entry.key, result.latencyMs);
      } else {
        // Don’t count DNS failures as drops — could be legitimate DNS issue
        if (result.method != PingMethod.dns) {
          recordFailure(entry.key);
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[CensorScore] Refresh complete for ${configs.length} configs.');
    }
  }

  /// Sort configs by score (highest first)
  List<VpnConfig> sortByScore(List<VpnConfig> configs) {
    return List<VpnConfig>.from(configs)
      ..sort((a, b) {
        final sa = getScore(a.id) ?? 5.0;
        final sb = getScore(b.id) ?? 5.0;
        return sb.compareTo(sa);
      });
  }

  // ─── Internal scoring logic ────────────────────────────────────────

  _ScoreState _getOrCreate(String id) =>
      _scores.putIfAbsent(id, () => _ScoreState());

  void _recalculate(String configId) {
    final state = _scores[configId];
    if (state == null) return;

    // 1. Latency score (40%) — lower & consistent = better
    double latencyScore = 10.0;
    if (state.latencyHistory.isNotEmpty) {
      final avg = state.avgLatency;
      final jitter = state.latencyJitter;
      if (avg < 100 && jitter < 30) {
        latencyScore = 10.0;
      } else if (avg < 200 && jitter < 60) {
        latencyScore = 8.0;
      } else if (avg < 400) {
        latencyScore = 6.0;
      } else if (avg < 800) {
        latencyScore = 4.0;
      } else {
        latencyScore = 2.0;
      }
      // Jitter penalty
      latencyScore -= math.min(3.0, jitter / 50);
    }

    // 2. Dropout score (30%)
    double dropoutScore = 10.0;
    if (state.totalAttempts > 0) {
      final dropRate = state.dropouts / state.totalAttempts;
      dropoutScore = 10.0 * (1.0 - dropRate * 2).clamp(0.0, 1.0);
    }

    // 3. Success rate score (20%)
    double successScore = 5.0; // neutral when no data
    if (state.totalAttempts > 0) {
      final rate = state.successCount / state.totalAttempts;
      successScore = 10.0 * rate;
    }

    // 4. Recency score (10%) — bonus if last success was recent
    double recencyScore = 5.0;
    if (state.lastSuccessAt != null) {
      final ago = DateTime.now().difference(state.lastSuccessAt!).inMinutes;
      if (ago < 10) recencyScore = 10.0;
      else if (ago < 60) recencyScore = 8.0;
      else if (ago < 360) recencyScore = 6.0;
      else recencyScore = 3.0;
    }

    state.score = (
      latencyScore * 0.40 +
      dropoutScore * 0.30 +
      successScore * 0.20 +
      recencyScore * 0.10
    ).clamp(1.0, 10.0);
  }
}

class _ScoreState {
  double score = 5.0;
  final List<int> latencyHistory = []; // last 20 samples
  int successCount = 0;
  int dropouts = 0;
  int failures = 0;
  DateTime? lastSuccessAt;

  int get totalAttempts => successCount + dropouts + failures;

  void recordSuccess(int latencyMs) {
    successCount++;
    lastSuccessAt = DateTime.now();
    latencyHistory.add(latencyMs);
    if (latencyHistory.length > 20) latencyHistory.removeAt(0);
  }

  void recordDropout() => dropouts++;
  void recordFailure() => failures++;

  double get avgLatency {
    if (latencyHistory.isEmpty) return 0;
    return latencyHistory.reduce((a, b) => a + b) / latencyHistory.length;
  }

  double get latencyJitter {
    if (latencyHistory.length < 2) return 0;
    final avg = avgLatency;
    final variance = latencyHistory
        .map((v) => math.pow(v - avg, 2))
        .reduce((a, b) => a + b) / latencyHistory.length;
    return math.sqrt(variance);
  }
}

enum ScoreLevel { safe, caution, blocked, unknown }

extension ScoreLevelExtension on ScoreLevel {
  String get emoji {
    switch (this) {
      case ScoreLevel.safe:    return '🟢';
      case ScoreLevel.caution: return '🟡';
      case ScoreLevel.blocked: return '🔴';
      case ScoreLevel.unknown: return '⚪';
    }
  }
  String get label {
    switch (this) {
      case ScoreLevel.safe:    return 'Safe & Fast';
      case ScoreLevel.caution: return 'Use with Care';
      case ScoreLevel.blocked: return 'Likely Blocked';
      case ScoreLevel.unknown: return 'No Data Yet';
    }
  }
  String get colorHex {
    switch (this) {
      case ScoreLevel.safe:    return '#4CAF50';
      case ScoreLevel.caution: return '#FFC107';
      case ScoreLevel.blocked: return '#F44336';
      case ScoreLevel.unknown: return '#9E9E9E';
    }
  }
}
