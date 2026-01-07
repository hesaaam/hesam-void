import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Fragment & Noise Injection Service with Persistent Settings
/// Advanced techniques to bypass DPI (Deep Packet Inspection) in Iran
class FragmentService extends ChangeNotifier {
  static final FragmentService _instance = FragmentService._internal();
  factory FragmentService() => _instance;
  FragmentService._internal();

  static const String _boxName = 'fragment_settings';
  Box? _settingsBox;
  bool _isInitialized = false;

  // Settings model
  FragmentServiceSettings _settings = FragmentServiceSettings();
  
  // Getters and setters for settings
  FragmentServiceSettings get settings => _settings;
  bool get isInitialized => _isInitialized;
  
  set settings(FragmentServiceSettings value) {
    _settings = value;
    _saveSettings();
    notifyListeners();
  }

  /// Initialize Hive storage
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _settingsBox = await Hive.openBox(_boxName);
      _loadSettings();
      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('[FragmentService] Initialized with settings: ${_settings.toJson()}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FragmentService] Failed to initialize: $e');
      }
    }
  }

  /// Load settings from Hive
  void _loadSettings() {
    if (_settingsBox == null) return;
    
    try {
      final data = _settingsBox!.get('settings');
      if (data != null) {
        _settings = FragmentServiceSettings.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FragmentService] Error loading settings: $e');
      }
    }
  }

  /// Save settings to Hive
  Future<void> _saveSettings() async {
    if (_settingsBox == null) return;
    
    try {
      await _settingsBox!.put('settings', _settings.toJson());
      if (kDebugMode) {
        debugPrint('[FragmentService] Settings saved');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FragmentService] Error saving settings: $e');
      }
    }
  }

  /// Fragment settings for Iran
  static const Map<String, dynamic> iranFragmentSettings = {
    'packets': 'tlshello',
    'length': '100-200',
    'interval': '10-20',
  };

  /// SNI hosts that work well in Iran
  static const List<String> workingSNIs = [
    'www.google.com',
    'www.microsoft.com',
    'www.apple.com',
    'www.amazon.com',
    'www.cloudflare.com',
    'www.fastly.com',
    'www.akamai.com',
    'update.microsoft.com',
    'www.bing.com',
    'www.office.com',
  ];

  /// Apply fragment settings to config
  String applyFragment(String configJson, {FragmentMode mode = FragmentMode.auto}) {
    try {
      Map<String, dynamic> config = jsonDecode(configJson);
      
      if (config['outbounds'] != null && config['outbounds'] is List) {
        for (var outbound in config['outbounds']) {
          if (outbound is Map && outbound['streamSettings'] != null) {
            var stream = outbound['streamSettings'] as Map<String, dynamic>;
            
            // Apply fragment based on mode
            stream['sockopt'] ??= {};
            
            switch (mode) {
              case FragmentMode.aggressive:
                stream['sockopt']['dialerProxy'] = 'fragment';
                stream['sockopt']['tcpKeepAliveInterval'] = 15;
                stream['sockopt']['tcpMptcp'] = true;
                break;
              case FragmentMode.moderate:
                stream['sockopt']['tcpKeepAliveInterval'] = 30;
                stream['sockopt']['tcpNoDelay'] = true;
                break;
              case FragmentMode.auto:
                stream['sockopt']['tcpKeepAliveInterval'] = 30;
                stream['sockopt']['tcpFastOpen'] = true;
            }
            
            // Add TLS settings with fingerprint
            if (stream['security'] == 'tls' || stream['security'] == 'reality') {
              _applyTLSFingerprint(stream);
            }
          }
        }
        
        // Add fragment outbound for aggressive mode
        if (mode == FragmentMode.aggressive) {
          config = _addFragmentOutbound(config);
        }
      }
      
      return jsonEncode(config);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FragmentService] Error applying fragment: $e');
      }
      return configJson;
    }
  }

  /// Apply TLS fingerprint to mimic browsers
  void _applyTLSFingerprint(Map<String, dynamic> stream) {
    if (stream['tlsSettings'] != null) {
      stream['tlsSettings']['fingerprint'] = _getRandomFingerprint();
      stream['tlsSettings']['allowInsecure'] = false;
    }
    
    if (stream['realitySettings'] != null) {
      stream['realitySettings']['fingerprint'] = _getRandomFingerprint();
      // Use a working SNI for Iran
      if (stream['realitySettings']['serverName'] == null || 
          stream['realitySettings']['serverName'].toString().isEmpty) {
        stream['realitySettings']['serverName'] = _getRandomSNI();
      }
    }
  }

  /// Add fragment outbound for packet splitting
  Map<String, dynamic> _addFragmentOutbound(Map<String, dynamic> config) {
    // Add fragment outbound at the beginning
    List<dynamic> outbounds = config['outbounds'] ?? [];
    
    // Check if fragment outbound already exists
    bool hasFragment = outbounds.any((o) => o['tag'] == 'fragment');
    
    if (!hasFragment) {
      outbounds.insert(0, {
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'fragment': {
            'packets': 'tlshello',
            'length': '100-200',
            'interval': '10-20',
          },
        },
        'streamSettings': {
          'sockopt': {
            'tcpNoDelay': true,
            'tcpKeepAliveInterval': 15,
          },
        },
      });
    }
    
    config['outbounds'] = outbounds;
    return config;
  }

  /// Get random TLS fingerprint
  String _getRandomFingerprint() {
    const fingerprints = [
      'chrome',
      'firefox',
      'safari',
      'edge',
      'ios',
      'android',
      'random',
      'randomized',
    ];
    return fingerprints[Random().nextInt(fingerprints.length)];
  }

  /// Get random SNI from working list
  String _getRandomSNI() {
    return workingSNIs[Random().nextInt(workingSNIs.length)];
  }

  /// Apply noise injection
  String applyNoiseInjection(String configJson, {int noiseLevel = 1}) {
    try {
      Map<String, dynamic> config = jsonDecode(configJson);
      
      if (config['outbounds'] != null && config['outbounds'] is List) {
        for (var outbound in config['outbounds']) {
          if (outbound is Map && outbound['streamSettings'] != null) {
            var stream = outbound['streamSettings'] as Map<String, dynamic>;
            
            // Add padding for WebSocket
            if (stream['network'] == 'ws' && stream['wsSettings'] != null) {
              stream['wsSettings']['headers'] ??= {};
              stream['wsSettings']['headers']['X-Padding'] = _generatePadding(noiseLevel);
            }
            
            // Add fake headers for HTTP
            if (stream['network'] == 'http' || stream['network'] == 'h2') {
              stream['httpSettings'] ??= {};
              stream['httpSettings']['headers'] ??= {};
              stream['httpSettings']['headers']['X-Forwarded-For'] = _generateFakeIP();
              stream['httpSettings']['headers']['X-Real-IP'] = _generateFakeIP();
            }
          }
        }
      }
      
      return jsonEncode(config);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FragmentService] Error applying noise: $e');
      }
      return configJson;
    }
  }

  /// Generate random padding string
  String _generatePadding(int level) {
    final random = Random();
    int length = level * 100 + random.nextInt(100);
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generate fake IP address
  String _generateFakeIP() {
    final random = Random();
    return '${random.nextInt(223) + 1}.${random.nextInt(256)}.${random.nextInt(256)}.${random.nextInt(256)}';
  }

  /// Get recommended settings for Iranian ISPs
  FragmentSettings getIranSettings(String? isp) {
    // Customize based on ISP if detected
    switch (isp?.toLowerCase()) {
      case 'mci':
      case 'همراه اول':
        return FragmentSettings(
          mode: FragmentMode.aggressive,
          fragmentLength: '50-100',
          fragmentInterval: '5-10',
          tlsFingerprint: 'chrome',
        );
      case 'irancell':
      case 'ایرانسل':
        return FragmentSettings(
          mode: FragmentMode.moderate,
          fragmentLength: '100-200',
          fragmentInterval: '10-20',
          tlsFingerprint: 'firefox',
        );
      case 'rightel':
      case 'رایتل':
        return FragmentSettings(
          mode: FragmentMode.aggressive,
          fragmentLength: '80-150',
          fragmentInterval: '8-15',
          tlsFingerprint: 'safari',
        );
      default:
        return FragmentSettings(
          mode: FragmentMode.auto,
          fragmentLength: '100-200',
          fragmentInterval: '10-20',
          tlsFingerprint: 'random',
        );
    }
  }
}

