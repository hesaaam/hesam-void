import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/vpn_config.dart';
import '../models/ssh_config.dart';
import 'ssh_tunnel_service.dart';
import 'split_tunneling_service.dart';
import 'connection_health_service.dart';
import 'xray_json_config.dart';

/// VPN Connection States
enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Result of the post-connect check that traffic really passes the tunnel.
enum TunnelCheck { idle, checking, verified, failed }

/// Error text recorded when the tunnel is up but no request passes through it.
const String kTunnelNoInternetError =
    'Connected, but no internet passed through the tunnel.';

/// Readable core version from the engine's own report, e.g. "26.7.28".
///
/// The engine answers with text such as "Lib v40, Xray-core v26.7.28"; only
/// the Xray part is shown. Before the engine has started, nothing is known.
String coreVersionLabel(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return 'Available after the engine starts';
  final match = RegExp(
    r'Xray-core\s*v?([0-9]+(?:\.[0-9]+)+)',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1) ?? text;
}

/// Error text recorded when the engine never reports a started tunnel.
const String kEngineStartTimeoutError =
    'The VPN engine did not start this profile.';

/// VPN Connection Statistics
class VpnStats {
  final int uploadSpeed; // bytes per second
  final int downloadSpeed; // bytes per second
  final int totalUpload; // total bytes
  final int totalDownload; // total bytes
  final String duration;

  VpnStats({
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.totalUpload = 0,
    this.totalDownload = 0,
    this.duration = '00:00:00',
  });

  String get uploadSpeedStr => _formatSpeed(uploadSpeed);
  String get downloadSpeedStr => _formatSpeed(downloadSpeed);
  String get totalUploadStr => _formatBytes(totalUpload);
  String get totalDownloadStr => _formatBytes(totalDownload);

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024)
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Bypass LAN subnets - routes only external traffic through VPN
final List<String> bypassSubnets = [
  "0.0.0.0/5",
  "8.0.0.0/7",
  "11.0.0.0/8",
  "12.0.0.0/6",
  "16.0.0.0/4",
  "32.0.0.0/3",
  "64.0.0.0/2",
  "128.0.0.0/3",
  "160.0.0.0/5",
  "168.0.0.0/6",
  "172.0.0.0/12",
  "172.32.0.0/11",
  "172.64.0.0/10",
  "172.128.0.0/9",
  "173.0.0.0/8",
  "174.0.0.0/7",
  "176.0.0.0/4",
  "192.0.0.0/9",
  "192.128.0.0/11",
  "192.160.0.0/13",
  "192.169.0.0/16",
  "192.170.0.0/15",
  "192.172.0.0/14",
  "192.176.0.0/12",
  "192.192.0.0/10",
  "193.0.0.0/8",
  "194.0.0.0/7",
  "196.0.0.0/6",
  "200.0.0.0/5",
  "208.0.0.0/4",
  "240.0.0.0/4",
];

/// Real VPN Service using V2Ray Core
/// Based on flutter_v2ray package official example
class VpnService extends ChangeNotifier {
  static final VpnService _instance = VpnService._internal();
  factory VpnService() => _instance;
  VpnService._internal();

  // CRITICAL: FlutterV2ray instance - must be initialized before use
  late FlutterV2ray flutterV2ray;

  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _currentConfig;
  String? _errorMessage;
  TunnelCheck _tunnelCheck = TunnelCheck.idle;
  int? _tunnelLatencyMs;
  Future<bool>? _verification;
  int _connectionGeneration = 0;
  VoidCallback? _sshListener;

  /// Live traffic statistics. They change every second while connected, so
  /// they are published separately from [notifyListeners] to keep screens
  /// that only care about the connection state from rebuilding every tick.
  final ValueNotifier<VpnStats> statsListenable = ValueNotifier<VpnStats>(
    VpnStats(),
  );
  String? _coreVersion;
  bool _isInitialized = false;
  int? _sshProxyPort; // SSH proxy port when connected
  DateTime? _suppressDropRecordingUntil;

