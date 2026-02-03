import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/ssh_config.dart';

/// SSH Connection States
enum SshStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// SSH Tunnel Statistics
class SshStats {
  final int uploadBytes;
  final int downloadBytes;
  final String duration;
  final int activeConnections;

  SshStats({
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.duration = '00:00:00',
    this.activeConnections = 0,
  });
}

/// Real SSH Tunnel Service using dartssh2
/// Creates a local SOCKS5 proxy that forwards all traffic through SSH tunnel
class SshTunnelService extends ChangeNotifier {
  static final SshTunnelService _instance = SshTunnelService._internal();
  factory SshTunnelService() => _instance;
  SshTunnelService._internal();

  // SSH Client instance
  SSHClient? _client;
  
  // Connection state
  SshStatus _status = SshStatus.disconnected;
  SshConfig? _currentConfig;
  SshStats _stats = SshStats();
  String? _errorMessage;
  
  // Local SOCKS5 proxy server
  ServerSocket? _proxyServer;
  int _localPort = 1080;
  static const List<int> _preferredPorts = [1080, 1081, 8080, 8888, 9050, 7890];
  
  // Connection tracking
  int _totalUpload = 0;
  int _totalDownload = 0;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  int _activeConnectionCount = 0;
  final List<Socket> _clientSockets = [];

  // Getters
  SshStatus get status => _status;
  SshConfig? get currentConfig => _currentConfig;
  SshStats get stats => _stats;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == SshStatus.connected;
  bool get isConnecting => _status == SshStatus.connecting;
  int get localPort => _localPort;
  String get proxyAddress => '127.0.0.1:$_localPort';

  /// Connect to SSH server and start SOCKS5 proxy
  Future<bool> connect(SshConfig config, {int localPort = 1080}) async {
    if (kIsWeb) {
      _errorMessage = 'SSH not supported on web platform';
      notifyListeners();
      return false;
    }

    // Disconnect existing connection
    if (_status == SshStatus.connected) {
      await disconnect();
    }

    try {
      _status = SshStatus.connecting;
      _currentConfig = config;
      _localPort = localPort;
      _errorMessage = null;
      _totalUpload = 0;
      _totalDownload = 0;
      notifyListeners();

      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('[SSH] Connecting to ${config.sshHost}:${config.sshPort}');
      debugPrint('[SSH] Username: ${config.sshUsername}');
      debugPrint('[SSH] Password length: ${config.sshPassword.length}');
      debugPrint('═══════════════════════════════════════════════════');

      // Create SSH socket connection with timeout
      final socket = await SSHSocket.connect(
        config.sshHost,
        config.sshPort,
        timeout: const Duration(seconds: 30),
      );

      debugPrint('[SSH] ✓ Socket connected!');

      // Create SSH client with password authentication
      _client = SSHClient(
        socket,
        username: config.sshUsername,
        onPasswordRequest: () {
          debugPrint('[SSH] Password requested, providing...');
          return config.sshPassword;
        },
      );

      // Wait for authentication to complete
      debugPrint('[SSH] Waiting for authentication...');
      await _client!.authenticated;

      debugPrint('[SSH] ✓ Authentication successful!');
      debugPrint('[SSH] Remote version: ${_client!.remoteVersion}');

      // TEST: Try to open a test channel to verify forwarding works
      debugPrint('[SSH] Testing port forwarding capability...');
      try {
        final testChannel = await _client!.forwardLocal('www.google.com', 80);
        debugPrint('[SSH] ✓ Test channel opened successfully!');
        await testChannel.sink.close();
      } catch (e) {
        debugPrint('[SSH] ⚠ Test channel failed: $e');
        debugPrint('[SSH] Server may not allow TCP forwarding');
      }

      // Start local SOCKS5 proxy server
      await _startSocks5Server();

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      
      debugPrint('[SSH] ✓ SOCKS5 proxy started on $proxyAddress');
      debugPrint('[SSH] ✓ SSH tunnel is ready!');

      notifyListeners();
      return true;

    } catch (e) {
      _status = SshStatus.error;
      _errorMessage = _parseError(e);
      
      debugPrint('[SSH] ✗ Connection error: $e');
      
      notifyListeners();
      return false;
    }
  }

  /// Start SOCKS5 proxy server - listens for incoming connections
  Future<void> _startSocks5Server() async {
    // Try preferred ports first
    for (final port in _preferredPorts) {
      try {
        _proxyServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _localPort = port;
        
        debugPrint('[SOCKS5] Server bound to port $_localPort');
        
        // Listen for incoming connections
        _proxyServer!.listen(
          _handleSocks5Connection,
          onError: (error) {
            debugPrint('[SOCKS5] Server error: $error');
          },
        );
        
        return;
      } catch (e) {
        debugPrint('[SOCKS5] Port $port in use, trying next...');
        continue;
      }
    }
    
    // Fallback: use random port
    _proxyServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _proxyServer!.port;
    
    _proxyServer!.listen(
      _handleSocks5Connection,
      onError: (error) {
        debugPrint('[SOCKS5] Server error: $error');
      },
    );
  }

