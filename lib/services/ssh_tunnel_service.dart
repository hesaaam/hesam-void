import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ssh_config.dart';
import 'ssh/socks_gateway.dart';
import 'ssh/ssh_session.dart';

enum SshStatus { disconnected, connecting, connected, disconnecting, error }

class SshStats {
  final int uploadBytes;
  final int downloadBytes;
  final String duration;
  final int activeConnections;

  const SshStats({
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.duration = '00:00:00',
    this.activeConnections = 0,
  });
}

/// The SSH tunnel the VPN engine sends traffic into.
///
/// It runs a loopback SOCKS5 gateway (TCP and UDP) backed by one SSH
/// session. UDP goes through the server's UDP gateway (udpgw) when the
/// profile has one; DNS falls back to TCP inside SSH. A dropped session is
/// reopened automatically while the gateway keeps running.
class SshTunnelService extends ChangeNotifier {
  static final SshTunnelService _instance = SshTunnelService._internal();
  factory SshTunnelService() => _instance;
  SshTunnelService._internal();

  static const _preferredPorts = <int>[1080, 1081, 8080, 8888, 9050, 7890];
  static const _connectTimeout = Duration(seconds: 25);
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  SshSession? _session;
  SocksGateway? _gateway;
  SshUdpBridge? _bridge;
  SshStatus _status = SshStatus.disconnected;
  SshConfig? _currentConfig;
  SshStats _stats = const SshStats();
  String? _errorMessage;
  String? _banner;
  bool _reconnecting = false;
  int _localPort = 0;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  int _generation = 0;

  SshStatus get status => _status;
  SshConfig? get currentConfig => _currentConfig;
  SshStats get stats => _stats;
  String? get errorMessage => _errorMessage;

  /// Message the server shows at sign-in (often the account's expiry).
  String? get banner => _banner;

  /// The session dropped and is being reopened.
  bool get isReconnecting => _reconnecting;
  bool get isConnected => _status == SshStatus.connected;
  bool get isConnecting => _status == SshStatus.connecting;
  int get localPort => _localPort;
  String get proxyAddress => '127.0.0.1:$_localPort';

  Future<bool> connect(SshConfig config, {int localPort = 1080}) async {
    if (kIsWeb) {
      return _fail('SSH is not supported on the web platform.');
    }
    if (config.sshHost.trim().isEmpty ||
        config.sshPort < 1 ||
        config.sshPort > 65535) {
      return _fail('The SSH host or port is invalid.');
    }
    if (config.sshUsername.trim().isEmpty) {
      return _fail('The SSH username is required.');
    }

    if (_status != SshStatus.disconnected) await disconnect();

    final generation = ++_generation;
    _status = SshStatus.connecting;
    _currentConfig = config;
    _errorMessage = null;
    _banner = null;
    _reconnecting = false;
    notifyListeners();

    try {
      final session = await SshSession.connect(
        config,
        timeout: _connectTimeout,
      );
      if (generation != _generation) {
        session.close();
        return false;
      }
      _session = session;
      _banner = session.banner;

      final bridge = SshUdpBridge(config, () => _session);
      final gateway = SocksGateway(
        openTcp: (host, port) {
          final active = _session;
          if (active == null || active.isClosed) {
            throw StateError('The SSH session is reconnecting.');
          }
          return active.openTcp(host, port);
        },
        udp: bridge,
      );
      _bridge = bridge;
      _gateway = gateway;
      _localPort = await gateway.start(
        preferredPorts: [if (localPort > 0) localPort, ..._preferredPorts],
      );

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      _watch(session, generation);
      notifyListeners();
      return true;
    } catch (error) {
      await _closeResources();
      _status = SshStatus.error;
      _errorMessage = error is SshSessionException
          ? error.message
          : 'SSH connection failed: $error';
      notifyListeners();
      return false;
    }
  }

  void _watch(SshSession session, int generation) {
    unawaited(
      session.done.then((_) {}, onError: (_) {}).whenComplete(() {
        if (generation != _generation || _status != SshStatus.connected) {
          return;
        }
        if (!identical(_session, session)) return;
        unawaited(_reconnect(generation));
      }),
    );
  }

  Future<void> _reconnect(int generation) async {
    final config = _currentConfig;
    if (config == null) return;
    _reconnecting = true;
    _session = null;
    _bridge?.reset();
    notifyListeners();

    for (final delay in _retryDelays) {
      await Future<void>.delayed(delay);
      if (generation != _generation || _status != SshStatus.connected) return;
      try {
        final session = await SshSession.connect(
          config,
          timeout: _connectTimeout,
        );
        if (generation != _generation) {
          session.close();
          return;
        }
        _session = session;
        _reconnecting = false;
        _watch(session, generation);
        notifyListeners();
        return;
      } on SshSessionException catch (error) {
        // A refused sign-in will not fix itself by retrying.
        if (error.step == SshCheckStep.signIn) {
          _errorMessage = error.message;
          break;
        }
        _errorMessage = error.message;
      } catch (error) {
        _errorMessage = '$error';
      }
    }
    if (generation != _generation) return;
    _reconnecting = false;
    _status = SshStatus.error;
    _errorMessage ??= 'The SSH connection was lost.';
    await _closeResources();
    notifyListeners();
  }

  Future<bool> _fail(String message) async {
    _errorMessage = message;
    _status = SshStatus.error;
    notifyListeners();
    return false;
  }

  Future<void> disconnect() async {
    if (_status == SshStatus.disconnected) return;
    _generation++;
    _status = SshStatus.disconnecting;
    notifyListeners();
    await _closeResources();
    _status = SshStatus.disconnected;
    _currentConfig = null;
    _errorMessage = null;
    _banner = null;
    _reconnecting = false;
    _connectedAt = null;
    _localPort = 0;
    _stats = const SshStats();
    notifyListeners();
  }

  Future<void> _closeResources() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    final gateway = _gateway;
    _gateway = null;
    await gateway?.close();
    final bridge = _bridge;
    _bridge = null;
    await bridge?.close();
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        session.close();
        await session.done.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  /// Time to sign in, in milliseconds, or -1 when it fails.
  Future<int> testConnection(SshConfig config) async {
    final stopwatch = Stopwatch()..start();
    try {
      final session = await SshSession.connect(
        config,
        timeout: const Duration(seconds: 12),
      );
      stopwatch.stop();
      session.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateStats(),
    );
  }

  void _updateStats() {
    final duration = _connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(_connectedAt!);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final gateway = _gateway;
    _stats = SshStats(
      uploadBytes: gateway?.uploaded ?? 0,
      downloadBytes: gateway?.downloaded ?? 0,
      duration: '$hours:$minutes:$seconds',
      activeConnections: gateway?.active ?? 0,
    );
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
