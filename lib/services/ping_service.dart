import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';

/// Professional Ping/Latency Testing Service
/// Optimized for fast concurrent testing
class PingService {
  // Connection pool for reuse
  static final Map<String, DateTime> _lastPingTime = {};
  static final Map<String, int?> _pingCache = {};
  static const Duration _cacheExpiry = Duration(minutes: 2);

  /// Test ping for a single config with caching
  static Future<int?> testPing(VpnConfig config, {bool useCache = true}) async {
    // Check cache first for faster response
    if (useCache) {
      final cachedPing = _getCachedPing(config.id);
      if (cachedPing != null) {
        return cachedPing;
      }
    }

    try {
      final stopwatch = Stopwatch()..start();

      // For web platform, use HTTP-based ping
      if (kIsWeb) {
        return await _httpPing(config.address, config.port);
      }

      // For mobile, try socket connection with shorter timeout
      final socket = await Socket.connect(
        config.address,
        config.port,
        timeout: const Duration(seconds: 3), // Reduced from 5s to 3s
      );

      stopwatch.stop();
      await socket.close();

      final ping = stopwatch.elapsedMilliseconds;
      _cachePing(config.id, ping);

      return ping;
    } catch (e) {
      _cachePing(config.id, null);
      return null; // Connection failed
    }
  }

  /// Get cached ping if still valid
  static int? _getCachedPing(String configId) {
    final lastTime = _lastPingTime[configId];
    if (lastTime != null &&
        DateTime.now().difference(lastTime) < _cacheExpiry &&
        _pingCache.containsKey(configId)) {
      return _pingCache[configId];
    }
    return null;
  }

  /// Cache ping result
  static void _cachePing(String configId, int? ping) {
    _pingCache[configId] = ping;
    _lastPingTime[configId] = DateTime.now();
  }

  /// Clear ping cache
  static void clearCache() {
    _pingCache.clear();
    _lastPingTime.clear();
  }

  /// HTTP-based ping for web platform
  static Future<int?> _httpPing(String address, int port) async {
    try {
      final stopwatch = Stopwatch()..start();

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      try {
        final request = await client.openUrl(
          'HEAD',
          Uri.parse('https://$address:$port'),
        );
        final response = await request.close();
        await response.drain();

        stopwatch.stop();
        return stopwatch.elapsedMilliseconds;
      } finally {
        client.close();
      }
    } catch (e) {
      // Never invent a latency value when the measurement fails.
      return null;
    }
  }

  /// Tests many profiles with a bounded worker pool.
  ///
  /// [onResult] fires as soon as each profile finishes, so the UI can show
  /// results progressively instead of waiting for the slowest batch.
  static Future<Map<String, int?>> testMultiplePings(
    List<VpnConfig> configs, {
    int concurrency = 10,
    void Function(int completed, int total)? onProgress,
    void Function(VpnConfig config, int? ping)? onResult,
  }) async {
    final results = <String, int?>{};
    if (configs.isEmpty) return results;

    var next = 0;
    var completed = 0;
    Future<void> worker() async {
      while (next < configs.length) {
        final config = configs[next++];
        final ping = await testPing(config, useCache: false);
        results[config.id] = ping;
        completed++;
        onResult?.call(config, ping);
        onProgress?.call(completed, configs.length);
      }
    }

    final workers = concurrency.clamp(1, configs.length);
    await Future.wait(List.generate(workers, (_) => worker()));
    return results;
  }

  /// Fast ping test - only tests first successful connection
  static Future<int?> fastPing(VpnConfig config) async {
    try {
      final stopwatch = Stopwatch()..start();

      if (kIsWeb) {
        return await _httpPing(config.address, config.port);
      }

      // Ultra-short timeout for fast response
      final socket = await Socket.connect(
        config.address,
        config.port,
        timeout: const Duration(seconds: 2),
      );

      stopwatch.stop();
      socket.destroy(); // Faster than close()

      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return null;
    }
  }

  /// Find fastest server from list
  static Future<VpnConfig?> findFastest(List<VpnConfig> configs) async {
    if (configs.isEmpty) return null;

    // Test all concurrently and return first successful
    final completer = Completer<VpnConfig?>();
    int bestPing = 999999;
    VpnConfig? bestConfig;
    int completed = 0;

    for (final config in configs) {
      fastPing(config).then((ping) {
        completed++;
        if (ping != null && ping < bestPing) {
          bestPing = ping;
          bestConfig = config;
        }
        if (completed == configs.length && !completer.isCompleted) {
          completer.complete(bestConfig);
        }
      });
    }

    // Return after 5 seconds max or when all complete
    return Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 5), () => bestConfig),
    ]);
  }

  /// Sort configs by ping (fastest first)
  static List<VpnConfig> sortByPing(List<VpnConfig> configs) {
    final sorted = List<VpnConfig>.from(configs);
    sorted.sort((a, b) {
      if (a.ping == null && b.ping == null) return 0;
      if (a.ping == null) return 1;
      if (b.ping == null) return -1;
      return a.ping!.compareTo(b.ping!);
    });
    return sorted;
  }

  /// Get best config by ping
  static VpnConfig? getBestConfig(List<VpnConfig> configs) {
    final sorted = sortByPing(configs);
    return sorted.isNotEmpty ? sorted.first : null;
  }

  /// Stream ping updates for real-time display
  static Stream<MapEntry<String, int?>> streamPingUpdates(
    List<VpnConfig> configs, {
    Duration interval = const Duration(seconds: 30),
  }) async* {
    while (true) {
      for (final config in configs) {
        final ping = await testPing(config);
        yield MapEntry(config.id, ping);
      }
      await Future.delayed(interval);
    }
  }
}

/// Ping result with additional metadata
class PingResult {
  final String configId;
  final int? latency;
  final DateTime testedAt;
  final bool isSuccess;
  final String? error;

  PingResult({
    required this.configId,
    this.latency,
    required this.testedAt,
    required this.isSuccess,
    this.error,
  });

  factory PingResult.success(String configId, int latency) {
    return PingResult(
      configId: configId,
      latency: latency,
      testedAt: DateTime.now(),
      isSuccess: true,
    );
  }

  factory PingResult.failure(String configId, String error) {
    return PingResult(
      configId: configId,
      testedAt: DateTime.now(),
      isSuccess: false,
      error: error,
    );
  }
}