  // Getters
  VpnStatus get status => _status;
  VpnConfig? get currentConfig => _currentConfig;
  VpnStats get stats => statsListenable.value;
  String? get errorMessage => _errorMessage;
  TunnelCheck get tunnelCheck => _tunnelCheck;
  int? get tunnelLatencyMs => _tunnelLatencyMs;
  String? get coreVersion => _coreVersion;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _status == VpnStatus.connected;
  bool get isConnecting => _status == VpnStatus.connecting;
  bool get isDisconnected => _status == VpnStatus.disconnected;

  // SSH specific getters
  int? get sshProxyPort => _sshProxyPort;
  String? get sshProxyAddress =>
      _sshProxyPort != null ? '127.0.0.1:$_sshProxyPort' : null;
  bool get isSshConnection => _currentConfig?.isSsh ?? false;

  /// Initialize V2Ray Core - MUST be called before any VPN operations
  Future<bool> initialize() async {
    if (kIsWeb) {
      _errorMessage = 'VPN not supported on web platform';
      notifyListeners();
      return false;
    }

    if (_isInitialized) return true;

    try {
      // Create FlutterV2ray instance with status callback
      flutterV2ray = FlutterV2ray(onStatusChanged: _onStatusChanged);

      // Initialize V2Ray with notification icon
      await flutterV2ray.initializeV2Ray(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );

      // Get core version to verify initialization
      _coreVersion = await flutterV2ray.getCoreVersion();
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint(
          '[VpnService] V2Ray initialized successfully. Core version: $_coreVersion',
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to initialize V2Ray: $e';
      if (kDebugMode) {
        debugPrint('[VpnService] Initialization error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  /// Handle V2Ray status changes from the core.
  ///
  /// The native core reports its state every second together with traffic
  /// counters. Only real state transitions are treated as events; repeated
  /// ticks just refresh [statsListenable].
  void _onStatusChanged(V2RayStatus v2rayStatus) {
    final previous = _status;

    if (!isSshConnection) {
      statsListenable.value = VpnStats(
        uploadSpeed: v2rayStatus.uploadSpeed,
        downloadSpeed: v2rayStatus.downloadSpeed,
        totalUpload: v2rayStatus.upload,
        totalDownload: v2rayStatus.download,
        duration: v2rayStatus.duration,
      );
    }

    VpnStatus next = previous;
    switch (v2rayStatus.state) {
      case 'CONNECTED':
        next = VpnStatus.connected;
        break;
      case 'DISCONNECTED':
      case 'STOPPED':
        next = VpnStatus.disconnected;
        break;
      case 'CONNECTING':
        next = VpnStatus.connecting;
        break;
      default:
        if (kDebugMode) {
          debugPrint('[VpnService] Unknown state: ${v2rayStatus.state}');
        }
        return;
    }

    if (next == previous) return;
    _status = next;

    if (next == VpnStatus.connected) {
      _errorMessage = null;
      unawaited(verifyTunnel());
    } else if (next == VpnStatus.disconnected) {
      _resetTunnelCheck();
      final config = _currentConfig;
      final dropIsSuppressed =
          _suppressDropRecordingUntil != null &&
          DateTime.now().isBefore(_suppressDropRecordingUntil!);
      if (previous == VpnStatus.connected &&
          config != null &&
          !dropIsSuppressed) {
        unawaited(ConnectionHealthService().recordDrop(config.id));
      }
    }

    notifyListeners();
  }

  /// Confirms that a request really travels through the running tunnel.
  ///
  /// A connected engine is not proof of a working route, so the result is
  /// recorded in local health history and shown to the user.
  Future<bool> verifyTunnel() {
    return _verification ??= _runVerification().whenComplete(() {
      _verification = null;
    });
  }

  Future<bool> _runVerification() async {
    final generation = _connectionGeneration;
    final config = _currentConfig;
    _tunnelCheck = TunnelCheck.checking;
    _tunnelLatencyMs = null;
    notifyListeners();

    // Give the tunnel a moment to install routes before the first request.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    var delay = -1;
    for (var attempt = 0; attempt < 2 && delay <= 0; attempt++) {
      if (generation != _connectionGeneration || !isConnected) return false;
      delay = await getConnectedServerDelay();
      if (delay <= 0 && attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (generation != _connectionGeneration || !isConnected) return false;

    final verified = delay > 0;
    _tunnelCheck = verified ? TunnelCheck.verified : TunnelCheck.failed;
    _tunnelLatencyMs = verified ? delay : null;
    if (config != null) {
      unawaited(
        verified
            ? ConnectionHealthService().recordConnected(
                config.id,
                latencyMs: delay,
              )
            : ConnectionHealthService().recordFailure(
                config.id,
                kTunnelNoInternetError,
              ),
      );
    }
    notifyListeners();
    return verified;
  }

  /// The engine reports nothing when it rejects a profile; it only keeps
  /// announcing "connecting". Stop waiting after [_engineStartTimeout] and
  /// show a clear error instead of an endless spinner.
  static const Duration _engineStartTimeout = Duration(seconds: 20);

  void _watchEngineStartup(VpnConfig config) {
    final generation = _connectionGeneration;
    Timer(_engineStartTimeout, () async {
      if (generation != _connectionGeneration ||
          _status != VpnStatus.connecting) {
        return;
      }
      _suppressDropRecordingUntil = DateTime.now().add(
        const Duration(seconds: 3),
      );
      try {
        await flutterV2ray.stopV2Ray();
      } catch (_) {
        // The engine may not be running at all.
      }
      if (_sshProxyPort != null) {
        _detachSshMonitor();
        await SshTunnelService().disconnect();
        _sshProxyPort = null;
      }
      if (generation != _connectionGeneration) return;
      _resetTunnelCheck();
      _status = VpnStatus.error;
      _errorMessage = kEngineStartTimeoutError;
      unawaited(
        ConnectionHealthService().recordFailure(
          config.id,
          kEngineStartTimeoutError,
        ),
      );
      notifyListeners();
    });
  }

  void _resetTunnelCheck() {
    _connectionGeneration++;
    _tunnelCheck = TunnelCheck.idle;
    _tunnelLatencyMs = null;
  }

  /// Connect to VPN using config - FOLLOWS OFFICIAL flutter_v2ray EXAMPLE
  Future<bool> connect(VpnConfig config) async {
    if (kIsWeb) {
      _errorMessage = 'VPN not supported on web platform';
      notifyListeners();
      return false;
    }

    // Initialize if not done
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Handle SSH configs differently - they require a separate SSH library
    if (config.isSsh) {
      return _connectSsh(config);
    }

    try {
      _resetTunnelCheck();
      _status = VpnStatus.connecting;
      _currentConfig = config;
      _errorMessage = null;
      notifyListeners();

      final (remark, fullConfig) = _engineConfig(config);

      if (kDebugMode) {
        debugPrint('[VpnService] Config parsed successfully. Remark: $remark');
        debugPrint('[VpnService] Config length: ${fullConfig.length} bytes');
      }

      // Request VPN permission - REQUIRED for VPN mode
      bool hasPermission = await flutterV2ray.requestPermission();
      if (!hasPermission) {
        _status = VpnStatus.error;
        _errorMessage = 'VPN permission denied. Please allow VPN permission.';
        notifyListeners();
        return false;
      }

      if (kDebugMode) {
        debugPrint('[VpnService] VPN permission granted. Starting V2Ray...');
      }

      // Resolve selected app routing immediately before starting the tunnel.
      // An empty policy keeps the engine default (all apps through VPN).
      final blockedApps = await _resolveBlockedApps();

      // Start V2Ray with the configuration
      // CRITICAL: proxyOnly = false means VPN mode (routes all traffic)
      // bypassSubnets = bypassSubnets means bypass local network traffic
      await flutterV2ray.startV2Ray(
        remark: remark,
        config: fullConfig,
        blockedApps: blockedApps,
        bypassSubnets: bypassSubnets, // Use bypass subnets for proper routing
        proxyOnly: false, // VPN Mode - routes all traffic through V2Ray
        notificationDisconnectButtonName: "Disconnect",
      );

      if (kDebugMode) {
        debugPrint('[VpnService] V2Ray startV2Ray called successfully');
      }
      _watchEngineStartup(config);

      return true;
    } catch (e) {
      _status = VpnStatus.error;
      _errorMessage = 'Connection failed: $e';
      unawaited(
        ConnectionHealthService().recordFailure(config.id, _errorMessage!),
      );
      if (kDebugMode) {
        debugPrint('[VpnService] Connection error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  /// Remark and full engine JSON for a link or a stored Xray JSON profile.
  (String, String) _engineConfig(VpnConfig config) {
    if (config.isJson) {
      return (config.name, XrayJsonConfig.prepareForEngine(config.rawUrl));
    }
    final parser = FlutterV2ray.parseFromURL(config.rawUrl);
    final remark = parser.remark.isNotEmpty ? parser.remark : config.name;
    return (remark, parser.getFullConfiguration());
  }

  /// Connect to SSH server using dartssh2 + V2Ray VPN mode
  /// This creates SSH tunnel AND routes all device traffic through it
  Future<bool> _connectSsh(VpnConfig config) async {
    final sshService = SshTunnelService();
    try {
      _resetTunnelCheck();
      _status = VpnStatus.connecting;
      _currentConfig = config;
      _errorMessage = null;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[VpnService] SSH Config detected: ${config.name}');
      }

      // The stored link (ssh:// or npvt-ssh://) holds every setting.
      var sshConfig = SshConfig.tryParse(config.rawUrl, config.id);
      sshConfig ??= SshConfig(
        id: config.id,
        remarks: config.name,
        configType: _parseSshConfigType(config.transportString),
        sshHost: config.address,
        sshPort: config.port,
        sshUsername: config.uuid ?? '',
        sshPassword: config.password ?? '',
        sni: config.sni,
      );

      // Validate SSH credentials
      if (sshConfig.sshHost.isEmpty) {
        _status = VpnStatus.error;
        _errorMessage = 'SSH host is empty';
        notifyListeners();
        return false;
      }

      if (sshConfig.sshUsername.isEmpty) {
        _status = VpnStatus.error;
        _errorMessage = 'SSH username is empty';
        notifyListeners();
        return false;
      }

      if (kDebugMode) {
        debugPrint(
          '[VpnService] Connecting SSH: ${sshConfig.sshUsername}@${sshConfig.sshHost}:${sshConfig.sshPort}',
        );
      }

      // Step 1: Start SSH tunnel (creates local SOCKS proxy)
      final sshConnected = await sshService.connect(sshConfig);

      if (!sshConnected) {
        _status = VpnStatus.error;
        _errorMessage = sshService.errorMessage ?? 'SSH connection failed';
        _sshProxyPort = null;
        unawaited(
          ConnectionHealthService().recordFailure(config.id, _errorMessage!),
        );
        notifyListeners();
        return false;
      }

      _sshProxyPort = sshService.localPort;

      if (kDebugMode) {
        debugPrint(
          '[VpnService] SSH tunnel established on port $_sshProxyPort',
        );
        debugPrint('[VpnService] Starting V2Ray VPN with SOCKS proxy...');
      }

      // Step 2: Request VPN permission
      bool hasPermission = await flutterV2ray.requestPermission();
      if (!hasPermission) {
        await sshService.disconnect();
        _status = VpnStatus.error;
        _errorMessage = 'VPN permission denied';
        notifyListeners();
        return false;
      }

      // Step 3: Create V2Ray config that uses SSH SOCKS proxy as outbound
      final v2rayConfig = _buildSshV2RayConfig(sshConfig, _sshProxyPort!);

      // Step 5: Start V2Ray VPN mode with SSH as backend
      final blockedApps = await _resolveBlockedApps();
      await flutterV2ray.startV2Ray(
        remark: sshConfig.remarks.isNotEmpty ? sshConfig.remarks : 'SSH Server',
        config: v2rayConfig,
        blockedApps: blockedApps,
        // The app's own sockets (the SSH connection) are excluded from the
        // VPN by the engine, so no route exception is needed here.
        bypassSubnets: bypassSubnets,
        proxyOnly: false, // VPN Mode - routes ALL traffic
        notificationDisconnectButtonName: "Disconnect",
      );

      // Monitor SSH stats
      _monitorSshStats(sshService);
      _watchEngineStartup(config);

      if (kDebugMode) {
        debugPrint('[VpnService] SSH + VPN started successfully!');
      }

      return true;
    } catch (e) {
      // Never leave an orphaned SSH session behind a failed VPN start.
      _detachSshMonitor();
      if (_sshProxyPort != null || sshService.isConnected) {
        await sshService.disconnect();
      }
      _sshProxyPort = null;
      _status = VpnStatus.error;
      _errorMessage = 'SSH connection failed: $e';
      unawaited(
        ConnectionHealthService().recordFailure(config.id, _errorMessage!),
      );
      if (kDebugMode) {
        debugPrint('[VpnService] SSH error: $e');
      }
      notifyListeners();
      return false;
    }
  }

  Future<List<String>?> _resolveBlockedApps() async {
    try {
      final splitTunneling = SplitTunnelingService();
      await splitTunneling.initialize();
      final packages = splitTunneling.getBypassPackagesForV2Ray();
      return packages.isEmpty ? null : packages;
    } catch (error) {
      // App routing must not prevent a user-owned configuration from connecting.
      if (kDebugMode)
        debugPrint('[VpnService] Split tunneling unavailable: $error');
      return null;
    }
  }

  /// Engine config that hands all device traffic (TCP and UDP) to the
  /// local SSH gateway. The DNS servers given to Android are reached
  /// through the tunnel: the server's UDP gateway answers them, or the
  /// gateway asks them over TCP inside SSH.
  String _buildSshV2RayConfig(SshConfig sshConfig, int localPort) {
    final custom = InternetAddress.tryParse(sshConfig.dnsServer ?? '');
    final dnsServers = [
      if (custom != null) custom.address,
      '1.1.1.1',
      '8.8.8.8',
    ].toSet().toList();
    return jsonEncode({
      'log': {'loglevel': 'warning'},
      'dns': {'servers': dnsServers},
      'inbounds': [
        {
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'tag': 'socks-in',
        },
      ],
      'outbounds': [
        {
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': localPort},
            ],
          },
          'tag': 'proxy',
        },
        {'protocol': 'freedom', 'settings': {}, 'tag': 'direct'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'ip': [
              '127.0.0.0/8',
              '10.0.0.0/8',
              '172.16.0.0/12',
              '192.168.0.0/16',
            ],
            'outboundTag': 'direct',
          },
          {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'proxy'},
        ],
      },
    });
  }

  /// Parse SSH config type from transport string
  SshConfigType _parseSshConfigType(String transport) {
    switch (transport.toLowerCase()) {
      case 'ssh-ws':
      case 'websocket':
        return SshConfigType.websocket;
      case 'ssh-ssl':
      case 'ssh-tls':
      case 'ssl':
      case 'tls':
        return SshConfigType.ssl;
      case 'ssh-dns':
      case 'slowdns':
        return SshConfigType.slowDns;
      default:
        return SshConfigType.direct;
    }
  }

  /// Monitor SSH tunnel statistics. Only one listener is kept at a time.
  /// Speeds are derived from the byte totals, about once a second.
  void _monitorSshStats(SshTunnelService sshService) {
    _detachSshMonitor();
    var lastUp = 0;
    var lastDown = 0;
    DateTime? lastAt;
    void listener() {
      if (sshService.isConnected) {
        final stats = sshService.stats;
        final now = DateTime.now();
        var upSpeed = statsListenable.value.uploadSpeed;
        var downSpeed = statsListenable.value.downloadSpeed;
        final previous = lastAt;
        if (previous == null) {
          lastAt = now;
          lastUp = stats.uploadBytes;
          lastDown = stats.downloadBytes;
        } else {
          final elapsed = now.difference(previous).inMilliseconds;
          if (elapsed >= 900) {
            upSpeed =
                ((stats.uploadBytes - lastUp).clamp(0, 1 << 40) *
                        1000 ~/
                        elapsed)
                    .toInt();
            downSpeed =
                ((stats.downloadBytes - lastDown).clamp(0, 1 << 40) *
                        1000 ~/
                        elapsed)
                    .toInt();
            lastAt = now;
            lastUp = stats.uploadBytes;
            lastDown = stats.downloadBytes;
          }
        }
        statsListenable.value = VpnStats(
          uploadSpeed: upSpeed,
          downloadSpeed: downSpeed,
          totalUpload: stats.uploadBytes,
          totalDownload: stats.downloadBytes,
          duration: stats.duration,
        );
      } else if (sshService.status == SshStatus.error &&
          _status != VpnStatus.error) {
        _status = VpnStatus.error;
        _errorMessage = sshService.errorMessage;
        _resetTunnelCheck();
        notifyListeners();
      }
    }

    sshService.addListener(listener);
    _sshListener = listener;
  }

  void _detachSshMonitor() {
    final listener = _sshListener;
    if (listener != null) SshTunnelService().removeListener(listener);
    _sshListener = null;
  }

  /// Disconnect VPN (and SSH if active)
  Future<void> disconnect() async {
    if (kIsWeb || !_isInitialized) return;

    try {
      _resetTunnelCheck();
      _status = VpnStatus.disconnecting;
      _suppressDropRecordingUntil = DateTime.now().add(
        const Duration(seconds: 3),
      );
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[VpnService] Stopping VPN...');
      }

      // Stop V2Ray VPN
      await flutterV2ray.stopV2Ray();

      // Also stop SSH tunnel if it was active
      _detachSshMonitor();
      if (_sshProxyPort != null) {
        if (kDebugMode) {
          debugPrint('[VpnService] Stopping SSH tunnel...');
        }
        final sshService = SshTunnelService();
        await sshService.disconnect();
        _sshProxyPort = null;
      }

      _status = VpnStatus.disconnected;
      statsListenable.value = VpnStats();

      if (kDebugMode) {
        debugPrint('[VpnService] VPN stopped successfully');
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Disconnect failed: $e';
      _status = VpnStatus.disconnected;
      if (kDebugMode) {
        debugPrint('[VpnService] Disconnect error: $e');
      }
      notifyListeners();
    }
  }

  /// Toggle connection
  Future<void> toggle(VpnConfig config) async {
    if (isConnected || isConnecting) {
      await disconnect();
    } else {
      await connect(config);
    }
  }

  /// Measures a real request through a temporary engine for [config].
  ///
  /// Unlike a TCP ping this proves the profile can carry traffic. SSH profiles
  /// are not supported by the engine probe and return -1.
  Future<int> getServerDelay(VpnConfig config) async {
    if (kIsWeb || config.isSsh) return -1;
    if (!_isInitialized && !await initialize()) return -1;

    try {
      final (_, fullConfig) = _engineConfig(config);

      // Use flutter_v2ray's getServerDelay method
      final delay = await flutterV2ray.getServerDelay(config: fullConfig);

      if (kDebugMode) {
        debugPrint('[VpnService] Server delay for ${config.name}: ${delay}ms');
      }

      return delay;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VpnService] Error getting server delay: $e');
      }
      return -1;
    }
  }

  /// Get connected server delay
  Future<int> getConnectedServerDelay() async {
    if (kIsWeb || !_isInitialized || !isConnected) return -1;

    try {
      final delay = await flutterV2ray.getConnectedServerDelay();

      if (kDebugMode) {
        debugPrint('[VpnService] Connected server delay: ${delay}ms');
      }

      return delay;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VpnService] Error getting connected server delay: $e');
      }
      return -1;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    _detachSshMonitor();
    statsListenable.dispose();
    super.dispose();
  }
}
