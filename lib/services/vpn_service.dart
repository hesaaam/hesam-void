import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/vpn_config.dart';
import '../models/ssh_config.dart';
import 'ssh_tunnel_service.dart';

/// VPN Connection States
enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// VPN Connection Statistics
class VpnStats {
  final int uploadSpeed; // bytes per second
  final int downloadSpeed; // bytes per second
  final int totalUpload; // total bytes
  final int totalDownload; // total bytes
  final String duration;

  VpnStats({
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.totalUpload = 0,
    this.totalDownload = 0,
    this.duration = '00:00:00',
  });

  String get uploadSpeedStr => _formatSpeed(uploadSpeed);
  String get downloadSpeedStr => _formatSpeed(downloadSpeed);
  String get totalUploadStr => _formatBytes(totalUpload);
  String get totalDownloadStr => _formatBytes(totalDownload);

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Bypass LAN subnets - routes only external traffic through VPN
final List<String> bypassSubnets = [
  "0.0.0.0/5",
  "8.0.0.0/7",
  "11.0.0.0/8",
  "12.0.0.0/6",
  "16.0.0.0/4",
  "32.0.0.0/3",
  "64.0.0.0/2",
  "128.0.0.0/3",
  "160.0.0.0/5",
  "168.0.0.0/6",
  "172.0.0.0/12",
  "172.32.0.0/11",
  "172.64.0.0/10",
  "172.128.0.0/9",
  "173.0.0.0/8",
  "174.0.0.0/7",
  "176.0.0.0/4",
  "192.0.0.0/9",
  "192.128.0.0/11",
  "192.160.0.0/13",
  "192.169.0.0/16",
  "192.170.0.0/15",
  "192.172.0.0/14",
  "192.176.0.0/12",
  "192.192.0.0/10",
  "193.0.0.0/8",
  "194.0.0.0/7",
  "196.0.0.0/6",
  "200.0.0.0/5",
  "208.0.0.0/4",
  "240.0.0.0/4",
];

/// Real VPN Service using V2Ray Core
/// Based on flutter_v2ray package official example
class VpnService extends ChangeNotifier {
  static final VpnService _instance = VpnService._internal();
  factory VpnService() => _instance;
  VpnService._internal();

  // CRITICAL: FlutterV2ray instance - must be initialized before use
  late FlutterV2ray flutterV2ray;
  
  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _currentConfig;
  VpnStats _stats = VpnStats();
  String? _errorMessage;
  String? _coreVersion;
  bool _isInitialized = false;

  // Getters
  VpnStatus get status => _status;
  VpnConfig? get currentConfig => _currentConfig;
  VpnStats get stats => _stats;
  String? get errorMessage => _errorMessage;
  String? get coreVersion => _coreVersion;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _status == VpnStatus.connected;
  bool get isConnecting => _status == VpnStatus.connecting;
  bool get isDisconnected => _status == VpnStatus.disconnected;

