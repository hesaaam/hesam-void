import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/ssh_config.dart';

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

/// A device-local SOCKS5 gateway backed by an authenticated SSH connection.
///
/// The service has one long-lived SSH session and opens a fresh SSH forwarding
/// channel for each SOCKS request. It deliberately listens only on loopback.
class SshTunnelService extends ChangeNotifier {
  static final SshTunnelService _instance = SshTunnelService._internal();
  factory SshTunnelService() => _instance;
  SshTunnelService._internal();

  static const _preferredPorts = <int>[1080, 1081, 8080, 8888, 9050, 7890];
  static const _connectTimeout = Duration(seconds: 25);
  static const _handshakeTimeout = Duration(seconds: 12);

  SSHClient? _client;
  ServerSocket? _proxyServer;
  SshStatus _status = SshStatus.disconnected;
  SshConfig? _currentConfig;
  SshStats _stats = const SshStats();
  String? _errorMessage;
  int _localPort = 0;
  int _totalUpload = 0;
  int _totalDownload = 0;
  int _activeConnectionCount = 0;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  final Set<Socket> _clientSockets = <Socket>{};

  SshStatus get status => _status;
  SshConfig? get currentConfig => _currentConfig;
  SshStats get stats => _stats;
  String? get errorMessage => _errorMessage;
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

    _status = SshStatus.connecting;
    _currentConfig = config;
    _errorMessage = null;
    _localPort = localPort;
    _totalUpload = 0;
    _totalDownload = 0;
    _activeConnectionCount = 0;
    notifyListeners();

