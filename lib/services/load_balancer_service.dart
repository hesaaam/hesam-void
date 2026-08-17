import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import 'vpn_service.dart';
import 'ping_service.dart';

/// Multi-Server Load Balancing Service
/// Distributes traffic across multiple servers for better performance
class LoadBalancerService extends ChangeNotifier {
  static final LoadBalancerService _instance = LoadBalancerService._internal();
  factory LoadBalancerService() => _instance;
  LoadBalancerService._internal();

  final VpnService _vpnService = VpnService();

  // Settings
  LoadBalanceStrategy _strategy = LoadBalanceStrategy.lowestPing;
  int _pingThreshold = 200; // ms - switch if ping exceeds this
  int _checkIntervalSeconds = 60;
  bool _enabled = false;

  // State
  List<ServerWithStats> _servers = [];
  int _currentServerIndex = 0;
  Timer? _balanceTimer;
  bool _isBalancing = false;

  // Stats
  int _totalSwitches = 0;
  Map<String, int> _serverUsageCount = {};

  // Getters
  bool get enabled => _enabled;
  LoadBalanceStrategy get strategy => _strategy;
  List<ServerWithStats> get servers => _servers;
  int get totalSwitches => _totalSwitches;
  ServerWithStats? get currentServer =>
      _servers.isNotEmpty && _currentServerIndex < _servers.length
      ? _servers[_currentServerIndex]
      : null;

  /// Set load balance strategy
  void setStrategy(LoadBalanceStrategy strategy) {
    _strategy = strategy;
    notifyListeners();
  }

  /// Enable/disable load balancing
  void setEnabled(bool value) {
    _enabled = value;
    if (value) {
      _startBalancing();
    } else {
      _stopBalancing();
    }
    notifyListeners();
  }

  /// Set servers for load balancing
  Future<void> setServers(List<VpnConfig> configs) async {
    _servers = configs
        .map(
          (c) => ServerWithStats(
            config: c,
            ping: null,
            successRate: 100,
            usageCount: _serverUsageCount[c.id] ?? 0,
            lastUsed: null,
          ),
        )
        .toList();

    // Test ping for all servers
    await _updateAllPings();

    notifyListeners();
  }

  /// Update ping for all servers
  Future<void> _updateAllPings() async {
    for (int i = 0; i < _servers.length; i++) {
      try {
        final ping = await PingService.testPing(_servers[i].config);
        _servers[i] = _servers[i].copyWith(ping: ping);
      } catch (e) {
        _servers[i] = _servers[i].copyWith(ping: -1);
      }
    }

    // Sort by ping if strategy is lowestPing
    if (_strategy == LoadBalanceStrategy.lowestPing) {
      _servers.sort((a, b) {
        if (a.ping == null || a.ping! < 0) return 1;
        if (b.ping == null || b.ping! < 0) return -1;
        return a.ping!.compareTo(b.ping!);
      });
    }

    notifyListeners();
  }

  /// Start load balancing
  void _startBalancing() {
    _stopBalancing();

    _balanceTimer = Timer.periodic(
      Duration(seconds: _checkIntervalSeconds),
      (_) => _checkAndBalance(),
    );

    if (kDebugMode) {
      debugPrint('[LoadBalancer] Started with strategy: $_strategy');
    }
  }

