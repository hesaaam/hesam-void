import 'dart:async';
import 'dart:io';
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
/// Provides SOCKS5-like local port forwarding for SSH connections
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
  
  // Local proxy server
  ServerSocket? _proxyServer;
  int _localPort = 1080; // Default SOCKS port
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

  /// Connect to SSH server and start local port forwarding
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

      // Start local SOCKS-like proxy server
      await _startProxyServer(config);

      _status = SshStatus.connected;
      _connectedAt = DateTime.now();
      _startStatsTimer();
      
      if (kDebugMode) {
        debugPrint('[SSH] Connected! Local proxy: $proxyAddress');
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

  /// Start local proxy server that forwards traffic through SSH
  Future<void> _startProxyServer(SshConfig config) async {
    // Try preferred ports first, then fall back to random
    for (final port in _preferredPorts) {
      try {
        _proxyServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _localPort = port;
        
        if (kDebugMode) {
          debugPrint('[SSH] Proxy server started on port $_localPort');
        }

        // Handle incoming connections
        _proxyServer!.listen(
          (Socket clientSocket) async {
            await _handleProxyConnection(clientSocket, config);
          },
          onError: (error) {
            if (kDebugMode) {
              debugPrint('[SSH] Proxy server error: $error');
            }
          },
        );
        
        return; // Success, exit loop
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SSH] Port $port in use, trying next...');
        }
        continue; // Try next port
      }
    }
    
    // All preferred ports failed, try a random port
    try {
      _proxyServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0, // Let OS assign a free port
      );
      _localPort = _proxyServer!.port;
      
      if (kDebugMode) {
        debugPrint('[SSH] Proxy server started on random port $_localPort');
      }

      _proxyServer!.listen(
        (Socket clientSocket) async {
          await _handleProxyConnection(clientSocket, config);
        },
        onError: (error) {
          if (kDebugMode) {
            debugPrint('[SSH] Proxy server error: $error');
          }
        },
      );
    } catch (e) {
      throw Exception('Failed to start proxy server: $e');
    }
  }

  /// Handle individual proxy connection
  Future<void> _handleProxyConnection(Socket clientSocket, SshConfig config) async {
    _activeConnections.add(clientSocket);
    _updateStats();

    try {
      // Read initial data to determine target
      final initialData = await clientSocket.first;
      
      // Simple HTTP proxy handling - extract target host:port from CONNECT request
      String targetHost = 'google.com';
      int targetPort = 80;

      final request = String.fromCharCodes(initialData);
      if (request.startsWith('CONNECT ')) {
        // HTTPS CONNECT request
        final match = RegExp(r'CONNECT ([^:]+):(\d+)').firstMatch(request);
        if (match != null) {
          targetHost = match.group(1)!;
          targetPort = int.parse(match.group(2)!);
        }
        
        // Send 200 OK response
        clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        
      } else if (request.startsWith('GET ') || request.startsWith('POST ')) {
        // HTTP request - extract host from header
        final hostMatch = RegExp(r'Host: ([^\r\n:]+)(?::(\d+))?').firstMatch(request);
        if (hostMatch != null) {
          targetHost = hostMatch.group(1)!;
          targetPort = int.tryParse(hostMatch.group(2) ?? '80') ?? 80;
        }
      }

      if (kDebugMode) {
        debugPrint('[SSH] Forwarding to $targetHost:$targetPort');
      }

      // Create SSH port forward to target
      final forward = await _client!.forwardLocal(targetHost, targetPort);

      // Pipe data between client and SSH tunnel
      int uploaded = 0;
      int downloaded = 0;

      // Client -> SSH tunnel
      clientSocket.listen(
        (data) {
          forward.sink.add(data);
          uploaded += data.length;
          _totalUpload += data.length;
        },
        onError: (_) {},
        onDone: () {
          forward.sink.close();
        },
      );

      // SSH tunnel -> Client
      forward.stream.listen(
        (data) {
          clientSocket.add(data);
          downloaded += data.length;
          _totalDownload += data.length;
        },
        onError: (_) {},
        onDone: () {
          clientSocket.close();
        },
      );

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SSH] Forward error: $e');
      }
    } finally {
      _activeConnections.remove(clientSocket);
      _updateStats();
    }
  }

  /// Disconnect SSH connection
  Future<void> disconnect() async {
    _status = SshStatus.disconnecting;
    notifyListeners();

    try {
      // Stop stats timer
      _statsTimer?.cancel();
      _statsTimer = null;

      // Close all active connections
      for (final socket in _activeConnections) {
        try {
          await socket.close();
        } catch (_) {}
      }
      _activeConnections.clear();

      // Close proxy server
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
