import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/vpn_config.dart';
import 'auto_reconnect_service.dart';
import 'connection_health_service.dart';
import 'ping_service.dart';
import 'vpn_service.dart';

enum SmartConnectPhase {
  idle,
  scanning,
  measuring,
  connecting,
  verifying,
  succeeded,
  failed,
  cancelled,
}

/// One candidate route with the evidence used to rank it.
class SmartCandidate {
  final VpnConfig config;
  final int? tcpMs;
  final int? realDelayMs;
  final int healthScore;

  const SmartCandidate({
    required this.config,
    required this.tcpMs,
    required this.healthScore,
    this.realDelayMs,
  });

  SmartCandidate withRealDelay(int? value) => SmartCandidate(
    config: config,
    tcpMs: tcpMs,
    healthScore: healthScore,
    realDelayMs: value,
  );
}

/// One-tap route selection.
///
/// 1. Every profile gets a fast parallel TCP reachability check.
/// 2. The most promising reachable profiles get a real request through a
///    temporary engine (Real Delay), which proves they carry traffic.
/// 3. The best route is connected, and the tunnel is verified end to end.
///    If the route fails, the next candidate is tried automatically.
class SmartConnectService extends ChangeNotifier {
  static final SmartConnectService _instance = SmartConnectService._internal();
  factory SmartConnectService() => _instance;
  SmartConnectService._internal();

  static const int maxRealDelayProbes = 4;
  static const int maxConnectAttempts = 3;
  static const Duration realDelayTimeout = Duration(seconds: 8);
  static const Duration connectTimeout = Duration(seconds: 25);

  SmartConnectPhase _phase = SmartConnectPhase.idle;
  String _message = '';
  int _attempt = 0;
  int _attemptTotal = 0;
  int _progressDone = 0;
  int _progressTotal = 0;
  VpnConfig? _currentCandidate;
  bool _cancelRequested = false;
  int _runId = 0;

  SmartConnectPhase get phase => _phase;
  String get message => _message;
  int get attempt => _attempt;
  int get attemptTotal => _attemptTotal;
  int get progressDone => _progressDone;
  int get progressTotal => _progressTotal;
  VpnConfig? get currentCandidate => _currentCandidate;

  bool get isRunning =>
      _phase == SmartConnectPhase.scanning ||
      _phase == SmartConnectPhase.measuring ||
      _phase == SmartConnectPhase.connecting ||
      _phase == SmartConnectPhase.verifying;

  String get headline {
    switch (_phase) {
      case SmartConnectPhase.scanning:
        return 'Checking your routes';
      case SmartConnectPhase.measuring:
        return 'Measuring real speed';
      case SmartConnectPhase.connecting:
        return _currentCandidate == null
            ? 'Connecting'
            : 'Connecting to ${_currentCandidate!.name}';
      case SmartConnectPhase.verifying:
        return 'Confirming internet access';
      case SmartConnectPhase.succeeded:
        return 'Best route connected';
      case SmartConnectPhase.failed:
        return 'No working route found';
      case SmartConnectPhase.cancelled:
        return 'Smart Connect stopped';
      case SmartConnectPhase.idle:
        return 'Smart Connect';
    }
  }

