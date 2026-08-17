import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/vpn_config.dart';
import 'vpn_service.dart';

/// Recovery policy for unexpected tunnel failures.
///
/// A user initiated disconnect is never retried. Automatic recovery starts only
/// after the app has observed a successful connection in the current session.
class AutoReconnectService extends ChangeNotifier {
  static final AutoReconnectService _instance =
      AutoReconnectService._internal();
  factory AutoReconnectService() => _instance;
  AutoReconnectService._internal();

  static const _boxName = 'auto_reconnect_settings';
  Box<dynamic>? _settingsBox;
  VpnService? _vpnService;
  void Function(VpnConfig config)? _onFailover;

  bool _isInitialized = false;
  bool _enabled = true;
  bool _autoFailover = true;
  int _maxRetries = 3;
  int _retryDelaySeconds = 5;
  int _healthCheckIntervalSeconds = 30;

  bool _hasConnectedThisSession = false;
  bool _userDisconnectPending = false;
  bool _isReconnecting = false;
  int _currentRetryCount = 0;
  int _totalReconnects = 0;
  int _totalFailovers = 0;
  int _currentServerIndex = 0;
  List<VpnConfig> _serverQueue = <VpnConfig>[];
  Timer? _reconnectTimer;
  Timer? _healthCheckTimer;

  bool get isInitialized => _isInitialized;
  bool get isEnabled => _enabled;
  bool get enabled => _enabled;
  bool get isReconnecting => _isReconnecting;
  int get currentRetryCount => _currentRetryCount;
  int get totalReconnects => _totalReconnects;
  int get totalFailovers => _totalFailovers;
  Duration get reconnectDelay => Duration(seconds: _retryDelaySeconds);
  int get maxRetries => _maxRetries;
  String get currentServerName => _serverQueue.isEmpty
      ? 'None'
      : _serverQueue[_currentServerIndex.clamp(0, _serverQueue.length - 1)]
            .name;

  Future<void> initializeStorage() async {
    if (_isInitialized) return;
    _settingsBox = await Hive.openBox<dynamic>(_boxName);
    _enabled = _settingsBox!.get('enabled', defaultValue: true) as bool;
    _autoFailover =
        _settingsBox!.get('autoFailover', defaultValue: true) as bool;
    _maxRetries = _settingsBox!.get('maxRetries', defaultValue: 3) as int;
    _retryDelaySeconds =
        _settingsBox!.get('retryDelaySeconds', defaultValue: 5) as int;
    _healthCheckIntervalSeconds =
        _settingsBox!.get('healthCheckIntervalSeconds', defaultValue: 30)
            as int;
    _isInitialized = true;
  }

  Future<void> _saveSettings() async {
    final box = _settingsBox;
    if (box == null) return;
    await box.putAll(<String, dynamic>{
      'enabled': _enabled,
      'autoFailover': _autoFailover,
      'maxRetries': _maxRetries,
      'retryDelaySeconds': _retryDelaySeconds,
      'healthCheckIntervalSeconds': _healthCheckIntervalSeconds,
    });
  }

  Future<void> initialize(
    VpnService vpnService, {
    void Function(VpnConfig config)? onFailover,
  }) async {
    await initializeStorage();
    if (!identical(_vpnService, vpnService)) {
      _vpnService?.removeListener(_onVpnStatusChanged);
      _vpnService = vpnService;
      _vpnService!.addListener(_onVpnStatusChanged);
    }
    _onFailover = onFailover;
    _restartHealthCheck();
  }

  void setServerQueue(List<VpnConfig> servers, {String? activeConfigId}) {
    _serverQueue = List<VpnConfig>.from(servers);
    if (_serverQueue.isEmpty) {
      _currentServerIndex = 0;
    } else if (activeConfigId != null) {
      final index = _serverQueue.indexWhere(
        (config) => config.id == activeConfigId,
      );
      _currentServerIndex = index >= 0 ? index : 0;
    } else {
      _currentServerIndex = _currentServerIndex.clamp(
        0,
        _serverQueue.length - 1,
      );
    }
    notifyListeners();
  }

  /// Must be called immediately before a user presses Disconnect.
  void notifyUserDisconnecting() {
    _userDisconnectPending = true;
    _cancelRecovery(resetRetries: true);
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    unawaited(_saveSettings());
    if (!enabled) _cancelRecovery(resetRetries: true);
    _restartHealthCheck();
    notifyListeners();
  }

