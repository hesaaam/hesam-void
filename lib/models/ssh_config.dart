import 'dart:convert';

/// One SSH server profile.
///
/// The app's own share format is an `ssh://` link (see [toSshUrl]); NPV
/// Tunnel `npvt-ssh://` links are still read so existing profiles keep
/// working, and are converted to `ssh://` on import.
class SshConfig {
  final String id;
  final String remarks;
  final SshConfigType configType;
  final String sshHost;
  final int sshPort;
  final String sshUsername;
  final String sshPassword;

  /// Private key in OpenSSH/PEM text. When set it is used instead of
  /// [sshPassword].
  final String? privateKey;
  final String? keyPassphrase;

  /// TLS server name (SNI) for SSL/TLS and secure WebSocket connections.
  final String? sni;
  final String tlsVersion;

  /// WebSocket request path and Host header.
  final String? wsPath;
  final String? wsHost;

  /// Whether the WebSocket connection itself uses TLS.
  final bool wsTls;

  /// Whether SSH data is wrapped in WebSocket frames after the upgrade.
  /// Most SSH WebSocket servers relay raw bytes after `101`; websockify
  /// style servers need frames.
  final bool wsFraming;

  /// Optional HTTP proxy, `host:port`, the connection goes through.
  final String? httpProxy;
  final bool authenticateProxy;
  final String? proxyUsername;
  final String? proxyPassword;

  /// Custom HTTP request sent before SSH starts, with placeholders such as
  /// `[host]`, `[port]` and `[crlf]`.
  final String? payload;

  final DnsTTMode dnsTTMode;

  /// DNS server used for the tunnel; null uses the defaults.
  final String? dnsServer;
  final String? nameserver;
  final String? publicKey;

  /// Port of the server's UDP gateway (badvpn-udpgw); 0 turns UDP off.
  final int udpgwPort;

  /// Let the server resolve DNS through the UDP gateway.
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
    this.privateKey,
    this.keyPassphrase,
    this.sni,
    this.tlsVersion = 'DEFAULT',
    this.wsPath,
    this.wsHost,
    this.wsTls = false,
    this.wsFraming = false,
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

  bool get usesPrivateKey => (privateKey ?? '').trim().isNotEmpty;
  bool get udpEnabled => udpgwPort > 0 && udpgwPort <= 65535;

  /// Whether the first hop is wrapped in TLS.
  bool get usesTls =>
      configType == SshConfigType.ssl ||
      (configType == SshConfigType.websocket && wsTls);

  /// The name sent in TLS; falls back to the server address.
  String get tlsServerName {
    final value = sni?.trim();
    return (value == null || value.isEmpty) ? sshHost : value;
  }

  // ---------------------------------------------------------------------
  // Links
  // ---------------------------------------------------------------------

  static bool isSshLink(String link) {
    final lower = link.trim().toLowerCase();
    return lower.startsWith('ssh://') || lower.startsWith('npvt-ssh://');
  }

