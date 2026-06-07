import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// AdvancedFragmentService
/// Extends basic TLS-hello fragmentation with:
///   1. Traffic Shaping  — adds randomised inter-packet jitter to break
///      timing-based DPI fingerprints used by GFW 2024+ probes.
///   2. Packet-size Normalisation — pads or splits packets so the size
///      distribution looks like normal HTTPS browsing, not VPN traffic.
///   3. Four configurable profiles matching real traffic archetypes.
class AdvancedFragmentService {
  static final _rng = math.Random.secure();

  // ─── Public API ────────────────────────────────────────────────

  /// Build an Xray-compatible `fragment` JSON block for the given [profile].
  /// Inject this into the outbound streamSettings.sockopt of your V2Ray config.
  static Map<String, dynamic> buildFragmentConfig(TrafficProfile profile) {
    final params = _profileParams(profile);
    return {
      'packets': params.packets,
      'length': '${params.minLen}-${params.maxLen}',
      'interval': '${params.minInterval}-${params.maxInterval}',
    };
  }

  /// Build the full sockopt block with fragment + noise settings.
  static Map<String, dynamic> buildSockopt(TrafficProfile profile) {
    final frag = buildFragmentConfig(profile);
    return {
      'fragment': frag,
      'noiseBasedSettings': {
        'delay': _jitterRange(profile),
        'packetSize': _sizeRange(profile),
        'noiseProbability': _noiseProbability(profile),
      },
    };
  }

  /// Inject fragment + sockopt into an existing V2Ray outbound JSON map.
  /// [outbound] must be the decoded JSON map of a single outbound.
  static Map<String, dynamic> injectIntoOutbound(
    Map<String, dynamic> outbound,
    TrafficProfile profile,
  ) {
    final Map<String, dynamic> streamSettings =
        Map<String, dynamic>.from(outbound['streamSettings'] as Map? ?? {});

    final sockopt = Map<String, dynamic>.from(
        streamSettings['sockopt'] as Map? ?? {});
    sockopt.addAll(buildSockopt(profile));
    streamSettings['sockopt'] = sockopt;
    outbound['streamSettings'] = streamSettings;

    if (kDebugMode) {
      debugPrint('[AdvancedFragment] Injected profile: ${profile.name}');
      debugPrint('[AdvancedFragment] sockopt: $sockopt');
    }

    return outbound;
  }

  /// Apply a random jitter delay in microseconds to simulate human browsing.
  /// Call this between write operations when building a custom tunnel.
  static Future<void> applyJitter(TrafficProfile profile) async {
    final params = _profileParams(profile);
    final delayMs = params.minInterval +
        _rng.nextInt(params.maxInterval - params.minInterval + 1);
    await Future.delayed(Duration(milliseconds: delayMs));
  }

  // ─── Profile Definitions ────────────────────────────────────────

  static _ProfileParams _profileParams(TrafficProfile profile) {
    switch (profile) {
      case TrafficProfile.normalBrowsing:
        // Mimics typical Chrome HTTPS browsing:
        // medium-sized TLS records, moderate jitter
        return _ProfileParams(
          packets: 'tlshello',
          minLen: 100,
          maxLen: 800,
          minInterval: 10,
          maxInterval: 50,
        );

      case TrafficProfile.videoStream:
        // Mimics YouTube / Aparat streaming:
        // large consistent packets, low jitter (steady bitrate)
        return _ProfileParams(
          packets: 'tlshello',
          minLen: 1200,
          maxLen: 1400,
          minInterval: 1,
          maxInterval: 8,
        );

      case TrafficProfile.videoCall:
        // Mimics WebRTC (Skype, Google Meet):
        // small packets, very low jitter, high frequency
        return _ProfileParams(
          packets: 'tlshello',
          minLen: 50,
          maxLen: 200,
          minInterval: 5,
          maxInterval: 20,
        );

      case TrafficProfile.stealth:
        // Maximum evasion: highly randomised size + timing
        return _ProfileParams(
          packets: 'tlshello',
          minLen: 1,
          maxLen: 500,
          minInterval: 1,
          maxInterval: 100,
        );
    }
  }

  static String _jitterRange(TrafficProfile profile) {
    final p = _profileParams(profile);
    return '${p.minInterval}-${p.maxInterval}';
  }

  static String _sizeRange(TrafficProfile profile) {
    final p = _profileParams(profile);
    return '${p.minLen}-${p.maxLen}';
  }

  static double _noiseProbability(TrafficProfile profile) {
    switch (profile) {
      case TrafficProfile.normalBrowsing: return 0.1;
      case TrafficProfile.videoStream:   return 0.05;
      case TrafficProfile.videoCall:     return 0.05;
      case TrafficProfile.stealth:       return 0.3;
    }
  }
}

/// Traffic profile presets — each mimics a real-world traffic pattern
/// to evade DPI behavioral fingerprinting.
enum TrafficProfile {
  normalBrowsing,
  videoStream,
  videoCall,
  stealth;

  String get displayName {
    switch (this) {
      case TrafficProfile.normalBrowsing: return 'Normal Browsing';
      case TrafficProfile.videoStream:   return 'Video Streaming';
      case TrafficProfile.videoCall:     return 'Video Call';
      case TrafficProfile.stealth:       return 'Maximum Stealth';
    }
  }

  String get description {
    switch (this) {
      case TrafficProfile.normalBrowsing:
        return 'Mimics Chrome HTTPS browsing. Best for daily use.';
      case TrafficProfile.videoStream:
        return 'Mimics YouTube/Aparat streams. Best for fast, stable connections.';
      case TrafficProfile.videoCall:
        return 'Mimics WebRTC calls. Low-latency for real-time apps.';
      case TrafficProfile.stealth:
        return 'Maximum randomisation. Best when other profiles are blocked.';
    }
  }

  String get iconAsset {
    switch (this) {
      case TrafficProfile.normalBrowsing: return 'assets/icons/profile_browse.png';
      case TrafficProfile.videoStream:   return 'assets/icons/profile_stream.png';
      case TrafficProfile.videoCall:     return 'assets/icons/profile_call.png';
      case TrafficProfile.stealth:       return 'assets/icons/profile_stealth.png';
    }
  }
}

class _ProfileParams {
  final String packets;
  final int minLen;
  final int maxLen;
  final int minInterval; // ms
  final int maxInterval; // ms

  const _ProfileParams({
    required this.packets,
    required this.minLen,
    required this.maxLen,
    required this.minInterval,
    required this.maxInterval,
  });
}
