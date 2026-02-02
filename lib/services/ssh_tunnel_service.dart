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
/// Implements SOCKS5 proxy by using forwardLocal for each connection
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
        debugPrint('[SSH] Connecting to ${config.sshHost}:${config.sshPort}');
        debugPrint('[SSH] Username: ${config.sshUsername}');
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
          (socket) => _handleSocks5Client(socket),
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
    
    _proxyServer!.listen(
      (socket) => _handleSocks5Client(socket),
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[SSH] SOCKS5 server error: $error');
        }
      },
    );
  }

  /// Handle SOCKS5 client connection - COMPLETE REWRITE
  void _handleSocks5Client(Socket clientSocket) async {
    _activeConnectionCount++;
    _updateStats();

    if (kDebugMode) {
      debugPrint('[SOCKS5] New connection #$_activeConnectionCount');
    }

    // Buffer to collect all incoming data
    final dataBuffer = <int>[];
    StreamSubscription<Uint8List>? subscription;
    bool handshakeComplete = false;
    String? targetHost;
    int? targetPort;
    SSHForwardChannel? sshChannel;

    try {
      subscription = clientSocket.listen(
        (Uint8List data) async {
          dataBuffer.addAll(data);

          // Process SOCKS5 handshake
          if (!handshakeComplete) {
            // Step 1: Version/Method selection (minimum 3 bytes: VER + NMETHODS + METHOD)
            if (dataBuffer.length >= 3 && dataBuffer[0] == 0x05) {
              final numMethods = dataBuffer[1];
              final expectedLen = 2 + numMethods;
              
              if (dataBuffer.length >= expectedLen) {
                // Send method selection response (no auth)
                clientSocket.add([0x05, 0x00]);
                dataBuffer.removeRange(0, expectedLen);
                
                if (kDebugMode) {
                  debugPrint('[SOCKS5] Handshake phase 1 complete');
                }
              }
            }

            // Step 2: Connection request (minimum 10 bytes for IPv4)
            if (dataBuffer.length >= 4 && dataBuffer[0] == 0x05 && dataBuffer[1] == 0x01) {
              final addressType = dataBuffer[3];
              int headerLen = 4;
              
              if (addressType == 0x01) {
                // IPv4: 4 bytes address + 2 bytes port
                if (dataBuffer.length >= 10) {
                  targetHost = '${dataBuffer[4]}.${dataBuffer[5]}.${dataBuffer[6]}.${dataBuffer[7]}';
                  targetPort = (dataBuffer[8] << 8) | dataBuffer[9];
                  headerLen = 10;
                }
              } else if (addressType == 0x03) {
                // Domain: 1 byte length + domain + 2 bytes port
                if (dataBuffer.length >= 5) {
                  final domainLen = dataBuffer[4];
                  if (dataBuffer.length >= 5 + domainLen + 2) {
                    targetHost = String.fromCharCodes(dataBuffer.sublist(5, 5 + domainLen));
                    targetPort = (dataBuffer[5 + domainLen] << 8) | dataBuffer[5 + domainLen + 1];
                    headerLen = 5 + domainLen + 2;
                  }
                }
              } else if (addressType == 0x04) {
                // IPv6: 16 bytes address + 2 bytes port
                if (dataBuffer.length >= 22) {
                  final ipBytes = dataBuffer.sublist(4, 20);
                  targetHost = _formatIPv6(ipBytes);
                  targetPort = (dataBuffer[20] << 8) | dataBuffer[21];
                  headerLen = 22;
                }
              }

              if (targetHost != null && targetPort != null) {
                if (kDebugMode) {
                  debugPrint('[SOCKS5] Target: $targetHost:$targetPort');
                }

                // Remove processed header
                dataBuffer.removeRange(0, headerLen);
                handshakeComplete = true;

                // Create SSH tunnel to target
                try {
                  sshChannel = await _client!.forwardLocal(targetHost!, targetPort!);
                  
                  // Send success response
                  clientSocket.add([
                    0x05, 0x00, 0x00, 0x01,
                    127, 0, 0, 1,
                    (_localPort >> 8) & 0xFF, _localPort & 0xFF,
                  ]);

                  if (kDebugMode) {
                    debugPrint('[SOCKS5] Tunnel established to $targetHost:$targetPort');
                  }

                  // If there's remaining data in buffer, send it through tunnel
                  if (dataBuffer.isNotEmpty) {
                    sshChannel!.sink.add(Uint8List.fromList(dataBuffer));
                    _totalUpload += dataBuffer.length;
                    dataBuffer.clear();
                  }

                  // Forward SSH responses back to client
                  sshChannel!.stream.listen(
                    (data) {
                      try {
                        clientSocket.add(data);
                        _totalDownload += data.length;
                        _updateStats();
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
                    },
                  );

                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('[SOCKS5] SSH forward failed: $e');
                  }
                  // Send connection refused
                  clientSocket.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
                  clientSocket.close();
                }
              }
            }
          } else {
            // Handshake complete - forward data through SSH tunnel
            if (sshChannel != null) {
              try {
                sshChannel!.sink.add(Uint8List.fromList(dataBuffer));
                _totalUpload += dataBuffer.length;
                _updateStats();
                dataBuffer.clear();
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[SOCKS5] Upload error: $e');
                }
              }
            }
          }
        },
        onError: (e) {
          if (kDebugMode) {
            debugPrint('[SOCKS5] Client error: $e');
          }
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[SOCKS5] Client disconnected');
          }
          sshChannel?.sink.close();
          _activeConnectionCount--;
          _updateStats();
        },
        cancelOnError: false,
      );

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SOCKS5] Handler error: $e');
      }
      try {
        clientSocket.close();
      } catch (_) {}
      _activeConnectionCount--;
      _updateStats();
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
