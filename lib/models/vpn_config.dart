import 'package:hive/hive.dart';

part 'vpn_config.g.dart';

/// Supported VPN Protocol Types
enum VpnProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  ssh,
  unknown,
}

extension VpnProtocolExtension on VpnProtocol {
  String get displayName {
    switch (this) {
      case VpnProtocol.vless:
        return 'VLESS';
      case VpnProtocol.vmess:
        return 'VMess';
      case VpnProtocol.trojan:
        return 'Trojan';
      case VpnProtocol.shadowsocks:
        return 'Shadowsocks';
      case VpnProtocol.ssh:
        return 'SSH';
      case VpnProtocol.unknown:
        return 'Unknown';
    }
  }

  String get shortName {
    switch (this) {
      case VpnProtocol.vless:
        return 'VL';
      case VpnProtocol.vmess:
        return 'VM';
      case VpnProtocol.trojan:
        return 'TR';
      case VpnProtocol.shadowsocks:
        return 'SS';
      case VpnProtocol.ssh:
        return 'SSH';
      case VpnProtocol.unknown:
        return '??';
    }
  }
}

/// Network Transport Types
enum TransportType {
  tcp,
  ws,
  grpc,
  http,
  quic,
  kcp,
  unknown,
}

/// Security Types
enum SecurityType {
  none,
  tls,
  reality,
  auto,
}

/// VPN Configuration Model
@HiveType(typeId: 0)
class VpnConfig extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String rawUrl;

  @HiveField(3)
  String protocolString;

  @HiveField(4)
  String address;

  @HiveField(5)
  int port;

  @HiveField(6)
  String? uuid;

  @HiveField(7)
  String? password;

  @HiveField(8)
  String transportString;

  @HiveField(9)
  String securityString;

  @HiveField(10)
  String? sni;

  @HiveField(11)
  String? fingerprint;

  @HiveField(12)
  String? publicKey;

  @HiveField(13)
  String? shortId;

  @HiveField(14)
  String? path;

  @HiveField(15)
  String? host;

  @HiveField(16)
  String? encryption;

  @HiveField(17)
  String? flow;

  @HiveField(18)
  int? ping;

  @HiveField(19)
  DateTime createdAt;

  @HiveField(20)
  DateTime? lastTestedAt;

  @HiveField(21)
  bool isActive;

  @HiveField(22)
  String? country;

  @HiveField(23)
  String? countryCode;

  VpnConfig({
    required this.id,
    required this.name,
    required this.rawUrl,
    required this.protocolString,
    required this.address,
    required this.port,
    this.uuid,
    this.password,
    this.transportString = 'tcp',
    this.securityString = 'none',
    this.sni,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.path,
    this.host,
    this.encryption,
    this.flow,
    this.ping,
    DateTime? createdAt,
    this.lastTestedAt,
    this.isActive = false,
    this.country,
    this.countryCode,
  }) : createdAt = createdAt ?? DateTime.now();

  VpnProtocol get protocol {
    switch (protocolString.toLowerCase()) {
      case 'vless':
        return VpnProtocol.vless;
      case 'vmess':
        return VpnProtocol.vmess;
      case 'trojan':
        return VpnProtocol.trojan;
      case 'ss':
      case 'shadowsocks':
        return VpnProtocol.shadowsocks;
      case 'ssh':
      case 'ssh-direct':
      case 'ssh-ws':
      case 'ssh-ssl':
      case 'ssh-tls':
      case 'ssh-dns':
        return VpnProtocol.ssh;
      default:
        return VpnProtocol.unknown;
    }
  }

  /// Check if this is an SSH config
  bool get isSsh => protocol == VpnProtocol.ssh;

  /// Get SSH username (stored in uuid field for SSH configs)
  String? get sshUsername => isSsh ? uuid : null;

  /// Get SSH password (stored in password field)
  String? get sshPassword => isSsh ? password : null;

  TransportType get transport {
    switch (transportString.toLowerCase()) {
      case 'tcp':
        return TransportType.tcp;
      case 'ws':
      case 'websocket':
        return TransportType.ws;
      case 'grpc':
        return TransportType.grpc;
      case 'http':
      case 'h2':
        return TransportType.http;
      case 'quic':
        return TransportType.quic;
      case 'kcp':
        return TransportType.kcp;
      default:
        return TransportType.unknown;
    }
  }

  SecurityType get security {
    switch (securityString.toLowerCase()) {
      case 'tls':
        return SecurityType.tls;
      case 'reality':
        return SecurityType.reality;
      case 'none':
      case '':
        return SecurityType.none;
      default:
        return SecurityType.auto;
    }
  }

  /// Get ping status color indicator
  PingStatus get pingStatus {
    if (ping == null) return PingStatus.unknown;
    if (ping! < 100) return PingStatus.excellent;
    if (ping! < 200) return PingStatus.good;
    if (ping! < 500) return PingStatus.fair;
    return PingStatus.poor;
  }

  /// Check if this is a Reality protocol config
  bool get isReality => security == SecurityType.reality;

  /// Get display subtitle with protocol details
  String get subtitle {
    final parts = <String>[];
    parts.add(protocol.displayName);
    if (transport != TransportType.tcp) {
      parts.add(transportString.toUpperCase());
    }
    if (isReality) {
      parts.add('Reality');
    } else if (security == SecurityType.tls) {
      parts.add('TLS');
    }
    return parts.join(' + ');
  }

  /// Copy with new values
  VpnConfig copyWith({
    String? id,
    String? name,
    String? rawUrl,
    String? protocolString,
    String? address,
    int? port,
    String? uuid,
    String? password,
    String? transportString,
    String? securityString,
    String? sni,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? path,
    String? host,
    String? encryption,
    String? flow,
    int? ping,
    DateTime? createdAt,
    DateTime? lastTestedAt,
    bool? isActive,
    String? country,
    String? countryCode,
  }) {
    return VpnConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      rawUrl: rawUrl ?? this.rawUrl,
      protocolString: protocolString ?? this.protocolString,
      address: address ?? this.address,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      transportString: transportString ?? this.transportString,
      securityString: securityString ?? this.securityString,
      sni: sni ?? this.sni,
      fingerprint: fingerprint ?? this.fingerprint,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      path: path ?? this.path,
      host: host ?? this.host,
      encryption: encryption ?? this.encryption,
      flow: flow ?? this.flow,
      ping: ping ?? this.ping,
      createdAt: createdAt ?? this.createdAt,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      isActive: isActive ?? this.isActive,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
    );
  }
}

/// Ping status enumeration
enum PingStatus {
  excellent,
  good,
  fair,
  poor,
  unknown,
}

extension PingStatusExtension on PingStatus {
  String get label {
    switch (this) {
      case PingStatus.excellent:
        return 'Excellent';
      case PingStatus.good:
        return 'Good';
      case PingStatus.fair:
        return 'Fair';
      case PingStatus.poor:
        return 'Poor';
      case PingStatus.unknown:
        return 'Unknown';
    }
  }
}