  /// Ranks reachable candidates. Profiles proven by Real Delay come first
  /// (fastest first), followed by profiles that only answered TCP, ordered by
  /// local health and then latency. Profiles whose Real Delay failed go last.
  @visibleForTesting
  static List<SmartCandidate> rank(List<SmartCandidate> candidates) {
    int group(SmartCandidate c) {
      if (c.realDelayMs != null && c.realDelayMs! > 0) return 0;
      if (c.realDelayMs == null) return 1;
      return 2;
    }

    final sorted = List<SmartCandidate>.from(candidates);
    sorted.sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      if (byGroup != 0) return byGroup;
      if (group(a) == 0) return a.realDelayMs!.compareTo(b.realDelayMs!);
      final byHealth = b.healthScore.compareTo(a.healthScore);
      if (byHealth != 0) return byHealth;
      return (a.tcpMs ?? 999999).compareTo(b.tcpMs ?? 999999);
    });
    return sorted;
  }

  void cancel() {
    if (!isRunning) return;
    _cancelRequested = true;
    _message = 'Stopping…';
    notifyListeners();
  }

  /// Resets a finished run so the UI returns to its normal state.
  void dismiss() {
    if (isRunning) return;
    _phase = SmartConnectPhase.idle;
    _message = '';
    _currentCandidate = null;
    notifyListeners();
  }

  /// Finds and connects the best working route. Returns it, or null.
  Future<VpnConfig?> run({
    required List<VpnConfig> configs,
    required VpnService vpn,
    required AutoReconnectService autoReconnect,
    required void Function(VpnConfig config) onSelect,
    Future<void> Function(Map<String, int?> latencies)? onMeasured,
  }) async {
    if (isRunning) return null;
    final runId = ++_runId;
    _cancelRequested = false;
    _attempt = 0;
    _attemptTotal = 0;
    _currentCandidate = null;

    if (configs.isEmpty) {
      _finish(SmartConnectPhase.failed, 'Add a profile first.');
      return null;
    }

    if (vpn.isConnected || vpn.isConnecting) {
      autoReconnect.notifyUserDisconnecting();
      await vpn.disconnect();
    }

    // 1. Fast reachability scan.
    _setPhase(
      SmartConnectPhase.scanning,
      'Checking ${configs.length} route${configs.length == 1 ? '' : 's'}…',
      total: configs.length,
    );
    final tcp = await PingService.testMultiplePings(
      configs,
      concurrency: 12,
      onProgress: (done, total) {
        if (runId != _runId) return;
        _progressDone = done;
        _message = 'Checked $done of $total routes';
        notifyListeners();
      },
    );
    await ConnectionHealthService().recordProbes(tcp);
    if (onMeasured != null) await onMeasured(tcp);
    if (_stopped(runId)) return null;

    final health = ConnectionHealthService();
    var candidates = configs
        .where((config) => tcp[config.id] != null)
        .map(
          (config) => SmartCandidate(
            config: config,
            tcpMs: tcp[config.id],
            healthScore: health.snapshotFor(config.id).score,
          ),
        )
        .toList();

    if (candidates.isEmpty) {
      _finish(
        SmartConnectPhase.failed,
        'None of your routes answered. Check that you are online, or import '
        'fresh profiles.',
      );
      return null;
    }
    candidates = rank(candidates);

    // 2. Real Delay for the most promising engine-based profiles.
    final measurable = candidates
        .where((c) => !c.config.isSsh)
        .take(maxRealDelayProbes)
        .toList();
    if (measurable.isNotEmpty) {
      _setPhase(
        SmartConnectPhase.measuring,
        'Testing real traffic on ${measurable.length} '
        'route${measurable.length == 1 ? '' : 's'}…',
        total: measurable.length,
      );
      final measured = <String, int>{};
      for (final candidate in measurable) {
        if (_stopped(runId)) return null;
        final delay = await vpn
            .getServerDelay(candidate.config)
            .timeout(realDelayTimeout, onTimeout: () => -1);
        measured[candidate.config.id] = delay;
        _progressDone++;
        _message = delay > 0
            ? '${candidate.config.name}: $delay ms'
            : '${candidate.config.name}: no traffic';
        notifyListeners();
      }
      candidates = rank([
        for (final c in candidates)
          measured.containsKey(c.config.id)
              ? c.withRealDelay(measured[c.config.id])
              : c,
      ]);
    }
    if (_stopped(runId)) return null;

    // 3. Connect, verify, and fall back to the next candidate when needed.
    final attempts = candidates.take(maxConnectAttempts).toList();
    _attemptTotal = attempts.length;
    autoReconnect.setServerQueue(
      candidates.map((c) => c.config).toList(),
      activeConfigId: attempts.first.config.id,
    );

    for (final candidate in attempts) {
      if (_stopped(runId)) return null;
      _attempt++;
      _currentCandidate = candidate.config;
      onSelect(candidate.config);
      _setPhase(
        SmartConnectPhase.connecting,
        _attemptTotal > 1
            ? 'Route $_attempt of $_attemptTotal'
            : 'Starting secure route',
      );

      final status = await _connectAndWait(vpn, candidate.config);
      if (_stopped(runId)) {
        await _abortConnection(vpn, autoReconnect);
        return null;
      }

      if (status == VpnStatus.connected) {
        _setPhase(SmartConnectPhase.verifying, 'Sending a test request…');
        final verified = await vpn.verifyTunnel();
        if (_stopped(runId)) {
          await _abortConnection(vpn, autoReconnect);
          return null;
        }
        if (verified) {
          _finish(
            SmartConnectPhase.succeeded,
            vpn.tunnelLatencyMs == null
                ? candidate.config.name
                : '${candidate.config.name} • ${vpn.tunnelLatencyMs} ms',
          );
          return candidate.config;
        }
      }

      // This route did not work: close it cleanly before trying the next.
      await _abortConnection(vpn, autoReconnect);
    }

    _finish(
      SmartConnectPhase.failed,
      'Tried $_attemptTotal route${_attemptTotal == 1 ? '' : 's'}, but none '
      'carried traffic. Try again later or import fresh profiles.',
    );
    return null;
  }

  Future<VpnStatus> _connectAndWait(VpnService vpn, VpnConfig config) async {
    final completer = Completer<VpnStatus>();
    void listener() {
      final status = vpn.status;
      if ((status == VpnStatus.connected || status == VpnStatus.error) &&
          !completer.isCompleted) {
        completer.complete(status);
      }
    }

    vpn.addListener(listener);
    try {
      final started = await vpn.connect(config);
      if (!started) return VpnStatus.error;
      listener();
      return await completer.future.timeout(
        connectTimeout,
        onTimeout: () => VpnStatus.error,
      );
    } finally {
      vpn.removeListener(listener);
    }
  }

  Future<void> _abortConnection(
    VpnService vpn,
    AutoReconnectService autoReconnect,
  ) async {
    if (vpn.isConnected || vpn.isConnecting) {
      autoReconnect.notifyUserDisconnecting();
      await vpn.disconnect();
    }
  }

  bool _stopped(int runId) {
    if (runId != _runId) return true;
    if (_cancelRequested) {
      _finish(SmartConnectPhase.cancelled, 'Stopped before connecting.');
      return true;
    }
    return false;
  }

  void _setPhase(SmartConnectPhase phase, String message, {int? total}) {
    _phase = phase;
    _message = message;
    if (total != null) {
      _progressDone = 0;
      _progressTotal = total;
    }
    notifyListeners();
  }

  void _finish(SmartConnectPhase phase, String message) {
    _phase = phase;
    _message = message;
    _cancelRequested = false;
    notifyListeners();
  }
}
