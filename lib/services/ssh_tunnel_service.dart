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
/// Based on the OFFICIAL dartssh2 forward_local.dart example
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

      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════════════════');
        debugPrint('[SSH] Connecting to ${config.sshHost}:${config.sshPort}');
        debugPrint('[SSH] Username: ${config.sshUsername}');
        debugPrint('[SSH] Password: ${config.sshPassword.isNotEmpty ? "***" : "(empty)"}');
        debugPrint('═══════════════════════════════════════════════════');
      }

      // Create SSH socket connection with timeout
      final socket = await SSHSocket.connect(
        config.sshHost,
        config.sshPort,
        timeout: const Duration(seconds: 30),
      );

      if (kDebugMode) {
        debugPrint('[SSH] Socket connected, authenticating...');
      }

      // Create SSH client with password authentication
      _client = SSHClient(
        socket,
        username: config.sshUsername,
        onPasswordRequest: () => config.sshPassword,
      );

      // Wait for authentication to complete
      await _client!.authenticated;

      if (kDebugMode) {
        debugPrint('[SSH] ✓ Authentication successful!');
        debugPrint('[SSH] Remote version: ${_client!.remoteVersion}');
      }

      // Start local SOCKS5 proxy server
      await _startSocks5Server();

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      
      if (kDebugMode) {
        debugPrint('[SSH] ✓ SOCKS5 proxy started on $proxyAddress');
        debugPrint('[SSH] ✓ SSH tunnel is ready!');
      }

      notifyListeners();
      return true;

    } catch (e) {
      _status = SshStatus.error;
      _errorMessage = _parseError(e);
      
      if (kDebugMode) {
        debugPrint('[SSH] ✗ Connection error: $e');
      }
      
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
        
        if (kDebugMode) {
          debugPrint('[SOCKS5] Server bound to port $_localPort');
        }
        
        // Listen for incoming connections
        _proxyServer!.listen(
          _handleSocks5Connection,
          onError: (error) {
            if (kDebugMode) {
              debugPrint('[SOCKS5] Server error: $error');
            }
          },
        );
        
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SOCKS5] Port $port in use, trying next...');
        }
        continue;
      }
    }
    
    // Fallback: use random port
    _proxyServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _proxyServer!.port;
    
    _proxyServer!.listen(
      _handleSocks5Connection,
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[SOCKS5] Server error: $error');
        }
      },
    );
  }

  /// Handle SOCKS5 connection - COMPLETE REWRITE
  /// Uses StreamController for proper data flow control
  void _handleSocks5Connection(Socket clientSocket) async {
    _activeConnectionCount++;
    _clientSockets.add(clientSocket);
    _updateStats();

    if (kDebugMode) {
      debugPrint('[SOCKS5] New connection #$_activeConnectionCount');
    }

    // Use a completer for the handshake phase
    final handshakeCompleter = Completer<_Socks5Target?>();
    final buffer = <int>[];
    int handshakeState = 0; // 0: waiting for greeting, 1: waiting for request, 2: done
    StreamSubscription<Uint8List>? subscription;

    subscription = clientSocket.listen(
      (data) {
        buffer.addAll(data);
        
        if (handshakeState == 0) {
          // State 0: Parse greeting
          if (buffer.length >= 2) {
            if (buffer[0] != 0x05) {
              handshakeCompleter.complete(null);
              return;
            }
            final numMethods = buffer[1];
            if (buffer.length >= 2 + numMethods) {
              // Send response: no auth required
              clientSocket.add([0x05, 0x00]);
              buffer.removeRange(0, 2 + numMethods);
              handshakeState = 1;
            }
          }
        }
        
        if (handshakeState == 1) {
          // State 1: Parse connection request
          if (buffer.length >= 4) {
            if (buffer[0] != 0x05 || buffer[1] != 0x01) {
              // Not CONNECT command
              clientSocket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
              handshakeCompleter.complete(null);
              return;
            }
            
            final addressType = buffer[3];
            String? targetHost;
            int? targetPort;
            int headerLen = 4;
            
            if (addressType == 0x01) {
              // IPv4
              if (buffer.length >= 10) {
                targetHost = '${buffer[4]}.${buffer[5]}.${buffer[6]}.${buffer[7]}';
                targetPort = (buffer[8] << 8) | buffer[9];
                headerLen = 10;
              }
            } else if (addressType == 0x03) {
              // Domain
              if (buffer.length >= 5) {
                final domainLen = buffer[4];
                if (buffer.length >= 5 + domainLen + 2) {
                  targetHost = String.fromCharCodes(buffer.sublist(5, 5 + domainLen));
                  targetPort = (buffer[5 + domainLen] << 8) | buffer[5 + domainLen + 1];
                  headerLen = 5 + domainLen + 2;
                }
              }
            } else if (addressType == 0x04) {
              // IPv6
              if (buffer.length >= 22) {
                final ipBytes = buffer.sublist(4, 20);
                targetHost = _formatIPv6(ipBytes);
                targetPort = (buffer[20] << 8) | buffer[21];
                headerLen = 22;
              }
            } else {
              clientSocket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
              handshakeCompleter.complete(null);
              return;
            }
            
            if (targetHost != null && targetPort != null) {
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
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(null);
        }
      },
      onDone: () {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(null);
        }
      },
    );

    // Wait for handshake to complete
    final target = await handshakeCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    // Cancel the handshake listener
    await subscription.cancel();

    if (target == null) {
      if (kDebugMode) {
        debugPrint('[SOCKS5] Handshake failed');
      }
      try {
        clientSocket.close();
      } catch (_) {}
      _activeConnectionCount--;
      _clientSockets.remove(clientSocket);
      _updateStats();
      return;
    }

    if (kDebugMode) {
      debugPrint('[SOCKS5] → Target: ${target.host}:${target.port}');
    }

    // Create SSH tunnel to target
    SSHForwardChannel? sshChannel;
    try {
      sshChannel = await _client!.forwardLocal(target.host, target.port);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SOCKS5] ✗ SSH forward failed: $e');
      }
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

    if (kDebugMode) {
      debugPrint('[SOCKS5] ✓ Tunnel established to ${target.host}:${target.port}');
    }

    // Send any remaining data from handshake buffer
    if (target.remainingData != null && target.remainingData!.isNotEmpty) {
      sshChannel.sink.add(target.remainingData!);
      _totalUpload += target.remainingData!.length;
    }

    // NOW USE PIPE - This is the key to making it work!
    // Based on official dartssh2 forward_local.dart example
    try {
      // Client → SSH (upload)
      final uploadFuture = clientSocket
          .map((data) {
            _totalUpload += data.length;
            _updateStats();
            return data;
          })
          .cast<List<int>>()
          .pipe(sshChannel.sink);

      // SSH → Client (download)
      final downloadFuture = sshChannel.stream
          .map((data) {
            _totalDownload += data.length;
            _updateStats();
            return data;
          })
          .cast<List<int>>()
          .pipe(clientSocket);

      // Wait for either direction to complete (connection closed)
      await Future.any([uploadFuture, downloadFuture]);

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SOCKS5] Pipe error: $e');
      }
    }

    // Clean up
    try {
      await clientSocket.close();
    } catch (_) {}

    if (kDebugMode) {
      debugPrint('[SOCKS5] Connection to ${target.host}:${target.port} closed');
    }

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
      // Stop stats timer
      _statsTimer?.cancel();
      _statsTimer = null;

      // Close all client sockets
      for (final socket in _clientSockets) {
        try {
          socket.close();
        } catch (_) {}
      }
      _clientSockets.clear();

      // Close SOCKS5 proxy server
      await _proxyServer?.close();
      _proxyServer = null;

      // Close SSH client
      _client?.close();
      await _client?.done;
      _client = null;

      if (kDebugMode) {
        debugPrint('[SSH] Disconnected');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SSH] Disconnect error: $e');
      }
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

  /// Start statistics update timer
  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateStats();
    });
  }

  /// Update connection statistics
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

  /// Parse error message for user-friendly display
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

  /// Clear error message
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

/// SOCKS5 target information
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