  /// Reads an `ssh://` or `npvt-ssh://` link; null when it cannot be read.
  static SshConfig? tryParse(String link, String id) {
    final text = link.trim();
    try {
      final lower = text.toLowerCase();
      if (lower.startsWith('ssh://')) return SshConfig.fromSshUrl(text, id);
      if (lower.startsWith('npvt-ssh://')) {
        return SshConfig.fromNpvtUrl(text, id);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static String? _b64(String? value) {
    if (value == null || value.isEmpty) return null;
    var text = value.replaceAll('-', '+').replaceAll('_', '/');
    while (text.length % 4 != 0) {
      text += '=';
    }
    try {
      return utf8.decode(base64.decode(text));
    } catch (_) {
      return value;
    }
  }

  static String _encodeB64(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static Map<String, String> _query(String query) {
    final values = <String, String>{};
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final key = _decode(eq == -1 ? part : part.substring(0, eq));
      final value = eq == -1 ? '' : part.substring(eq + 1);
      values[key] = _decode(value.replaceAll('+', ' '));
    }
    return values;
  }

  /// `ssh://USER:PASS@HOST:PORT?type=tls&sni=…&udpgw=7300#Name`.
  factory SshConfig.fromSshUrl(String url, String id) {
    var rest = url.trim().substring('ssh://'.length);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash != -1) {
      name = _decode(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    var query = '';
    final question = rest.indexOf('?');
    if (question != -1) {
      query = rest.substring(question + 1);
      rest = rest.substring(0, question);
    }
    if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);

    final at = rest.lastIndexOf('@');
    if (at == -1) throw const FormatException('Missing user name.');
    final userInfo = rest.substring(0, at);
    final server = rest.substring(at + 1);
    final colon = userInfo.indexOf(':');
    final username = _decode(
      colon == -1 ? userInfo : userInfo.substring(0, colon),
    );
    final password = colon == -1 ? '' : _decode(userInfo.substring(colon + 1));

    String host;
    var port = 22;
    if (server.startsWith('[')) {
      final end = server.indexOf(']');
      if (end == -1) throw const FormatException('Bad IPv6 address.');
      host = server.substring(1, end);
      final tail = server.substring(end + 1);
      if (tail.startsWith(':')) port = int.parse(tail.substring(1));
    } else {
      final portColon = server.lastIndexOf(':');
      if (portColon == -1) {
        host = server;
      } else {
        host = server.substring(0, portColon);
        port = int.parse(server.substring(portColon + 1));
      }
    }
    if (host.isEmpty) throw const FormatException('Missing host.');
    if (port < 1 || port > 65535) throw const FormatException('Bad port.');

    final q = _query(query);
    bool flag(String key, bool fallback) {
      final value = q[key]?.toLowerCase();
      if (value == null || value.isEmpty) return fallback;
      return value == '1' || value == 'true' || value == 'yes' || value == 'on';
    }

    final type = switch ((q['type'] ?? 'direct').toLowerCase()) {
      'tls' || 'ssl' => SshConfigType.ssl,
      'ws' || 'websocket' => SshConfigType.websocket,
      'slowdns' || 'dns' => SshConfigType.slowDns,
      _ => SshConfigType.direct,
    };
    final udpgw = q.containsKey('udpgw')
        ? (int.tryParse(q['udpgw']!) ?? 0)
        : 7300;

    return SshConfig(
      id: id,
      remarks: name.isNotEmpty ? name : '$username@$host',
      configType: type,
      sshHost: host,
      sshPort: port,
      sshUsername: username,
      sshPassword: password,
      privateKey: _b64(q['key']),
      keyPassphrase: q['keypass'],
      sni: _nonEmpty(q['sni']),
      wsPath: _nonEmpty(q['path']),
      wsHost: _nonEmpty(q['host']),
      wsTls: flag('tls', false),
      wsFraming: flag('framing', false),
      httpProxy: _nonEmpty(q['proxy']),
      payload: _b64(q['payload']),
      dnsServer: _nonEmpty(q['dns']),
      udpgwPort: udpgw,
      udpgwTransparentDNS: flag('udpgw-dns', true),
    );
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// The app's share link for this profile.
  String toSshUrl() {
    final params = <String, String>{
      'type': switch (configType) {
        SshConfigType.ssl => 'tls',
        SshConfigType.websocket => 'ws',
        SshConfigType.slowDns => 'slowdns',
        SshConfigType.direct => 'direct',
      },
      if (_nonEmpty(sni) != null) 'sni': sni!.trim(),
      if (configType == SshConfigType.websocket) ...{
        if (_nonEmpty(wsPath) != null) 'path': wsPath!.trim(),
        if (_nonEmpty(wsHost) != null) 'host': wsHost!.trim(),
        if (wsTls) 'tls': '1',
        if (wsFraming) 'framing': '1',
      },
      if (_nonEmpty(httpProxy) != null) 'proxy': httpProxy!.trim(),
      if ((payload ?? '').isNotEmpty) 'payload': _encodeB64(payload!),
      'udpgw': '${udpEnabled ? udpgwPort : 0}',
      if (udpEnabled) 'udpgw-dns': udpgwTransparentDNS ? '1' : '0',
      if (_nonEmpty(dnsServer) != null) 'dns': dnsServer!.trim(),
      if (usesPrivateKey) 'key': _encodeB64(privateKey!.trim()),
      if (usesPrivateKey && (keyPassphrase ?? '').isNotEmpty)
        'keypass': keyPassphrase!,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    final host = sshHost.contains(':') && !sshHost.startsWith('[')
        ? '[$sshHost]'
        : sshHost;
    final auth = usesPrivateKey
        ? Uri.encodeComponent(sshUsername)
        : '${Uri.encodeComponent(sshUsername)}:${Uri.encodeComponent(sshPassword)}';
    final name = remarks.trim();
    return 'ssh://$auth@$host:$sshPort?$query'
        '${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';
  }

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

    String? text(String key) => _nonEmpty(json[key]?.toString());
    int number(String key, int fallback) =>
        int.tryParse(json[key]?.toString() ?? '') ?? fallback;

    final type = _parseConfigType(json['sshConfigType']?.toString());
    final rawPayload = json['payload']?.toString();
    String? wsPath;
    String? payload = _nonEmpty(rawPayload);
    // NPV keeps a bare WebSocket path in the payload field.
    if (type == SshConfigType.websocket &&
        payload != null &&
        payload.startsWith('/') &&
        !payload.contains(RegExp(r'\s'))) {
      wsPath = payload;
    }
    final port = number('sshPort', 22);

    return SshConfig(
      id: id,
      remarks: text('remarks') ?? 'SSH Server',
      configType: type,
      sshHost: json['sshHost']?.toString() ?? '',
      sshPort: port,
      sshUsername: json['sshUsername']?.toString() ?? '',
      sshPassword: json['sshPassword']?.toString() ?? '',
      privateKey: text('sshPrivateKey') ?? text('privateKey'),
      keyPassphrase: text('sshPrivateKeyPassphrase'),
      sni: text('sni'),
      tlsVersion: text('tlsVersion') ?? 'DEFAULT',
      wsPath: wsPath,
      wsTls:
          type == SshConfigType.websocket &&
          (text('sni') != null || port == 443),
      httpProxy: text('httpProxy'),
      authenticateProxy: json['authenticateProxy'] == true,
      proxyUsername: text('proxyUsername'),
      proxyPassword: text('proxyPassword'),
      payload: payload,
      dnsTTMode: _parseDnsTTMode(json['dnsTTMode']?.toString()),
      dnsServer: text('dnsServer'),
      nameserver: text('nameserver'),
      publicKey: text('publicKey'),
      udpgwPort: number('udpgwPort', 7300),
      udpgwTransparentDNS: json['udpgwTransparentDNS'] != false,
    );
  }

  static SshConfigType _parseConfigType(String? type) {
    switch (type?.toUpperCase()) {
      case 'SSH':
      case 'DIRECT':
      case 'SSH-DIRECT':
        return SshConfigType.direct;
      case 'WEBSOCKET':
      case 'WS':
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
      'payload': payload ?? wsPath ?? '',
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
    final parts = <String>[configType.displayName];
    if (sni != null && sni!.isNotEmpty) parts.add('SNI');
    if (udpEnabled) parts.add('UDP');
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
    String? payload,
    String? httpProxy,
    String? dnsServer,
    int? udpgwPort,
    bool? udpgwTransparentDNS,
  }) {
    return SshConfig(
      id: id ?? this.id,
      remarks: remarks ?? this.remarks,
      configType: configType ?? this.configType,
      sshHost: sshHost ?? this.sshHost,
      sshPort: sshPort ?? this.sshPort,
      sshUsername: sshUsername ?? this.sshUsername,
      sshPassword: sshPassword ?? this.sshPassword,
      privateKey: privateKey,
      keyPassphrase: keyPassphrase,
      sni: sni ?? this.sni,
      tlsVersion: tlsVersion,
      wsPath: wsPath,
      wsHost: wsHost,
      wsTls: wsTls,
      wsFraming: wsFraming,
      httpProxy: httpProxy ?? this.httpProxy,
      authenticateProxy: authenticateProxy,
      proxyUsername: proxyUsername,
      proxyPassword: proxyPassword,
      payload: payload ?? this.payload,
      dnsTTMode: dnsTTMode,
      dnsServer: dnsServer ?? this.dnsServer,
      nameserver: nameserver,
      publicKey: publicKey,
      udpgwPort: udpgwPort ?? this.udpgwPort,
      udpgwTransparentDNS: udpgwTransparentDNS ?? this.udpgwTransparentDNS,
      createdAt: createdAt,
      ping: ping,
      isActive: isActive,
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
        return 'WS';
      case SshConfigType.ssl:
        return 'SSL';
      case SshConfigType.slowDns:
        return 'DNS';
    }
  }
}

/// DNS Tunnel Mode
// ignore: constant_identifier_names
enum DnsTTMode { UDP, TCP, DOH }