  void setAutoFailover(bool enabled) {
    _autoFailover = enabled;
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setMaxRetries(int value) {
    _maxRetries = value.clamp(1, 10);
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setRetryDelay(int seconds) {
    _retryDelaySeconds = seconds.clamp(1, 60);
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setReconnectDelay(Duration duration) =>
      setRetryDelay(duration.inSeconds);

  void setHealthCheckInterval(int seconds) {
    _healthCheckIntervalSeconds = seconds.clamp(10, 300);
    unawaited(_saveSettings());
    _restartHealthCheck();
    notifyListeners();
  }

  void _onVpnStatusChanged() {
    final service = _vpnService;
    if (service == null) return;

    switch (service.status) {
      case VpnStatus.connected:
        _hasConnectedThisSession = true;
        if (_isReconnecting) _totalReconnects++;
        _cancelRecovery(resetRetries: true);
        _restartHealthCheck();
        notifyListeners();
      case VpnStatus.disconnected:
        if (_userDisconnectPending) {
          _userDisconnectPending = false;
          _hasConnectedThisSession = false;
          _cancelRecovery(resetRetries: true);
          notifyListeners();
          return;
        }
        if (_hasConnectedThisSession) _scheduleRecovery();
      case VpnStatus.error:
        if (!_userDisconnectPending && _hasConnectedThisSession)
          _scheduleRecovery();
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        break;
    }
  }

  void _restartHealthCheck() {
    _healthCheckTimer?.cancel();
    if (!_enabled || _vpnService == null) return;
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: _healthCheckIntervalSeconds),
      (_) => _performHealthCheck(),
    );
  }

  Future<void> _performHealthCheck() async {
    final service = _vpnService;
    if (!_enabled || service == null || !service.isConnected || _isReconnecting)
      return;
    final delay = await service.getConnectedServerDelay();
    if (delay < 0 || delay > 5000) _scheduleRecovery();
  }

  void _scheduleRecovery() {
    if (!_enabled || _isReconnecting || _userDisconnectPending) return;
    final service = _vpnService;
    if (service?.currentConfig == null && _serverQueue.isEmpty) return;

    _isReconnecting = true;
    _currentRetryCount = 0;
    _attemptReconnect();
    notifyListeners();
  }

  void _attemptReconnect() {
    if (!_enabled || _userDisconnectPending) {
      _cancelRecovery(resetRetries: true);
      return;
    }

    if (_currentRetryCount >= _maxRetries) {
      if (!_moveToNextServer()) {
        _cancelRecovery(resetRetries: true);
        return;
      }
      _currentRetryCount = 0;
    }

    final service = _vpnService;
    final config = _serverQueue.isNotEmpty
        ? _serverQueue[_currentServerIndex]
        : service?.currentConfig;
    if (service == null || config == null) {
      _cancelRecovery(resetRetries: true);
      return;
    }

    _currentRetryCount++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _retryDelaySeconds), () async {
      if (!_enabled || _userDisconnectPending) return;
      final started = await service.connect(config);
      if (!started) _attemptReconnect();
    });
    notifyListeners();
  }

  bool _moveToNextServer() {
    if (!_autoFailover || _serverQueue.length < 2) return false;
    _currentServerIndex = (_currentServerIndex + 1) % _serverQueue.length;
    _totalFailovers++;
    _onFailover?.call(_serverQueue[_currentServerIndex]);
    return true;
  }

  Future<void> manualFailover() async {
    final service = _vpnService;
    if (service == null || !_moveToNextServer()) return;
    _userDisconnectPending = true;
    await service.disconnect();
    _userDisconnectPending = false;
    _isReconnecting = true;
    _currentRetryCount = 0;
    _attemptReconnect();
  }

  void _cancelRecovery({required bool resetRetries}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    if (resetRetries) _currentRetryCount = 0;
  }

  String getStatusText() {
    if (!_enabled) return 'Auto-reconnect disabled';
    if (_isReconnecting) {
      return 'Recovering connection (attempt $_currentRetryCount/$_maxRetries)';
    }
    return 'Connection monitoring active';
  }

  void resetStats() {
    _totalReconnects = 0;
    _totalFailovers = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _cancelRecovery(resetRetries: true);
    _vpnService?.removeListener(_onVpnStatusChanged);
    super.dispose();
  }
}