/// Fragment modes
enum FragmentMode {
  auto,       // Automatic based on connection
  moderate,   // Light fragmentation
  aggressive, // Heavy fragmentation for strict DPI
}

/// Fragment settings
class FragmentSettings {
  final FragmentMode mode;
  final String fragmentLength;
  final String fragmentInterval;
  final String tlsFingerprint;

  FragmentSettings({
    required this.mode,
    required this.fragmentLength,
    required this.fragmentInterval,
    required this.tlsFingerprint,
  });
}

/// Fragment Service Settings Model with JSON serialization
class FragmentServiceSettings {
  final bool fragmentEnabled;
  final bool tlsPaddingEnabled;
  final bool sniRandomizationEnabled;
  final FragmentMode mode;
  final String tlsFingerprint;

  FragmentServiceSettings({
    this.fragmentEnabled = false,
    this.tlsPaddingEnabled = false,
    this.sniRandomizationEnabled = false,
    this.mode = FragmentMode.auto,
    this.tlsFingerprint = 'chrome',
  });

  FragmentServiceSettings copyWith({
    bool? fragmentEnabled,
    bool? tlsPaddingEnabled,
    bool? sniRandomizationEnabled,
    FragmentMode? mode,
    String? tlsFingerprint,
  }) {
    return FragmentServiceSettings(
      fragmentEnabled: fragmentEnabled ?? this.fragmentEnabled,
      tlsPaddingEnabled: tlsPaddingEnabled ?? this.tlsPaddingEnabled,
      sniRandomizationEnabled: sniRandomizationEnabled ?? this.sniRandomizationEnabled,
      mode: mode ?? this.mode,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
    );
  }

  Map<String, dynamic> toJson() => {
    'fragmentEnabled': fragmentEnabled,
    'tlsPaddingEnabled': tlsPaddingEnabled,
    'sniRandomizationEnabled': sniRandomizationEnabled,
    'mode': mode.index,
    'tlsFingerprint': tlsFingerprint,
  };

  factory FragmentServiceSettings.fromJson(Map<String, dynamic> json) {
    return FragmentServiceSettings(
      fragmentEnabled: json['fragmentEnabled'] ?? false,
      tlsPaddingEnabled: json['tlsPaddingEnabled'] ?? false,
      sniRandomizationEnabled: json['sniRandomizationEnabled'] ?? false,
      mode: FragmentMode.values[json['mode'] ?? 0],
      tlsFingerprint: json['tlsFingerprint'] ?? 'chrome',
    );
  }
}