  /// Initialize V2Ray Core - MUST be called before any VPN operations
  Future<bool> initialize() async {
    if (kIsWeb) {
      _errorMessage = 'VPN not supported on web platform';
      notifyListeners();
      return false;
    }
    
    if (_isInitialized) return true;

    try {
      // Create FlutterV2ray instance with status callback
      flutterV2ray = FlutterV2ray(
        onStatusChanged: _onStatusChanged,
      );

      // Initialize V2Ray with notification icon
      await flutterV2ray.initializeV2Ray(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );

      // Get core version to verify initialization
      _coreVersion = await flutterV2ray.getCoreVersion();
      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('[VpnService] V2Ray initialized successfully. Core version: $_coreVersion');
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to initialize V2Ray: $e';
      if (kDebugMode) {
        debugPrint('[VpnService] Initialization error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  /// Handle V2Ray status changes from the core
  void _onStatusChanged(V2RayStatus v2rayStatus) {
    if (kDebugMode) {
      debugPrint('[VpnService] Status changed: ${v2rayStatus.state}');
      debugPrint('[VpnService] Duration: ${v2rayStatus.duration}');
      debugPrint('[VpnService] Upload: ${v2rayStatus.uploadSpeed} B/s, Download: ${v2rayStatus.downloadSpeed} B/s');
    }
    
    // Update stats from V2Ray status
    _stats = VpnStats(
      uploadSpeed: v2rayStatus.uploadSpeed,
      downloadSpeed: v2rayStatus.downloadSpeed,
      totalUpload: v2rayStatus.upload,
      totalDownload: v2rayStatus.download,
      duration: v2rayStatus.duration,
    );

    // Map V2Ray state to our VpnStatus
    switch (v2rayStatus.state) {
      case 'CONNECTED':
        _status = VpnStatus.connected;
        _errorMessage = null;
        break;
      case 'DISCONNECTED':
      case 'STOPPED':
        _status = VpnStatus.disconnected;
        break;
      case 'CONNECTING':
        _status = VpnStatus.connecting;
        break;
      default:
        if (kDebugMode) {
          debugPrint('[VpnService] Unknown state: ${v2rayStatus.state}');
        }
        break;
    }

    notifyListeners();
  }

  /// Connect to VPN using config - FOLLOWS OFFICIAL flutter_v2ray EXAMPLE
  Future<bool> connect(VpnConfig config) async {
    if (kIsWeb) {
      _errorMessage = 'VPN not supported on web platform';
      notifyListeners();
      return false;
    }

    // Initialize if not done
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Handle SSH configs differently - they require a separate SSH library
    if (config.isSsh) {
      return _connectSsh(config);
    }

    try {
      _status = VpnStatus.connecting;
      _currentConfig = config;
      _errorMessage = null;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[VpnService] Parsing config URL: ${config.rawUrl.substring(0, 50)}...');
      }

      // CRITICAL: Use FlutterV2ray.parseFromURL to parse the config
      // This is the official way as per flutter_v2ray documentation
      V2RayURL parser = FlutterV2ray.parseFromURL(config.rawUrl);
      
      String remark = parser.remark.isNotEmpty ? parser.remark : config.name;
      String fullConfig = parser.getFullConfiguration();

      if (kDebugMode) {
        debugPrint('[VpnService] Config parsed successfully. Remark: $remark');
        debugPrint('[VpnService] Config length: ${fullConfig.length} bytes');
      }

      // Request VPN permission - REQUIRED for VPN mode
      bool hasPermission = await flutterV2ray.requestPermission();
      if (!hasPermission) {
        _status = VpnStatus.error;
        _errorMessage = 'VPN permission denied. Please allow VPN permission.';
        notifyListeners();
        return false;
      }

      if (kDebugMode) {
        debugPrint('[VpnService] VPN permission granted. Starting V2Ray...');
      }

      // Start V2Ray with the configuration
      // CRITICAL: proxyOnly = false means VPN mode (routes all traffic)
      // bypassSubnets = bypassSubnets means bypass local network traffic
      await flutterV2ray.startV2Ray(
        remark: remark,
        config: fullConfig,
        blockedApps: null,
        bypassSubnets: bypassSubnets, // Use bypass subnets for proper routing
        proxyOnly: false, // VPN Mode - routes all traffic through V2Ray
        notificationDisconnectButtonName: "Disconnect",
      );

      if (kDebugMode) {
        debugPrint('[VpnService] V2Ray startV2Ray called successfully');
      }

      return true;
    } catch (e) {
      _status = VpnStatus.error;
      _errorMessage = 'Connection failed: $e';
      if (kDebugMode) {
        debugPrint('[VpnService] Connection error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  /// Connect to SSH server using dartssh2 real SSH tunneling
  Future<bool> _connectSsh(VpnConfig config) async {
    try {
      _status = VpnStatus.connecting;
      _currentConfig = config;
      _errorMessage = null;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[VpnService] SSH Config detected: ${config.name}');
        debugPrint('[VpnService] SSH Host: ${config.address}:${config.port}');
        debugPrint('[VpnService] SSH User: ${config.sshUsername}');
      }

      // Create SshConfig from VpnConfig
      final sshConfig = SshConfig(
        id: config.id,
        remarks: config.name,
        configType: _parseSshConfigType(config.transportString),
        sshHost: config.address,
        sshPort: config.port,
        sshUsername: config.uuid ?? '', // Username stored in uuid field
        sshPassword: config.password ?? '',
        sni: config.sni,
        tlsVersion: config.encryption ?? 'DEFAULT',
      );

      // Use SSH Tunnel Service for real connection
      final sshService = SshTunnelService();
      final connected = await sshService.connect(sshConfig);

      if (connected) {
        _status = VpnStatus.connected;
        _errorMessage = null;
        
        // Start monitoring SSH stats
        _monitorSshStats(sshService);
        
        if (kDebugMode) {
          debugPrint('[VpnService] SSH connected! Proxy: ${sshService.proxyAddress}');
        }
      } else {
        _status = VpnStatus.error;
        _errorMessage = sshService.errorMessage ?? 'SSH connection failed';
      }
      
      notifyListeners();
      return connected;
      
    } catch (e) {
      _status = VpnStatus.error;
      _errorMessage = 'SSH connection failed: $e';
      if (kDebugMode) {
        debugPrint('[VpnService] SSH error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  /// Parse SSH config type from transport string
  SshConfigType _parseSshConfigType(String transport) {
    switch (transport.toLowerCase()) {
      case 'ssh-ws':
      case 'websocket':
        return SshConfigType.websocket;
      case 'ssh-ssl':
      case 'ssh-tls':
      case 'ssl':
      case 'tls':
        return SshConfigType.ssl;
      case 'ssh-dns':
      case 'slowdns':
        return SshConfigType.slowDns;
      default:
        return SshConfigType.direct;
    }
  }

  /// Monitor SSH tunnel statistics
  void _monitorSshStats(SshTunnelService sshService) {
    sshService.addListener(() {
      if (sshService.isConnected) {
        _stats = VpnStats(
          uploadSpeed: 0, // SSH doesn't provide real-time speed
          downloadSpeed: 0,
          totalUpload: sshService.stats.uploadBytes,
          totalDownload: sshService.stats.downloadBytes,
          duration: sshService.stats.duration,
        );
        notifyListeners();
      } else if (sshService.status == SshStatus.disconnected) {
        _status = VpnStatus.disconnected;
        notifyListeners();
      } else if (sshService.status == SshStatus.error) {
        _status = VpnStatus.error;
        _errorMessage = sshService.errorMessage;
        notifyListeners();
      }
    });
  }

  /// Disconnect VPN
  Future<void> disconnect() async {
    if (kIsWeb || !_isInitialized) return;

    try {
      _status = VpnStatus.disconnecting;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[VpnService] Stopping V2Ray...');
      }

      await flutterV2ray.stopV2Ray();
      
      _status = VpnStatus.disconnected;
      _stats = VpnStats();
      
      if (kDebugMode) {
        debugPrint('[VpnService] V2Ray stopped successfully');
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Disconnect failed: $e';
      _status = VpnStatus.disconnected;
      if (kDebugMode) {
        debugPrint('[VpnService] Disconnect error: $e');
      }
      notifyListeners();
    }
  }

  /// Toggle connection
  Future<void> toggle(VpnConfig config) async {
    if (isConnected || isConnecting) {
      await disconnect();
    } else {
      await connect(config);
    }
  }

  /// Get server delay/ping using flutter_v2ray built-in method
  Future<int> getServerDelay(VpnConfig config) async {
    if (kIsWeb || !_isInitialized) return -1;

    try {
      // Parse the config URL
      V2RayURL parser = FlutterV2ray.parseFromURL(config.rawUrl);
      String fullConfig = parser.getFullConfiguration();
      
      // Use flutter_v2ray's getServerDelay method
      final delay = await flutterV2ray.getServerDelay(config: fullConfig);
      
      if (kDebugMode) {
        debugPrint('[VpnService] Server delay for ${config.name}: ${delay}ms');
      }
      
      return delay;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VpnService] Error getting server delay: $e');
      }
      return -1;
    }
  }

  /// Get connected server delay
  Future<int> getConnectedServerDelay() async {
    if (kIsWeb || !_isInitialized || !isConnected) return -1;

    try {
      final delay = await flutterV2ray.getConnectedServerDelay();
      
      if (kDebugMode) {
        debugPrint('[VpnService] Connected server delay: ${delay}ms');
      }
      
      return delay;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VpnService] Error getting connected server delay: $e');
      }
      return -1;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    super.dispose();
  }
}
