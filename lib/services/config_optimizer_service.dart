import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Smart Config Optimizer Service
/// Optimizes V2Ray configs for better speed and lower ping
class ConfigOptimizerService {
  static final ConfigOptimizerService _instance = ConfigOptimizerService._internal();
  factory ConfigOptimizerService() => _instance;
  ConfigOptimizerService._internal();

  // Settings model
  OptimizerSettings _settings = OptimizerSettings();
  
  // Getters and setters for settings
  OptimizerSettings get settings => _settings;
  set settings(OptimizerSettings value) => _settings = value;

  /// Optimization settings
  static const Map<String, dynamic> defaultOptimizations = {
    'mtu': 1400,
    'buffer_size': 4096,
    'mux_enabled': true,
    'mux_concurrency': 8,
    'dns_strategy': 'UseIPv4',
    'domain_strategy': 'AsIs',
    'tcp_fast_open': true,
    'tcp_keep_alive': 30,
    'tcp_no_delay': true,
  };

  /// Best DNS servers for Iran
  static const List<Map<String, dynamic>> optimizedDNS = [
    {'address': '1.1.1.1', 'name': 'Cloudflare', 'priority': 1},
    {'address': '8.8.8.8', 'name': 'Google', 'priority': 2},
    {'address': '9.9.9.9', 'name': 'Quad9', 'priority': 3},
    {'address': '208.67.222.222', 'name': 'OpenDNS', 'priority': 4},
  ];

  /// DNS over HTTPS endpoints
  static const List<String> dohServers = [
    'https://1.1.1.1/dns-query',
    'https://dns.google/dns-query',
    'https://dns.quad9.net/dns-query',
  ];