  /// Stop load balancing
  void _stopBalancing() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
    _isBalancing = false;
  }

  /// Check current server and balance if needed
  Future<void> _checkAndBalance() async {
    if (!_enabled || _isBalancing || _servers.isEmpty) return;

    _isBalancing = true;

    try {
      // Update current server ping
      if (_vpnService.isConnected && currentServer != null) {
        final currentPing = await _vpnService.getConnectedServerDelay();

        if (currentPing > _pingThreshold) {
          // Current server is slow, find a better one
          if (kDebugMode) {
            debugPrint(
              '[LoadBalancer] Current ping ($currentPing) exceeds threshold ($_pingThreshold)',
            );
          }
          await _switchToBetterServer();
        }
      }

      // Periodically refresh all pings
      await _updateAllPings();
    } finally {
      _isBalancing = false;
    }
  }

  /// Switch to a better server
  Future<void> _switchToBetterServer() async {
    final nextServer = _selectNextServer();

    if (nextServer != null &&
        nextServer.config.id != currentServer?.config.id) {
      if (kDebugMode) {
        debugPrint('[LoadBalancer] Switching to: ${nextServer.config.name}');
      }

      await _vpnService.disconnect();
      await _vpnService.connect(nextServer.config);

      _currentServerIndex = _servers.indexOf(nextServer);
      _totalSwitches++;
      _serverUsageCount[nextServer.config.id] =
          (_serverUsageCount[nextServer.config.id] ?? 0) + 1;

      notifyListeners();
    }
  }

  /// Select next server based on strategy
  ServerWithStats? _selectNextServer() {
    if (_servers.isEmpty) return null;

    switch (_strategy) {
      case LoadBalanceStrategy.roundRobin:
        return _selectRoundRobin();
      case LoadBalanceStrategy.lowestPing:
        return _selectLowestPing();
      case LoadBalanceStrategy.random:
        return _selectRandom();
      case LoadBalanceStrategy.leastUsed:
        return _selectLeastUsed();
      case LoadBalanceStrategy.weighted:
        return _selectWeighted();
    }
  }

  /// Round-robin selection
  ServerWithStats _selectRoundRobin() {
    int nextIndex = (_currentServerIndex + 1) % _servers.length;
    return _servers[nextIndex];
  }

  /// Select server with lowest ping
  ServerWithStats? _selectLowestPing() {
    ServerWithStats? best;
    int bestPing = 99999;

    for (var server in _servers) {
      if (server.ping != null && server.ping! > 0 && server.ping! < bestPing) {
        bestPing = server.ping!;
        best = server;
      }
    }

    return best ?? _servers.first;
  }

  /// Random selection
  ServerWithStats _selectRandom() {
    return _servers[Random().nextInt(_servers.length)];
  }

  /// Select least used server
  ServerWithStats _selectLeastUsed() {
    _servers.sort((a, b) => a.usageCount.compareTo(b.usageCount));
    return _servers.first;
  }

  /// Weighted selection based on ping
  ServerWithStats _selectWeighted() {
    // Calculate weights (lower ping = higher weight)
    List<double> weights = [];
    double totalWeight = 0;

    for (var server in _servers) {
      double weight = server.ping != null && server.ping! > 0
          ? 1000.0 / server.ping!
          : 0.1;
      weights.add(weight);
      totalWeight += weight;
    }

    // Random weighted selection
    double random = Random().nextDouble() * totalWeight;
    double cumulative = 0;

    for (int i = 0; i < _servers.length; i++) {
      cumulative += weights[i];
      if (random <= cumulative) {
        return _servers[i];
      }
    }

    return _servers.last;
  }

  /// Manually switch to specific server
  Future<void> switchToServer(VpnConfig config) async {
    final index = _servers.indexWhere((s) => s.config.id == config.id);
    if (index >= 0) {
      await _vpnService.disconnect();
      await _vpnService.connect(config);
      _currentServerIndex = index;
      _totalSwitches++;
      notifyListeners();
    }
  }

  /// Manually trigger rebalance
  Future<void> rebalance() async {
    await _checkAndBalance();
  }

  /// Get stats summary
  Map<String, dynamic> getStats() {
    return {
      'totalSwitches': _totalSwitches,
      'currentStrategy': _strategy.name,
      'serverCount': _servers.length,
      'avgPing': _servers.isNotEmpty
          ? _servers
                    .where((s) => s.ping != null && s.ping! > 0)
                    .map((s) => s.ping!)
                    .fold(0, (a, b) => a + b) /
                _servers.where((s) => s.ping != null && s.ping! > 0).length
          : 0,
    };
  }

  @override
  void dispose() {
    _stopBalancing();
    super.dispose();
  }
}

/// Load balance strategies
enum LoadBalanceStrategy {
  roundRobin, // Cycle through servers
  lowestPing, // Always use fastest server
  random, // Random selection
  leastUsed, // Use least used server
  weighted, // Weighted by ping (faster = more likely)
}

/// Server with statistics
class ServerWithStats {
  final VpnConfig config;
  final int? ping;
  final double successRate;
  final int usageCount;
  final DateTime? lastUsed;

  ServerWithStats({
    required this.config,
    this.ping,
    this.successRate = 100,
    this.usageCount = 0,
    this.lastUsed,
  });

  ServerWithStats copyWith({
    VpnConfig? config,
    int? ping,
    double? successRate,
    int? usageCount,
    DateTime? lastUsed,
  }) {
    return ServerWithStats(
      config: config ?? this.config,
      ping: ping ?? this.ping,
      successRate: successRate ?? this.successRate,
      usageCount: usageCount ?? this.usageCount,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  String get pingText => ping != null && ping! > 0 ? '${ping}ms' : 'N/A';
}
