import 'dart:convert';

/// SSH Configuration Model for NPVT-SSH protocol
/// Supports SSH Direct, SSH over WebSocket, SSH over SSL
class SshConfig {
  final String id;
  final String remarks;
  final SshConfigType configType;
  final String sshHost;
  final int sshPort;
  final String sshUsername;
  final String sshPassword;
  final String? sni;
  final String tlsVersion;
  final String? httpProxy;
  final bool authenticateProxy;
  final String? proxyUsername;
  final String? proxyPassword;
  final String? payload;
  final DnsTTMode dnsTTMode;
  final String? dnsServer;
  final String? nameserver;
  final String? publicKey;
  final int udpgwPort;
  final bool udpgwTransparentDNS;
  final DateTime createdAt;
  final int? ping;
  final bool isActive;

  SshConfig({
    required this.id,
    required this.remarks,
    required this.configType,
    required this.sshHost,
    required this.sshPort,
    required this.sshUsername,
    required this.sshPassword,
    this.sni,
    this.tlsVersion = 'DEFAULT',
    this.httpProxy,
    this.authenticateProxy = false,
    this.proxyUsername,
    this.proxyPassword,
    this.payload,
    this.dnsTTMode = DnsTTMode.UDP,
    this.dnsServer,
    this.nameserver,
    this.publicKey,
    this.udpgwPort = 7300,
    this.udpgwTransparentDNS = true,
    DateTime? createdAt,
    this.ping,
    this.isActive = false,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Parse from npvt-ssh:// URL
  factory SshConfig.fromNpvtUrl(String url, String id) {
    if (!url.startsWith('npvt-ssh://')) {
      throw FormatException('Invalid NPVT-SSH URL: $url');
    }

    final base64Part = url.substring(11); // Remove 'npvt-ssh://'
    String normalized = base64Part.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }

    final jsonStr = utf8.decode(base64.decode(normalized));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    return SshConfig(
      id: id,
      remarks: json['remarks'] ?? 'SSH Server',
      configType: _parseConfigType(json['sshConfigType']),
      sshHost: json['sshHost'] ?? '',
      sshPort: json['sshPort'] ?? 22,
      sshUsername: json['sshUsername'] ?? '',
      sshPassword: json['sshPassword'] ?? '',
      sni: json['sni'],
      tlsVersion: json['tlsVersion'] ?? 'DEFAULT',
      httpProxy: json['httpProxy'],
      authenticateProxy: json['authenticateProxy'] ?? false,
      proxyUsername: json['proxyUsername'],
      proxyPassword: json['proxyPassword'],
      payload: json['payload'],
      dnsTTMode: _parseDnsTTMode(json['dnsTTMode']),
      dnsServer: json['dnsServer'],
      nameserver: json['nameserver'],
      publicKey: json['publicKey'],
      udpgwPort: json['udpgwPort'] ?? 7300,
      udpgwTransparentDNS: json['udpgwTransparentDNS'] ?? true,
    );
  }

  static SshConfigType _parseConfigType(String? type) {
    switch (type?.toUpperCase()) {
      case 'SSH':
      case 'DIRECT':
      case 'SSH-DIRECT':
        return SshConfigType.direct;
      case 'WEBSOCKET':
      case 'SSH-WS':
      case 'SSH-WEBSOCKET':
        return SshConfigType.websocket;
      case 'SSL':
      case 'TLS':
      case 'SSH-SSL':
      case 'SSH-TLS':
        return SshConfigType.ssl;
      case 'SLOWDNS':
      case 'SSH-SLOWDNS':
        return SshConfigType.slowDns;
      default:
        return SshConfigType.direct;
    }
  }

  static DnsTTMode _parseDnsTTMode(String? mode) {
    switch (mode?.toUpperCase()) {
      case 'UDP':
        return DnsTTMode.UDP;
      case 'TCP':
        return DnsTTMode.TCP;
      case 'DOH':
        return DnsTTMode.DOH;
      default:
        return DnsTTMode.UDP;
    }
  }

  static String _npvtConfigType(SshConfigType type) {
    switch (type) {
      case SshConfigType.direct:
        return 'SSH-DIRECT';
      case SshConfigType.websocket:
        return 'SSH-WS';
      case SshConfigType.ssl:
        return 'SSH-SSL';
      case SshConfigType.slowDns:
        return 'SSH-SLOWDNS';
    }
  }

  /// Export to npvt-ssh:// URL
  String toNpvtUrl() {
    final json = {
      'sshConfigType': _npvtConfigType(configType),
      'remarks': remarks,
      'sshHost': sshHost,
      'sshPort': sshPort,
      'sshUsername': sshUsername,
      'sshPassword': sshPassword,
      'sni': sni ?? '',
      'tlsVersion': tlsVersion,
      'httpProxy': httpProxy ?? '',
      'authenticateProxy': authenticateProxy,
      'proxyUsername': proxyUsername ?? '',
      'proxyPassword': proxyPassword ?? '',
      'payload': payload ?? '',
      'dnsTTMode': dnsTTMode.name,
      'dnsServer': dnsServer ?? '',
      'nameserver': nameserver ?? '',
      'publicKey': publicKey ?? '',
      'udpgwPort': udpgwPort,
      'udpgwTransparentDNS': udpgwTransparentDNS,
    };

    final jsonStr = jsonEncode(json);
    final base64Str = base64.encode(utf8.encode(jsonStr));
    return 'npvt-ssh://$base64Str';
  }

  /// Get display subtitle
  String get subtitle {
    final parts = <String>[];
    parts.add(configType.displayName);
    if (sni != null && sni!.isNotEmpty) {
      parts.add('SNI');
    }
    if (configType == SshConfigType.websocket) {
      parts.add('WS');
    }
    return parts.join(' + ');
  }

  /// Get server display string
  String get serverDisplay => '$sshHost:$sshPort';

  SshConfig copyWith({
    String? id,
    String? remarks,
    SshConfigType? configType,
    String? sshHost,
    int? sshPort,
    String? sshUsername,
    String? sshPassword,
    String? sni,
    String? tlsVersion,
    String? httpProxy,
    bool? authenticateProxy,
    String? proxyUsername,
    String? proxyPassword,
    String? payload,
    DnsTTMode? dnsTTMode,
    String? dnsServer,
    String? nameserver,
    String? publicKey,
    int? udpgwPort,
    bool? udpgwTransparentDNS,
    DateTime? createdAt,
    int? ping,
    bool? isActive,
  }) {
    return SshConfig(
      id: id ?? this.id,
      remarks: remarks ?? this.remarks,
      configType: configType ?? this.configType,
      sshHost: sshHost ?? this.sshHost,
      sshPort: sshPort ?? this.sshPort,
      sshUsername: sshUsername ?? this.sshUsername,
      sshPassword: sshPassword ?? this.sshPassword,
      sni: sni ?? this.sni,
      tlsVersion: tlsVersion ?? this.tlsVersion,
      httpProxy: httpProxy ?? this.httpProxy,
      authenticateProxy: authenticateProxy ?? this.authenticateProxy,
      proxyUsername: proxyUsername ?? this.proxyUsername,
      proxyPassword: proxyPassword ?? this.proxyPassword,
      payload: payload ?? this.payload,
      dnsTTMode: dnsTTMode ?? this.dnsTTMode,
      dnsServer: dnsServer ?? this.dnsServer,
      nameserver: nameserver ?? this.nameserver,
      publicKey: publicKey ?? this.publicKey,
      udpgwPort: udpgwPort ?? this.udpgwPort,
      udpgwTransparentDNS: udpgwTransparentDNS ?? this.udpgwTransparentDNS,
      createdAt: createdAt ?? this.createdAt,
      ping: ping ?? this.ping,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// SSH Configuration Types
enum SshConfigType { direct, websocket, ssl, slowDns }

extension SshConfigTypeExtension on SshConfigType {
  String get displayName {
    switch (this) {
      case SshConfigType.direct:
        return 'SSH Direct';
      case SshConfigType.websocket:
        return 'SSH + WebSocket';
      case SshConfigType.ssl:
        return 'SSH + SSL/TLS';
      case SshConfigType.slowDns:
        return 'SSH + SlowDNS';
    }
  }

  String get shortName {
    switch (this) {
      case SshConfigType.direct:
        return 'SSH';
      case SshConfigType.websocket:
        return 'SSH-WS';
      case SshConfigType.ssl:
        return 'SSH-TLS';
      case SshConfigType.slowDns:
        return 'SSH-DNS';
    }
  }
}

/// DNS Tunnel Mode
enum DnsTTMode { UDP, TCP, DOH }
