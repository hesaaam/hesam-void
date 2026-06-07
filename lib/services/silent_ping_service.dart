import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// SilentPingService
/// Measures server latency WITHOUT exposing the server IP to the ISP.
///
/// Strategy:
///   1. HTTPS timing check — opens an HTTPS connection to a known CDN/endpoint
///      that the server operator controls. Looks exactly like normal web traffic.
///   2. DNS timing fallback — measures the time to resolve a subdomain that
///      points to the VPN server. No TCP connection is opened; ISP sees only
///      a DNS query for a generic-looking hostname.
///   3. Only uses ICMP/TCP ping when already connected through the tunnel
///      (in that case the server IP is already known to the tunnel, not ISP).
///
/// This prevents the pattern: user opens VPN app → app pings server IPs →
/// ISP flags the IP and blocks it before the user even connects.
class SilentPingService {
  static const Duration _timeout = Duration(seconds: 5);
  static const Duration _dnsTimeout = Duration(seconds: 3);

  /// Measure latency for [serverAddress] using the safest available method.
  ///
  /// [isInsideTunnel] – pass true when VPN is already connected. In that case
  /// direct TCP ping is used (server IP is already tunnelled; no leak).
  static Future<PingResult> measureLatency(
    String serverAddress,
    int serverPort, {
    bool isInsideTunnel = false,
    String? httpsCheckUrl, // optional: HTTPS endpoint on the server
  }) async {
    if (isInsideTunnel) {
      return _tcpPing(serverAddress, serverPort);
    }

    // Outside tunnel: use HTTPS timing or DNS fallback
    if (httpsCheckUrl != null) {
      final result = await _httpsPing(httpsCheckUrl);
      if (result.isSuccess) return result;
    }

    return _dnsPing(serverAddress);
  }

  /// HTTPS latency — mimics normal browser HTTPS request
  static Future<PingResult> _httpsPing(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final client = HttpClient()
        ..connectionTimeout = _timeout
        ..badCertificateCallback = (_, __, ___) => true;

      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36');
      request.headers.set('Accept', 'text/html,application/xhtml+xml');
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');

      await request.close().timeout(_timeout);
      stopwatch.stop();
      client.close();

      return PingResult(
        latencyMs: stopwatch.elapsedMilliseconds,
        method: PingMethod.https,
        isSuccess: true,
      );
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) debugPrint('[SilentPing] HTTPS ping failed: $e');
      return PingResult(
        latencyMs: -1,
        method: PingMethod.https,
        isSuccess: false,
        error: e.toString(),
      );
    }
  }

  /// DNS timing — resolves hostname, measures round-trip time
  /// Looks like a normal DNS lookup; does NOT expose server IP directly.
  static Future<PingResult> _dnsPing(String hostname) async {
    final stopwatch = Stopwatch()..start();
    try {
      await InternetAddress.lookup(hostname).timeout(_dnsTimeout);
      stopwatch.stop();
      return PingResult(
        latencyMs: stopwatch.elapsedMilliseconds,
        method: PingMethod.dns,
        isSuccess: true,
      );
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) debugPrint('[SilentPing] DNS ping failed: $e');
      return PingResult(
        latencyMs: -1,
        method: PingMethod.dns,
        isSuccess: false,
        error: e.toString(),
      );
    }
  }

  /// TCP ping — only safe to use when already inside the VPN tunnel
  static Future<PingResult> _tcpPing(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port,
          timeout: _timeout);
      stopwatch.stop();
      socket.destroy();
      return PingResult(
        latencyMs: stopwatch.elapsedMilliseconds,
        method: PingMethod.tcp,
        isSuccess: true,
      );
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) debugPrint('[SilentPing] TCP ping failed: $e');
      return PingResult(
        latencyMs: -1,
        method: PingMethod.tcp,
        isSuccess: false,
        error: e.toString(),
      );
    }
  }

  /// Batch ping multiple configs concurrently with concurrency limit.
  static Future<Map<String, PingResult>> batchPing(
    Map<String, ({String host, int port, String? httpsUrl})> targets, {
    bool isInsideTunnel = false,
    int concurrency = 3,
  }) async {
    final results = <String, PingResult>{};
    final entries = targets.entries.toList();

    for (int i = 0; i < entries.length; i += concurrency) {
      final batch = entries.skip(i).take(concurrency);
      final futures = batch.map((e) async {
        final result = await measureLatency(
          e.value.host,
          e.value.port,
          isInsideTunnel: isInsideTunnel,
          httpsCheckUrl: e.value.httpsUrl,
        );
        results[e.key] = result;
      });
      await Future.wait(futures);
      // Small jitter between batches to avoid traffic burst fingerprint
      if (i + concurrency < entries.length) {
        await Future.delayed(Duration(
          milliseconds: 100 + Random().nextInt(200),
        ));
      }
    }
    return results;
  }
}

enum PingMethod { https, dns, tcp }

class PingResult {
  final int latencyMs;   // -1 = failed
  final PingMethod method;
  final bool isSuccess;
  final String? error;

  const PingResult({
    required this.latencyMs,
    required this.method,
    required this.isSuccess,
    this.error,
  });

  String get displayLatency {
    if (!isSuccess || latencyMs < 0) return 'Timeout';
    return '${latencyMs}ms';
  }

  PingQuality get quality {
    if (!isSuccess) return PingQuality.offline;
    if (latencyMs < 100) return PingQuality.excellent;
    if (latencyMs < 250) return PingQuality.good;
    if (latencyMs < 500) return PingQuality.fair;
    return PingQuality.poor;
  }
}

enum PingQuality { excellent, good, fair, poor, offline }

extension PingQualityExtension on PingQuality {
  String get label {
    switch (this) {
      case PingQuality.excellent: return 'Excellent';
      case PingQuality.good: return 'Good';
      case PingQuality.fair: return 'Fair';
      case PingQuality.poor: return 'Poor';
      case PingQuality.offline: return 'Offline';
    }
  }
  // Returns a hex color string for UI
  String get colorHex {
    switch (this) {
      case PingQuality.excellent: return '#4CAF50';
      case PingQuality.good:      return '#8BC34A';
      case PingQuality.fair:      return '#FFC107';
      case PingQuality.poor:      return '#FF5722';
      case PingQuality.offline:   return '#9E9E9E';
    }
  }
}

// ignore: avoid_classes_with_only_static_members
class Random {
  static final _rng = dart.math.Random();
  int nextInt(int max) => _rng.nextInt(max);
}