  /// Handle SOCKS5 connection
  void _handleSocks5Connection(Socket clientSocket) async {
    _activeConnectionCount++;
    _clientSockets.add(clientSocket);
    _updateStats();

    debugPrint('[SOCKS5] ═══ New connection #$_activeConnectionCount ═══');

    // Use a completer for the handshake phase
    final handshakeCompleter = Completer<_Socks5Target?>();
    final buffer = <int>[];
    int handshakeState = 0;
    StreamSubscription<Uint8List>? subscription;

    subscription = clientSocket.listen(
      (data) {
        debugPrint('[SOCKS5] Received ${data.length} bytes in state $handshakeState');
        buffer.addAll(data);
        
        if (handshakeState == 0) {
          if (buffer.length >= 2) {
            if (buffer[0] != 0x05) {
              debugPrint('[SOCKS5] Invalid version: ${buffer[0]}');
              handshakeCompleter.complete(null);
              return;
            }
            final numMethods = buffer[1];
            if (buffer.length >= 2 + numMethods) {
              debugPrint('[SOCKS5] Greeting received, sending no-auth response');
              clientSocket.add([0x05, 0x00]);
              buffer.removeRange(0, 2 + numMethods);
              handshakeState = 1;
            }
          }
        }
        
        if (handshakeState == 1) {
          if (buffer.length >= 4) {
            debugPrint('[SOCKS5] Request header: ${buffer.take(4).toList()}');
            if (buffer[0] != 0x05 || buffer[1] != 0x01) {
              debugPrint('[SOCKS5] Invalid command: ${buffer[1]}');
              clientSocket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
              handshakeCompleter.complete(null);
              return;
            }
            
            final addressType = buffer[3];
            String? targetHost;
            int? targetPort;
            int headerLen = 4;
            
            if (addressType == 0x01) {
              if (buffer.length >= 10) {
                targetHost = '${buffer[4]}.${buffer[5]}.${buffer[6]}.${buffer[7]}';
                targetPort = (buffer[8] << 8) | buffer[9];
                headerLen = 10;
              }
            } else if (addressType == 0x03) {
              if (buffer.length >= 5) {
                final domainLen = buffer[4];
                if (buffer.length >= 5 + domainLen + 2) {
                  targetHost = String.fromCharCodes(buffer.sublist(5, 5 + domainLen));
                  targetPort = (buffer[5 + domainLen] << 8) | buffer[5 + domainLen + 1];
                  headerLen = 5 + domainLen + 2;
                }
              }
            } else if (addressType == 0x04) {
              if (buffer.length >= 22) {
                final ipBytes = buffer.sublist(4, 20);
                targetHost = _formatIPv6(ipBytes);
                targetPort = (buffer[20] << 8) | buffer[21];
                headerLen = 22;
              }
            } else {
              debugPrint('[SOCKS5] Unsupported address type: $addressType');
              clientSocket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
              handshakeCompleter.complete(null);
              return;
            }
            
            if (targetHost != null && targetPort != null) {
              debugPrint('[SOCKS5] Target parsed: $targetHost:$targetPort');
              buffer.removeRange(0, headerLen);
              handshakeState = 2;
              handshakeCompleter.complete(_Socks5Target(
                host: targetHost,
                port: targetPort,
                remainingData: buffer.isNotEmpty ? Uint8List.fromList(buffer) : null,
              ));
            }
          }
        }
      },
      onError: (e) {
        debugPrint('[SOCKS5] Client stream error: $e');
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(null);
        }
      },
      onDone: () {
        debugPrint('[SOCKS5] Client stream done');
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(null);
        }
      },
    );

    // Wait for handshake to complete
    final target = await handshakeCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[SOCKS5] Handshake timeout!');
        return null;
      },
    );

    // Cancel the handshake listener
    await subscription.cancel();

    if (target == null) {
      debugPrint('[SOCKS5] Handshake failed, closing connection');
      try {
        clientSocket.close();
      } catch (_) {}
      _activeConnectionCount--;
      _clientSockets.remove(clientSocket);
      _updateStats();
      return;
    }

    debugPrint('[SOCKS5] ══════════════════════════════════════');
    debugPrint('[SOCKS5] → Creating tunnel to ${target.host}:${target.port}');
    debugPrint('[SOCKS5] ══════════════════════════════════════');

    // Create SSH tunnel to target
    SSHForwardChannel? sshChannel;
    try {
      debugPrint('[SOCKS5] Calling forwardLocal...');
      sshChannel = await _client!.forwardLocal(target.host, target.port);
      debugPrint('[SOCKS5] ✓ forwardLocal succeeded!');
    } catch (e) {
      debugPrint('[SOCKS5] ✗ forwardLocal FAILED: $e');
      clientSocket.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      clientSocket.close();
      _activeConnectionCount--;
      _clientSockets.remove(clientSocket);
      _updateStats();
      return;
    }

    // Send success response
    clientSocket.add([
      0x05, 0x00, 0x00, 0x01,
      127, 0, 0, 1,
      (_localPort >> 8) & 0xFF, _localPort & 0xFF,
    ]);

    debugPrint('[SOCKS5] ✓ Sent success response to client');

    // Send any remaining data from handshake buffer
    if (target.remainingData != null && target.remainingData!.isNotEmpty) {
      debugPrint('[SOCKS5] Sending ${target.remainingData!.length} bytes of remaining data');
      sshChannel.sink.add(target.remainingData!);
      _totalUpload += target.remainingData!.length;
    }

    // Bidirectional piping
    debugPrint('[SOCKS5] Starting bidirectional pipe...');
    try {
      // Client → SSH (upload)
      final uploadFuture = clientSocket
          .map((data) {
            debugPrint('[SOCKS5] Upload: ${data.length} bytes');
            _totalUpload += data.length;
            _updateStats();
            return data;
          })
          .cast<List<int>>()
          .pipe(sshChannel.sink);

      // SSH → Client (download)
      final downloadFuture = sshChannel.stream
          .map((data) {
            debugPrint('[SOCKS5] Download: ${data.length} bytes');
            _totalDownload += data.length;
            _updateStats();
            return data;
          })
          .cast<List<int>>()
          .pipe(clientSocket);

      // Wait for either direction to complete
      await Future.any([uploadFuture, downloadFuture]);

      debugPrint('[SOCKS5] Pipe completed');
    } catch (e) {
      debugPrint('[SOCKS5] Pipe error: $e');
    }

    // Clean up
    try {
      await clientSocket.close();
    } catch (_) {}

    debugPrint('[SOCKS5] Connection to ${target.host}:${target.port} closed');

    _activeConnectionCount--;
    _clientSockets.remove(clientSocket);
    _updateStats();
  }

  /// Format IPv6 address
  String _formatIPv6(List<int> bytes) {
    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      final value = (bytes[i] << 8) | bytes[i + 1];
      parts.add(value.toRadixString(16));
    }
    return parts.join(':');
  }

  /// Disconnect SSH connection and stop SOCKS5 server
  Future<void> disconnect() async {
    _status = SshStatus.disconnecting;
    notifyListeners();

    try {
      _statsTimer?.cancel();
      _statsTimer = null;

      for (final socket in _clientSockets) {
        try {
          socket.close();
        } catch (_) {}
      }
      _clientSockets.clear();

      await _proxyServer?.close();
      _proxyServer = null;

      _client?.close();
      await _client?.done;
      _client = null;

      debugPrint('[SSH] Disconnected');

    } catch (e) {
      debugPrint('[SSH] Disconnect error: $e');
    }

    _status = SshStatus.disconnected;
    _currentConfig = null;
    _connectedAt = null;
    _totalUpload = 0;
    _totalDownload = 0;
    _activeConnectionCount = 0;
    _stats = SshStats();
    
    notifyListeners();
  }

  /// Test SSH connection (ping)
  Future<int> testConnection(SshConfig config) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final socket = await SSHSocket.connect(
        config.sshHost,
        config.sshPort,
        timeout: const Duration(seconds: 10),
      );

      final client = SSHClient(
        socket,
        username: config.sshUsername,
        onPasswordRequest: () => config.sshPassword,
      );

      await client.authenticated;
      client.close();
      
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;

    } catch (e) {
      stopwatch.stop();
      return -1;
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateStats();
    });
  }

  void _updateStats() {
    final duration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;

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

  String _parseError(dynamic error) {
    final msg = error.toString();
    
    if (msg.contains('Connection refused')) {
      return 'Connection refused. Server may be offline.';
    }
    if (msg.contains('Connection timed out') || msg.contains('timeout')) {
      return 'Connection timeout. Check your network.';
    }
    if (msg.contains('Authentication failed') || msg.contains('not authenticated')) {
      return 'Authentication failed. Check username/password.';
    }
    if (msg.contains('Host key verification failed')) {
      return 'Host key verification failed.';
    }
    if (msg.contains('No route to host')) {
      return 'No route to host. Check server address.';
    }
    if (msg.contains('Network is unreachable')) {
      return 'Network unreachable. Check your connection.';
    }
    
    return 'SSH Error: $msg';
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

class _Socks5Target {
  final String host;
  final int port;
  final Uint8List? remainingData;

  _Socks5Target({
    required this.host,
    required this.port,
    this.remainingData,
  });
}
