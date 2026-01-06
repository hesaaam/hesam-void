import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import 'vpn_service.dart';

/// Auto-Reconnect & Failover Service
/// Automatically reconnects when connection drops and switches to next server
class AutoReconnectService extends ChangeNotifier {
  static final AutoReconnectService _instance = AutoReconnectService._internal();
  factory AutoReconnectService() => _instance;
  AutoReconnectService._internal();

  final VpnService _vpnService = VpnService();
  
  // Settings
  bool _enabled = true;
  int _maxRetries = 3;
  int _retryDelaySeconds = 5;
  int _healthCheckIntervalSeconds = 30;
  bool _autoFailover = true;
  
  // State
  int _currentRetryCount = 0;
  Timer? _healthCheckTimer;
  Timer? _reconnectTimer;
  List<VpnConfig> _serverQueue = [];
  int _currentServerIndex = 0;
  bool _isReconnecting = false;
  DateTime? _lastDisconnectTime;
  
  // Stats
  int _totalReconnects = 0;
  int _totalFailovers = 0;
  
  // Getters
  bool get isEnabled => _enabled;
  bool get enabled => _enabled;
  bool get isReconnecting => _isReconnecting;
  int get currentRetryCount => _currentRetryCount;
  int get totalReconnects => _totalReconnects;
  int get totalFailovers => _totalFailovers;
  String get currentServerName => _serverQueue.isNotEmpty && _currentServerIndex < _serverQueue.length
      ? _serverQueue[_currentServerIndex].name
      : 'None';