  /// Optimize a V2Ray JSON configuration
  String optimizeConfig(String configJson, {OptimizationLevel level = OptimizationLevel.balanced}) {
    try {
      Map<String, dynamic> config = jsonDecode(configJson);
      
      // Apply optimizations based on level
      config = _optimizeDNS(config, level);
      config = _optimizeInbound(config, level);
      config = _optimizeOutbound(config, level);
      config = _optimizeRouting(config, level);
      config = _addMux(config, level);
      
      return jsonEncode(config);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ConfigOptimizer] Error optimizing config: $e');
      }
      return configJson; // Return original if optimization fails
    }
  }

  /// Optimize DNS settings
  Map<String, dynamic> _optimizeDNS(Map<String, dynamic> config, OptimizationLevel level) {
    List<dynamic> servers = [];
    
    switch (level) {
      case OptimizationLevel.speed:
        // Use fastest DNS
        servers = ['1.1.1.1', '8.8.8.8'];
        break;
      case OptimizationLevel.security:
        // Use DoH
        servers = [
          {
            'address': 'https://1.1.1.1/dns-query',
            'domains': ['geosite:geolocation-!cn'],
          },
          '1.1.1.1',
        ];
        break;
      case OptimizationLevel.balanced:
      default:
        servers = ['1.1.1.1', '8.8.8.8', '9.9.9.9'];
    }

    config['dns'] = {
      'servers': servers,
      'queryStrategy': 'UseIPv4',
      'disableCache': false,
      'disableFallback': false,
      'tag': 'dns-out',
    };

    return config;
  }

  /// Optimize inbound settings
  Map<String, dynamic> _optimizeInbound(Map<String, dynamic> config, OptimizationLevel level) {
    if (config['inbounds'] != null && config['inbounds'] is List) {
      for (var inbound in config['inbounds']) {
        if (inbound is Map) {
          inbound['sniffing'] = {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'metadataOnly': false,
          };
        }
      }
    }
    return config;
  }

  /// Optimize outbound settings
  Map<String, dynamic> _optimizeOutbound(Map<String, dynamic> config, OptimizationLevel level) {
    if (config['outbounds'] != null && config['outbounds'] is List) {
      for (var outbound in config['outbounds']) {
        if (outbound is Map && outbound['streamSettings'] != null) {
          var stream = outbound['streamSettings'] as Map<String, dynamic>;
          
          // TCP optimizations
          if (stream['network'] == 'tcp' || stream['network'] == null) {
            stream['sockopt'] = {
              'mark': 255,
              'tcpFastOpen': level == OptimizationLevel.speed,
              'tcpKeepAliveInterval': 30,
              'tcpNoDelay': true,
              'domainStrategy': 'UseIPv4',
            };
          }
          
          // WebSocket optimizations
          if (stream['network'] == 'ws') {
            stream['wsSettings'] ??= {};
            stream['wsSettings']['headers'] ??= {};
            // Add browser-like headers
            stream['wsSettings']['headers']['User-Agent'] = 
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
          }
          
          // gRPC optimizations
          if (stream['network'] == 'grpc') {
            stream['grpcSettings'] ??= {};
            stream['grpcSettings']['multiMode'] = true;
            stream['grpcSettings']['idle_timeout'] = 60;
            stream['grpcSettings']['health_check_timeout'] = 20;
          }
        }
      }
    }
    return config;
  }

  /// Optimize routing
  Map<String, dynamic> _optimizeRouting(Map<String, dynamic> config, OptimizationLevel level) {
    config['routing'] = {
      'domainStrategy': 'IPIfNonMatch',
      'domainMatcher': 'hybrid',
      'rules': [
        // Block ads and trackers
        {
          'type': 'field',
          'domain': ['geosite:category-ads-all'],
          'outboundTag': 'blocked',
        },
        // Direct connection for private IPs
        {
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        },
        // Route DNS queries
        {
          'type': 'field',
          'port': '53',
          'outboundTag': 'dns-out',
        },
        // Default: proxy
        {
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': 'proxy',
        },
      ],
    };
    
    return config;
  }

  /// Add Mux (multiplexing) for better performance
  Map<String, dynamic> _addMux(Map<String, dynamic> config, OptimizationLevel level) {
    if (level == OptimizationLevel.speed || level == OptimizationLevel.balanced) {
      if (config['outbounds'] != null && config['outbounds'] is List) {
        for (var outbound in config['outbounds']) {
          if (outbound is Map && 
              (outbound['protocol'] == 'vmess' || 
               outbound['protocol'] == 'vless' ||
               outbound['protocol'] == 'trojan')) {
            outbound['mux'] = {
              'enabled': true,
              'concurrency': level == OptimizationLevel.speed ? 16 : 8,
              'xudpConcurrency': 16,
              'xudpProxyUDP443': 'reject',
            };
          }
        }
      }
    }
    return config;
  }

  /// Test DNS server latency
  Future<Map<String, int>> testDNSLatency() async {
    Map<String, int> results = {};
    
    for (var dns in optimizedDNS) {
      try {
        final stopwatch = Stopwatch()..start();
        await InternetAddress.lookup('google.com', type: InternetAddressType.IPv4);
        stopwatch.stop();
        results[dns['address']] = stopwatch.elapsedMilliseconds;
      } catch (e) {
        results[dns['address']] = -1;
      }
    }
    
    return results;
  }

  /// Get best DNS based on latency
  Future<String> getBestDNS() async {
    final latencies = await testDNSLatency();
    String bestDNS = '1.1.1.1';
    int bestLatency = 9999;
    
    latencies.forEach((dns, latency) {
      if (latency > 0 && latency < bestLatency) {
        bestLatency = latency;
        bestDNS = dns;
      }
    });
    
    return bestDNS;
  }
}

/// Optimization levels
enum OptimizationLevel {
  speed,    // Maximum speed, less security
  balanced, // Balance between speed and security
  security, // Maximum security, may be slower
}

/// Optimization result
class OptimizationResult {
  final String optimizedConfig;
  final List<String> appliedOptimizations;
  final int estimatedImprovement; // percentage

  OptimizationResult({
    required this.optimizedConfig,
    required this.appliedOptimizations,
    required this.estimatedImprovement,
  });
}

/// Optimizer Settings Model
class OptimizerSettings {
  final bool autoOptimize;
  final String preferredDns;
  final int mtuSize;
  final bool muxEnabled;
  final int muxConcurrency;

  OptimizerSettings({
    this.autoOptimize = true,
    this.preferredDns = '1.1.1.1',
    this.mtuSize = 1400,
    this.muxEnabled = true,
    this.muxConcurrency = 8,
  });

  OptimizerSettings copyWith({
    bool? autoOptimize,
    String? preferredDns,
    int? mtuSize,
    bool? muxEnabled,
    int? muxConcurrency,
  }) {
    return OptimizerSettings(
      autoOptimize: autoOptimize ?? this.autoOptimize,
      preferredDns: preferredDns ?? this.preferredDns,
      mtuSize: mtuSize ?? this.mtuSize,
      muxEnabled: muxEnabled ?? this.muxEnabled,
      muxConcurrency: muxConcurrency ?? this.muxConcurrency,
    );
  }
}
