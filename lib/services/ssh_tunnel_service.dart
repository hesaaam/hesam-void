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

  String get uploadStr => _formatBytes(uploadBytes);
  String get downloadStr => _formatBytes(downloadBytes);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Real SSH Tunnel Service using dartssh2
/// Provides a proper SOCKS5 proxy server that forwards traffic through SSH
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
  final List<Socket> _activeConnections = [];

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
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[SSH] Connecting to ${config.sshHost}:${config.sshPort}');
        debugPrint('[SSH] Username: ${config.sshUsername}');
        debugPrint('[SSH] Config type: ${config.configType.displayName}');
      }

      // Create SSH socket connection
      final socket = await SSHSocket.connect(
        config.sshHost,
        config.sshPort,
        timeout: const Duration(seconds: 30),
      );

      // Create SSH client with password authentication
      _client = SSHClient(
        socket,
        username: config.sshUsername,
        onPasswordRequest: () => config.sshPassword,
      );

      // Wait for authentication
      await _client!.authenticated;

      if (kDebugMode) {
        debugPrint('[SSH] Authentication successful!');
        debugPrint('[SSH] Remote version: ${_client!.remoteVersion}');
      }

      // Start local SOCKS5 proxy server
      await _startSocks5Server();

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      
      if (kDebugMode) {
        debugPrint('[SSH] SOCKS5 proxy started on $proxyAddress');
      }

      notifyListeners();
      return true;

    } catch (e) {
      _status = SshStatus.error;
      _errorMessage = _parseError(e);
      
      if (kDebugMode) {
        debugPrint('[SSH] Connection error: $e');
      }
      
      notifyListeners();
      return false;
    }
  }

  /// Start SOCKS5 proxy server
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
          debugPrint('[SSH] SOCKS5 server bound to port $_localPort');
        }

        // Handle incoming SOCKS5 connections
        _proxyServer!.listen(
          _handleSocks5Client,
          onError: (error) {
            if (kDebugMode) {
              debugPrint('[SSH] SOCKS5 server error: $error');
            }
          },
        );
        
        return; // Success
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SSH] Port $port in use, trying next...');
        }
        continue;
      }
    }
    
    // Try random port as fallback
    _proxyServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _proxyServer!.port;
    
    if (kDebugMode) {
      debugPrint('[SSH] SOCKS5 server on random port $_localPort');
    }

    _proxyServer!.listen(
      _handleSocks5Client,
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[SSH] SOCKS5 server error: $error');
        }
      },
    );
  }

  /// Handle SOCKS5 client connection
  void _handleSocks5Client(Socket clientSocket) async {
    _activeConnections.add(clientSocket);
    _updateStats();

    if (kDebugMode) {
      debugPrint('[SOCKS5] New client connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
    }

    try {
      // SOCKS5 Handshake Phase 1: Method Selection
      final methodRequest = await _readBytes(clientSocket, 2);
      if (methodRequest == null || methodRequest[0] != 0x05) {
        if (kDebugMode) {
          debugPrint('[SOCKS5] Invalid SOCKS version: ${methodRequest?[0]}');
        }
        clientSocket.close();
        return;
      }

      final numMethods = methodRequest[1];
      final methods = await _readBytes(clientSocket, numMethods);
      if (methods == null) {
        clientSocket.close();
        return;
      }

      // Reply: SOCKS5, no authentication required
      clientSocket.add([0x05, 0x00]);

      // SOCKS5 Phase 2: Connection Request
      final request = await _readBytes(clientSocket, 4);
      if (request == null || request[0] != 0x05 || request[1] != 0x01) {
        if (kDebugMode) {
          debugPrint('[SOCKS5] Invalid request: ${request?.map((e) => e.toRadixString(16)).join(' ')}');
        }
        // Send error reply
        clientSocket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        clientSocket.close();
        return;
      }

      // Parse destination address
      String targetHost;
      int targetPort;

      final addressType = request[3];
      
      if (addressType == 0x01) {
        // IPv4
        final ipBytes = await _readBytes(clientSocket, 4);
        if (ipBytes == null) {
          clientSocket.close();
          return;
        }
        targetHost = ipBytes.join('.');
      } else if (addressType == 0x03) {
        // Domain name
        final domainLengthBytes = await _readBytes(clientSocket, 1);
        if (domainLengthBytes == null) {
          clientSocket.close();
          return;
        }
        final domainLength = domainLengthBytes[0];
        final domainBytes = await _readBytes(clientSocket, domainLength);
        if (domainBytes == null) {
          clientSocket.close();
          return;
        }
        targetHost = String.fromCharCodes(domainBytes);
      } else if (addressType == 0x04) {
        // IPv6
        final ipBytes = await _readBytes(clientSocket, 16);
        if (ipBytes == null) {
          clientSocket.close();
          return;
        }
        targetHost = _formatIPv6(ipBytes);
      } else {
        if (kDebugMode) {
          debugPrint('[SOCKS5] Unsupported address type: $addressType');
        }
        clientSocket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        clientSocket.close();
        return;
      }

      // Read port (2 bytes, big-endian)
      final portBytes = await _readBytes(clientSocket, 2);
      if (portBytes == null) {
        clientSocket.close();
        return;
      }
      targetPort = (portBytes[0] << 8) | portBytes[1];

      if (kDebugMode) {
        debugPrint('[SOCKS5] Connecting to $targetHost:$targetPort via SSH');
      }

      // Create SSH tunnel to target
      try {
        final sshForward = await _client!.forwardLocal(targetHost, targetPort);

        // Send success reply
        // [VER, REP, RSV, ATYP, BND.ADDR, BND.PORT]
        clientSocket.add([
          0x05, // SOCKS5
          0x00, // Success
          0x00, // Reserved
          0x01, // IPv4
          127, 0, 0, 1, // Bound address (localhost)
          (_localPort >> 8) & 0xFF, _localPort & 0xFF, // Bound port
        ]);

        if (kDebugMode) {
          debugPrint('[SOCKS5] Tunnel established to $targetHost:$targetPort');
        }

        // Bidirectional data forwarding
        final clientSubscription = clientSocket.listen(
          (data) {
            try {
              sshForward.sink.add(data);
              _totalUpload += data.length;
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[SOCKS5] Upload error: $e');
              }
            }
          },
          onError: (e) {
            if (kDebugMode) {
              debugPrint('[SOCKS5] Client error: $e');
            }
          },
          onDone: () {
            sshForward.sink.close();
          },
          cancelOnError: false,
        );

        sshForward.stream.listen(
          (data) {
            try {
              clientSocket.add(data);
              _totalDownload += data.length;
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[SOCKS5] Download error: $e');
              }
            }
          },
          onError: (e) {
            if (kDebugMode) {
              debugPrint('[SOCKS5] SSH stream error: $e');
            }
          },
          onDone: () {
            clientSocket.close();
            clientSubscription.cancel();
          },
          cancelOnError: false,
        );

      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SOCKS5] SSH forward failed: $e');
        }
        // Connection refused or network unreachable
        clientSocket.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        clientSocket.close();
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SOCKS5] Client handler error: $e');
      }
      try {
        clientSocket.close();
      } catch (_) {}
    } finally {
      _activeConnections.remove(clientSocket);
      _updateStats();
    }
  }

  /// Read exact number of bytes from socket
  Future<Uint8List?> _readBytes(Socket socket, int count) async {
    try {
      final completer = Completer<Uint8List?>();
      final buffer = BytesBuilder();
      late StreamSubscription subscription;
      
      subscription = socket.listen(
        (data) {
          buffer.add(data);
          if (buffer.length >= count) {
            subscription.cancel();
            final result = buffer.toBytes();
            completer.complete(Uint8List.fromList(result.sublist(0, count)));
          }
        },
        onError: (e) {
          subscription.cancel();
          completer.complete(null);
        },
        onDone: () {
          subscription.cancel();
          if (buffer.length >= count) {
            final result = buffer.toBytes();
            completer.complete(Uint8List.fromList(result.sublist(0, count)));
          } else {
            completer.complete(null);
          }
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          subscription.cancel();
          return null;
        },
      );
    } catch (e) {
      return null;
    }
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

      // Close all active connections
      for (final socket in List.from(_activeConnections)) {
        try {
          await socket.close();
        } catch (_) {}
      }
      _activeConnections.clear();

      // Close SOCKS5 proxy server
      await _proxyServer?.close();
      _proxyServer = null;

      // Close SSH client
      _client?.close();
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
      activeConnections: _activeConnections.length,
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
