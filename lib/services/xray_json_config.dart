import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/vpn_config.dart';

/// Support for complete Xray JSON configurations ("custom" or "JSON" profiles
/// delivered by many subscription panels).
///
/// The bundled engine accepts a JSON config only when it has a SOCKS inbound
/// and when its first outbound is the server (with `vnext` or `servers`).
/// [prepareForEngine] normalizes configs that are valid Xray but arranged
/// differently, without changing where traffic is sent.
class XrayJsonConfig {
  const XrayJsonConfig._();

  static const _uuid = Uuid();
  static const int defaultSocksPort = 10808;
  static const String _proxyTag = 'proxy';

  /// Outbound protocols whose server can be read by the engine.
  static const Set<String> _serverProtocols = {
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'socks',
    'http',
  };

  /// Whether [json] is an Xray/V2Ray configuration (outbounds use `protocol`).
  static bool isXrayConfig(Object? json) {
    if (json is! Map) return false;
    final outbounds = json['outbounds'];
    return outbounds is List &&
        outbounds.any((o) => o is Map && o['protocol'] is String);
  }

  /// Whether [json] is a sing-box configuration (outbounds use `type`).
  static bool isSingBoxConfig(Object? json) {
    if (json is! Map) return false;
    final outbounds = json['outbounds'];
    return outbounds is List &&
        outbounds.isNotEmpty &&
        outbounds.every((o) => o is Map && o['protocol'] == null) &&
        outbounds.any((o) => o is Map && o['type'] is String);
  }

  /// Builds a stored route from an Xray JSON object, or null when the config
  /// has no server outbound the engine can use.
  static VpnConfig? toVpnConfig(
    Map<String, dynamic> json, {
    String? fallbackName,
    DateTime? createdAt,
  }) {
    final outbound = _serverOutbound(json);
    if (outbound == null) return null;
    final server = _serverOf(outbound);
    if (server == null) return null;

    final protocol = outbound['protocol'] as String;
    final stream = outbound['streamSettings'];
    final network = stream is Map ? stream['network']?.toString() : null;
    final security = stream is Map ? stream['security']?.toString() : null;
    String? sni;
    if (stream is Map) {
      final tls = stream['tlsSettings'] ?? stream['realitySettings'];
      if (tls is Map) sni = tls['serverName']?.toString();
    }

    final remarks = json['remarks']?.toString().trim();
    final name = (remarks != null && remarks.isNotEmpty)
        ? remarks
        : (fallbackName ?? '${protocol.toUpperCase()} ${server.$1}');

    return VpnConfig(
      id: _uuid.v4(),
      name: name,
      rawUrl: jsonEncode(json),
      protocolString: 'json',
      address: server.$1,
      port: server.$2,
      transportString: network ?? 'tcp',
      securityString: security ?? 'none',
      sni: sni,
      // Keeps the underlying protocol visible on cards (e.g. "VLESS").
      flow: protocol,
      createdAt: createdAt,
    );
  }

  /// Returns a copy of [raw] arranged the way the engine expects:
  /// a SOCKS inbound exists, the server outbound comes first, and that
  /// outbound is tagged `proxy` so traffic statistics work.
  static String prepareForEngine(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The JSON profile is not an object.');
    }
    final config = Map<String, dynamic>.from(decoded)..remove('remarks');

    // 1. Inbound for the VPN tunnel to hand traffic to.
    final inbounds = <dynamic>[
      ...(config['inbounds'] is List ? config['inbounds'] as List : const []),
    ];
    final hasSocks = inbounds.any(
      (i) => i is Map && i['protocol'] == 'socks' && i['port'] is int,
    );
    if (!hasSocks) {
      inbounds.insert(0, <String, dynamic>{
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': defaultSocksPort,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
        },
      });
    }
    config['inbounds'] = inbounds;

    // 2. The server outbound first. In Xray the first outbound is also the
    //    default route, which is what a VPN profile intends.
    final outbounds = <dynamic>[
      ...(config['outbounds'] is List ? config['outbounds'] as List : const []),
    ];
    final index = outbounds.indexWhere(
      (o) => o is Map && _serverOf(Map<String, dynamic>.from(o)) != null,
    );
    if (index == -1) {
      throw const FormatException('The JSON profile has no usable server.');
    }
    final server = Map<String, dynamic>.from(outbounds.removeAt(index) as Map);
    outbounds.insert(0, server);

    // 3. Tag it `proxy` unless that tag is taken or a balancer selects by
    //    prefix (renaming could then change which outbounds are selected).
    final oldTag = server['tag']?.toString();
    final routing = config['routing'];
    final hasBalancers =
        routing is Map &&
        routing['balancers'] is List &&
        (routing['balancers'] as List).isNotEmpty;
    final proxyTagTaken = outbounds
        .skip(1)
        .any((o) => o is Map && o['tag'] == _proxyTag);
    if (oldTag != _proxyTag && !proxyTagTaken && !hasBalancers) {
      server['tag'] = _proxyTag;
      if (oldTag != null && oldTag.isNotEmpty) {
        _renameReferences(config, oldTag, _proxyTag);
      }
    }
    config['outbounds'] = outbounds;
    return jsonEncode(config);
  }

  static Map<String, dynamic>? _serverOutbound(Map<String, dynamic> json) {
    final outbounds = json['outbounds'];
    if (outbounds is! List) return null;
    for (final outbound in outbounds) {
      if (outbound is Map) {
        final map = Map<String, dynamic>.from(outbound);
        if (_serverOf(map) != null) return map;
      }
    }
    return null;
  }

  /// Address and port of an outbound with `vnext` or `servers`.
  static (String, int)? _serverOf(Map<String, dynamic> outbound) {
    final protocol = outbound['protocol'];
    if (protocol is! String || !_serverProtocols.contains(protocol)) {
      return null;
    }
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final list = settings['vnext'] ?? settings['servers'];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    final entry = list.first as Map;
    final address = entry['address']?.toString();
    final port = int.tryParse(entry['port']?.toString() ?? '');
    if (address == null || address.isEmpty || port == null) return null;
    return (address, port);
  }

  static void _renameReferences(
    Map<String, dynamic> config,
    String from,
    String to,
  ) {
    final routing = config['routing'];
    if (routing is Map && routing['rules'] is List) {
      for (final rule in routing['rules'] as List) {
        if (rule is Map && rule['outboundTag'] == from) {
          rule['outboundTag'] = to;
        }
      }
    }
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      for (final outbound in outbounds) {
        if (outbound is! Map) continue;
        final stream = outbound['streamSettings'];
        final sockopt = stream is Map ? stream['sockopt'] : null;
        if (sockopt is Map && sockopt['dialerProxy'] == from) {
          sockopt['dialerProxy'] = to;
        }
        final mux = outbound['proxySettings'];
        if (mux is Map && mux['tag'] == from) mux['tag'] = to;
      }
    }
  }
}