    try {
      final transport = await _openTransport(config);
      final client = SSHClient(
        transport,
        username: config.sshUsername,
        onPasswordRequest: () => config.sshPassword,
      );
      _client = client;
      await client.authenticated.timeout(_connectTimeout);
      await _startSocks5Server(requestedPort: localPort);

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      notifyListeners();

      unawaited(
        client.done.then((_) {
          if (_status == SshStatus.connected) {
            _status = SshStatus.error;
            _errorMessage = 'The SSH connection was closed by the server.';
            unawaited(_closeProxyOnly());
            notifyListeners();
          }
        }),
      );
      return true;
    } catch (error) {
      await _closeResources();
      _status = SshStatus.error;
      _errorMessage = _parseError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> _fail(String message) async {
    _errorMessage = message;
    _status = SshStatus.error;
    notifyListeners();
    return false;
  }

  Future<SSHSocket> _openTransport(SshConfig config) async {
    switch (config.configType) {
      case SshConfigType.direct:
        return SSHSocket.connect(
          config.sshHost,
          config.sshPort,
          timeout: _connectTimeout,
        );
      case SshConfigType.ssl:
        final socket = await SecureSocket.connect(
          config.sshHost,
          config.sshPort,
          timeout: _connectTimeout,
        );
        return _IoSshSocket(socket);
      case SshConfigType.websocket:
        final path = _extractWebSocketPath(config.payload);
        final scheme =
            (config.sni?.isNotEmpty ?? false) || config.sshPort == 443
            ? 'wss'
            : 'ws';
        final uri = Uri(
          scheme: scheme,
          host: config.sshHost,
          port: config.sshPort,
          path: path,
        );
        final socket = await WebSocket.connect(
          uri.toString(),
          headers: config.sni?.isNotEmpty == true
              ? {'Host': config.sni!}
              : null,
          compression: CompressionOptions.compressionOff,
        ).timeout(_connectTimeout);
        return _WebSocketSshSocket(socket);
      case SshConfigType.slowDns:
        throw UnsupportedError(
          'SSH over SlowDNS needs a compatible DNS transport and is not available in this release.',
        );
    }
  }

  String _extractWebSocketPath(String? payload) {
    final value = payload?.trim();
    if (value == null || value.isEmpty) return '/';
    if (value.startsWith('/')) return value.split(RegExp(r'\s+')).first;
    if (value.toUpperCase().startsWith('GET ')) {
      final parts = value.split(RegExp(r'\s+'));
      if (parts.length > 1 && parts[1].startsWith('/')) return parts[1];
    }
    return '/';
  }

  Future<void> _startSocks5Server({required int requestedPort}) async {
    final candidates = <int>{
      if (requestedPort > 0 && requestedPort <= 65535) requestedPort,
      ..._preferredPorts,
      0,
    };

    Object? lastError;
    for (final port in candidates) {
      try {
        final server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _proxyServer = server;
        _localPort = server.port;
        server.listen(
          _handleSocks5Connection,
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) debugPrint('[SSH SOCKS] Server error: $error');
          },
        );
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw SocketException('Unable to bind a local SOCKS5 port: $lastError');
  }

  void _handleSocks5Connection(Socket clientSocket) {
    _clientSockets.add(clientSocket);
    _activeConnectionCount++;
    _updateStats();

    final buffer = <int>[];
    var stage =
        0; // 0: authentication methods, 1: connect request, 2: forwarding
    var openingTunnel = false;
    var closed = false;
    SSHForwardChannel? channel;
    StreamSubscription<Uint8List>? remoteSubscription;
    Timer? handshakeTimer;
    late final StreamSubscription<Uint8List> clientSubscription;

    Future<void> closeConnection() async {
      if (closed) return;
      closed = true;
      handshakeTimer?.cancel();
      await remoteSubscription?.cancel();
      try {
        await channel?.sink.close();
      } catch (_) {}
      try {
        await clientSocket.close();
      } catch (_) {}
      _clientSockets.remove(clientSocket);
      if (_activeConnectionCount > 0) _activeConnectionCount--;
      _updateStats();
    }

    Future<void> openTunnel(_Socks5Target target) async {
      try {
        final activeClient = _client;
        if (activeClient == null || _status != SshStatus.connected) {
          throw StateError('SSH tunnel is not connected.');
        }
        final openedChannel = await activeClient.forwardLocal(
          target.host,
          target.port,
        );
        if (closed) {
          await openedChannel.sink.close();
          return;
        }
        channel = openedChannel;
        clientSocket.add(_socksReply(0x00));
        if (target.remainingData.isNotEmpty) {
          openedChannel.sink.add(target.remainingData);
          _totalUpload += target.remainingData.length;
        }
        remoteSubscription = openedChannel.stream.listen(
          (data) {
            if (closed) return;
            clientSocket.add(data);
            _totalDownload += data.length;
            _updateStats();
          },
          onError: (_, __) => unawaited(closeConnection()),
          onDone: () => unawaited(closeConnection()),
          cancelOnError: true,
        );
        stage = 2;
        openingTunnel = false;
        handshakeTimer?.cancel();
        clientSubscription.resume();
        _updateStats();
      } catch (_) {
        if (!closed) clientSocket.add(_socksReply(0x05));
        unawaited(closeConnection());
      }
    }

    void onClientData(Uint8List data) {
      if (closed) return;
      if (stage == 2 && channel != null) {
        channel!.sink.add(data);
        _totalUpload += data.length;
        _updateStats();
        return;
      }
      if (openingTunnel) return;

      buffer.addAll(data);
      if (stage == 0) {
        if (buffer.length < 2) return;
        final methodCount = buffer[1];
        if (buffer.length < methodCount + 2) return;
        final methods = buffer.sublist(2, methodCount + 2);
        buffer.removeRange(0, methodCount + 2);
        if (!methods.contains(0x00)) {
          clientSocket.add(<int>[0x05, 0xff]);
          unawaited(closeConnection());
          return;
        }
        clientSocket.add(<int>[0x05, 0x00]);
        stage = 1;
      }

      if (stage != 1) return;
      final request = _readSocksRequest(buffer);
      if (request == null) return;
      if (request.errorReply != null) {
        clientSocket.add(_socksReply(request.errorReply!));
        unawaited(closeConnection());
        return;
      }
      if (request.target == null) return;

      openingTunnel = true;
      clientSubscription.pause();
      unawaited(openTunnel(request.target!));
    }

    clientSubscription = clientSocket.listen(
      onClientData,
      onError: (_, __) => unawaited(closeConnection()),
      onDone: () => unawaited(closeConnection()),
      cancelOnError: true,
    );
    handshakeTimer = Timer(_handshakeTimeout, () {
      if (stage < 2) unawaited(closeConnection());
    });
  }

  _SocksRequestResult? _readSocksRequest(List<int> buffer) {
    if (buffer.length < 4) return null;
    if (buffer[0] != 0x05 || buffer[1] != 0x01) {
      return const _SocksRequestResult.error(0x07);
    }

    final addressType = buffer[3];
    var requiredLength = 0;
    String? host;
    var portOffset = 0;
    if (addressType == 0x01) {
      requiredLength = 10;
      if (buffer.length < requiredLength) return null;
      host = '${buffer[4]}.${buffer[5]}.${buffer[6]}.${buffer[7]}';
      portOffset = 8;
    } else if (addressType == 0x03) {
      if (buffer.length < 5) return null;
      final domainLength = buffer[4];
      requiredLength = 7 + domainLength;
      if (buffer.length < requiredLength) return null;
      host = String.fromCharCodes(buffer.sublist(5, 5 + domainLength));
      portOffset = 5 + domainLength;
    } else if (addressType == 0x04) {
      requiredLength = 22;
      if (buffer.length < requiredLength) return null;
      host = _formatIpv6(buffer.sublist(4, 20));
      portOffset = 20;
    } else {
      return const _SocksRequestResult.error(0x08);
    }

    final port = (buffer[portOffset] << 8) | buffer[portOffset + 1];
    final remaining = Uint8List.fromList(buffer.sublist(requiredLength));
    buffer.clear();
    return _SocksRequestResult.target(
      _Socks5Target(host: host, port: port, remainingData: remaining),
    );
  }

  List<int> _socksReply(int code) => <int>[
    0x05,
    code,
    0x00,
    0x01,
    127,
    0,
    0,
    1,
    (_localPort >> 8) & 0xff,
    _localPort & 0xff,
  ];

  String _formatIpv6(List<int> bytes) {
    final groups = <String>[];
    for (var index = 0; index < 16; index += 2) {
      groups.add(((bytes[index] << 8) | bytes[index + 1]).toRadixString(16));
    }
    return groups.join(':');
  }

  Future<void> disconnect() async {
    if (_status == SshStatus.disconnected) return;
    _status = SshStatus.disconnecting;
    notifyListeners();
    await _closeResources();
    _status = SshStatus.disconnected;
    _currentConfig = null;
    _errorMessage = null;
    _connectedAt = null;
    _localPort = 0;
    _totalUpload = 0;
    _totalDownload = 0;
    _activeConnectionCount = 0;
    _stats = const SshStats();
    notifyListeners();
  }

  Future<void> _closeProxyOnly() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    for (final socket in _clientSockets.toList()) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _clientSockets.clear();
    await _proxyServer?.close();
    _proxyServer = null;
  }