  /// Enable/disable auto-reconnect
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      stopMonitoring();
    }
    notifyListeners();
  }

  /// Set max retries before failover
  void setMaxRetries(int value) {
    _maxRetries = value;
    notifyListeners();
  }

  /// Get retry delay
  Duration get reconnectDelay => Duration(seconds: _retryDelaySeconds);

  /// Get max retries
  int get maxRetries => _maxRetries;

  /// Set retry delay in seconds
  void setRetryDelay(int seconds) {
    _retryDelaySeconds = seconds;
    notifyListeners();
  }

  /// Set retry delay duration
  void setReconnectDelay(Duration duration) {
    _retryDelaySeconds = duration.inSeconds;
    notifyListeners();
  }

  /// Set health check interval
  void setHealthCheckInterval(int seconds) {
    _healthCheckIntervalSeconds = seconds;
    _restartHealthCheck();
    notifyListeners();
  }

  /// Set server queue for failover
  void setServerQueue(List<VpnConfig> servers) {
    _serverQueue = List.from(servers);
    _currentServerIndex = 0;
    notifyListeners();
  }

  /// Initialize the service
  void initialize(VpnService vpnService, dynamic configProvider) {
    // Start monitoring when initialized
    startMonitoring();
  }

  /// Start monitoring connection
  void startMonitoring() {
    if (!_enabled) return;
    
    _stopTimers();
    
    // Start health check timer
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: _healthCheckIntervalSeconds),
      (_) => _performHealthCheck(),
    );
    
    // Listen to VPN status changes
    _vpnService.addListener(_onVpnStatusChanged);
    
    if (kDebugMode) {
      debugPrint('[AutoReconnect] Monitoring started');
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _stopTimers();
    _vpnService.removeListener(_onVpnStatusChanged);
    _isReconnecting = false;
    _currentRetryCount = 0;
    
    if (kDebugMode) {
      debugPrint('[AutoReconnect] Monitoring stopped');
    }
  }

  void _stopTimers() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _restartHealthCheck() {
    _healthCheckTimer?.cancel();
    if (_enabled) {
      _healthCheckTimer = Timer.periodic(
        Duration(seconds: _healthCheckIntervalSeconds),
        (_) => _performHealthCheck(),
      );
    }
  }

  /// Handle VPN status changes
  void _onVpnStatusChanged() {
    if (!_enabled) return;
    
    final status = _vpnService.status;
    
    if (status == VpnStatus.disconnected && !_isReconnecting) {
      // Unexpected disconnect - trigger reconnect
      _lastDisconnectTime = DateTime.now();
      _triggerReconnect();
    } else if (status == VpnStatus.connected) {
      // Successfully connected - reset counters
      _currentRetryCount = 0;
      _isReconnecting = false;
      _reconnectTimer?.cancel();
      
      if (kDebugMode) {
        debugPrint('[AutoReconnect] Connected successfully');
      }
    }
  }

  /// Perform health check
  Future<void> _performHealthCheck() async {
    if (!_enabled || !_vpnService.isConnected) return;
    
    try {
      final delay = await _vpnService.getConnectedServerDelay();
      
      if (delay < 0 || delay > 5000) {
        // Connection seems unhealthy
        if (kDebugMode) {
          debugPrint('[AutoReconnect] Health check failed: delay=$delay');
        }
        _triggerReconnect();
      } else {
        if (kDebugMode) {
          debugPrint('[AutoReconnect] Health check OK: delay=${delay}ms');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AutoReconnect] Health check error: $e');
      }
    }
  }

  /// Trigger reconnection attempt
  void _triggerReconnect() {
    if (_isReconnecting || !_enabled) return;
    
    _isReconnecting = true;
    notifyListeners();
    
    if (kDebugMode) {
      debugPrint('[AutoReconnect] Triggering reconnect (attempt ${_currentRetryCount + 1}/$_maxRetries)');
    }
    
    _attemptReconnect();
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (!_enabled) {
      _isReconnecting = false;
      return;
    }
    
    _currentRetryCount++;
    notifyListeners();
    
    // Check if we should failover to next server
    if (_currentRetryCount > _maxRetries && _autoFailover) {
      _performFailover();
      return;
    }
    
    // Get current config
    VpnConfig? config;
    if (_serverQueue.isNotEmpty && _currentServerIndex < _serverQueue.length) {
      config = _serverQueue[_currentServerIndex];
    } else {
      config = _vpnService.currentConfig;
    }
    
    if (config == null) {
      if (kDebugMode) {
        debugPrint('[AutoReconnect] No config available for reconnect');
      }
      _isReconnecting = false;
      notifyListeners();
      return;
    }
    
    // Wait before retry
    _reconnectTimer = Timer(Duration(seconds: _retryDelaySeconds), () async {
      if (!_enabled) return;
      
      final success = await _vpnService.connect(config!);
      
      if (success) {
        _totalReconnects++;
        _currentRetryCount = 0;
        _isReconnecting = false;
        notifyListeners();
        
        if (kDebugMode) {
          debugPrint('[AutoReconnect] Reconnected successfully');
        }
      } else {
        // Retry again
        _attemptReconnect();
      }
    });
  }

  /// Failover to next server
  void _performFailover() {
    if (!_autoFailover || _serverQueue.isEmpty) {
      _isReconnecting = false;
      _currentRetryCount = 0;
      notifyListeners();
      return;
    }
    
    _currentServerIndex++;
    if (_currentServerIndex >= _serverQueue.length) {
      _currentServerIndex = 0; // Loop back to first server
    }
    
    _currentRetryCount = 0;
    _totalFailovers++;
    
    if (kDebugMode) {
      debugPrint('[AutoReconnect] Failover to server: ${_serverQueue[_currentServerIndex].name}');
    }
    
    notifyListeners();
    _attemptReconnect();
  }

  /// Manually trigger failover to next server
  Future<void> manualFailover() async {
    if (_serverQueue.isEmpty) return;
    
    await _vpnService.disconnect();
    _performFailover();
  }

  /// Get reconnect status text
  String getStatusText() {
    if (!_enabled) return 'Auto-reconnect disabled';
    if (_isReconnecting) {
      return 'Reconnecting... (attempt $_currentRetryCount/$_maxRetries)';
    }
    return 'Monitoring active';
  }

  /// Reset all stats
  void resetStats() {
    _totalReconnects = 0;
    _totalFailovers = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

/// Reconnect event for logging
class ReconnectEvent {
  final DateTime timestamp;
  final String serverName;
  final bool success;
  final int attempt;
  final String? errorMessage;

  ReconnectEvent({
    required this.timestamp,
    required this.serverName,
    required this.success,
    required this.attempt,
    this.errorMessage,
  });
}