  Future<void> _closeResources() async {
    await _closeProxyOnly();
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        client.close();
        await client.done.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  Future<int> testConnection(SshConfig config) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      final transport = await _openTransport(config);
      client = SSHClient(
        transport,
        username: config.sshUsername,
        onPasswordRequest: () => config.sshPassword,
      );
      await client.authenticated.timeout(const Duration(seconds: 12));
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      stopwatch.stop();
      return -1;
    } finally {
      client?.close();
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
    _stats = SshStats(
      uploadBytes: _totalUpload,
      downloadBytes: _totalDownload,
      duration: '$hours:$minutes:$seconds',
      activeConnections: _activeConnectionCount,
    );
    notifyListeners();
  }

  String _parseError(Object error) {
    final message = error.toString();
    final normalized = message.toLowerCase();
    if (error is UnsupportedError) return message;
    if (normalized.contains('connection refused'))
      return 'Connection refused. The server may be offline.';
    if (normalized.contains('timed out') || normalized.contains('timeout'))
      return 'Connection timeout. Check the server address and your network.';
    if (normalized.contains('authentication') ||
        normalized.contains('not authenticated'))
      return 'Authentication failed. Check the SSH username and password.';
    if (normalized.contains('certificate') || normalized.contains('handshake'))
      return 'TLS handshake failed. Verify the SSH TLS host and certificate.';
    if (normalized.contains('no route') || normalized.contains('unreachable'))
      return 'Network is unreachable. Check your connection.';
    if (normalized.contains('websocket'))
      return 'WebSocket transport failed. Verify its host, path and port.';
    return 'SSH connection failed: $message';
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

class _Socks5Target {
  final String host;
  final int port;
  final Uint8List remainingData;

  const _Socks5Target({
    required this.host,
    required this.port,
    required this.remainingData,
  });
}

class _SocksRequestResult {
  final _Socks5Target? target;
  final int? errorReply;

  const _SocksRequestResult.target(this.target) : errorReply = null;
  const _SocksRequestResult.error(this.errorReply) : target = null;
}

class _IoSshSocket implements SSHSocket {
  final Socket _socket;
  _IoSshSocket(this._socket);

  @override
  Stream<Uint8List> get stream => _socket;
  @override
  StreamSink<List<int>> get sink => _socket;
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> close() => _socket.close();
  @override
  void destroy() => _socket.destroy();
}

class _WebSocketSshSocket implements SSHSocket {
  final WebSocket _socket;
  late final Stream<Uint8List> _stream = _socket
      .where((data) => data is List<int>)
      .cast<List<int>>()
      .map(Uint8List.fromList);
  late final StreamSink<List<int>> _sink = _WebSocketByteSink(_socket);

  _WebSocketSshSocket(this._socket);

  @override
  Stream<Uint8List> get stream => _stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  void destroy() => _socket.close();
}

class _WebSocketByteSink implements StreamSink<List<int>> {
  final WebSocket _socket;
  _WebSocketByteSink(this._socket);

  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() => _socket.close();
  @override
  Future<void> get done => _socket.done;
}
