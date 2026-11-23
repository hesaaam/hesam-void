import 'dart:convert';

import '../models/vpn_config.dart';
import 'config_parser_service.dart';
import 'xray_json_config.dart';

/// Group a field is shown in on the edit screen.
enum EditSection { server, identity, transport, security, advanced }

/// How a field is edited.
enum EditKind { text, number, choice, toggle, multiline }

/// Thrown when an edited profile cannot be saved; [message] is shown as is.
class ConfigEditException implements Exception {
  final String message;
  const ConfigEditException(this.message);

  @override
  String toString() => message;
}

/// One editable part of a profile.
class EditField {
  final String key;
  final String label;
  final EditSection section;
  final EditKind kind;
  final List<String> options;
  final bool secret;
  final String? hint;

  /// A parameter this app has no label for; it can be removed.
  final bool custom;

  /// Whether the key existed in the original profile.
  final bool wasPresent;

  final String initial;
  String value;

  EditField({
    required this.key,
    required this.label,
    required this.section,
    this.kind = EditKind.text,
    this.options = const [],
    this.secret = false,
    this.hint,
    this.custom = false,
    this.wasPresent = false,
    String initial = '',
  }) : initial = initial,
       value = initial;

  bool get changed => value != initial;

  /// The value as it should be written back.
  String get cleaned =>
      kind == EditKind.multiline || secret ? value : value.trim();
}

/// Where a profile stores its settings.
enum DraftFormat { uri, vmess, ssh, shadowsocks, xrayJson }

class _Spec {
  final String key;
  final String label;
  final EditSection section;
  final EditKind kind;
  final List<String> options;
  final bool always;
  final bool secret;
  final String? hint;

  const _Spec(
    this.key,
    this.label,
    this.section, {
    this.kind = EditKind.text,
    this.options = const [],
    this.always = false,
    this.secret = false,
    this.hint,
  });
}

/// Editable copy of a saved profile.
///
/// Every part of the original link is kept: settings this app knows get a
/// labelled field, anything else is listed under Advanced with its raw key,
/// so saving never drops a parameter the user did not touch.
class ConfigDraft {
  static const nameKey = '@name';
  static const addressKey = '@address';
  static const portKey = '@port';
  static const secretKey = '@secret';
  static const methodKey = '@method';

  final VpnConfig original;
  final DraftFormat format;
  final String _scheme;
  final List<EditField> fields;

  /// For VMess and SSH links: the decoded JSON object, in original order.
  final Map<String, dynamic> _object;

  /// Keys of [_object] that hold the name, address and port.
  final Map<String, String> _roles;

  /// Full configuration text of an Xray JSON profile.
  String jsonText;
  final String _initialJson;

  /// The link this draft was read from.
  final String source;

  ConfigDraft._({
    required this.original,
    required this.format,
    required this.fields,
    required this.source,
    String scheme = '',
    Map<String, dynamic>? object,
    Map<String, String> roles = const {},
    this.jsonText = '',
  }) : _scheme = scheme,
       _object = object ?? <String, dynamic>{},
       _roles = roles,
       _initialJson = jsonText;

  /// Reads [config] into a draft, or null when its format cannot be edited
  /// field by field.
  static ConfigDraft? fromConfig(VpnConfig config) =>
      parse(config.rawUrl, config);

  /// Reads [link] (for example text edited in link mode) into a draft that
  /// will replace [original].
  static ConfigDraft? parse(String link, VpnConfig original) {
    final raw = link.trim();
    try {
      if (original.isJson || raw.startsWith('{')) {
        return _fromJson(raw, original);
      }
      final lower = raw.toLowerCase();
      if (lower.startsWith('vless://')) return _fromUri(raw, original, 'vless');
      if (lower.startsWith('trojan://')) {
        return _fromUri(raw, original, 'trojan');
      }
      if (lower.startsWith('vmess://')) {
        return _fromObjectLink(raw, original, DraftFormat.vmess);
      }
      if (lower.startsWith('npvt-ssh://')) {
        return _fromObjectLink(raw, original, DraftFormat.ssh);
      }
      if (lower.startsWith('ss://')) return _fromShadowsocks(raw, original);
    } catch (_) {
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Field specifications
  // ---------------------------------------------------------------------

  static const _transports = [
    'tcp',
    'raw',
    'ws',
    'grpc',
    'httpupgrade',
    'xhttp',
    'splithttp',
    'h2',
    'http',
    'kcp',
    'quic',
  ];
  static const _fingerprints = [
    'chrome',
    'firefox',
    'safari',
    'ios',
    'android',
    'edge',
    '360',
    'qq',
    'random',
    'randomized',
  ];

  static const _uriTransport = [
    _Spec(
      'type',
      'Transport',
      EditSection.transport,
      kind: EditKind.choice,
      options: _transports,
      always: true,
    ),
    _Spec('host', 'Host header', EditSection.transport, always: true),
    _Spec('path', 'Path', EditSection.transport, always: true),
    _Spec('serviceName', 'gRPC service name', EditSection.transport),
    _Spec('mode', 'Mode', EditSection.transport),
    _Spec('headerType', 'Header type', EditSection.transport),
    _Spec('authority', 'Authority', EditSection.transport),
    _Spec('seed', 'Seed', EditSection.transport),
    _Spec('extra', 'Extra (XHTTP)', EditSection.transport),
  ];
  static const _uriSecurity = [
    _Spec(
      'security',
      'Security',
      EditSection.security,
      kind: EditKind.choice,
      options: ['none', 'tls', 'reality'],
      always: true,
    ),
    _Spec('sni', 'SNI (server name)', EditSection.security, always: true),
    _Spec(
      'fp',
      'Fingerprint',
      EditSection.security,
      kind: EditKind.choice,
      options: _fingerprints,
      always: true,
    ),
    _Spec('alpn', 'ALPN', EditSection.security, hint: 'h2,http/1.1'),
    _Spec('pbk', 'Reality public key', EditSection.security),
    _Spec('sid', 'Reality short ID', EditSection.security),
    _Spec('spx', 'Reality spider path', EditSection.security),
    _Spec('pqv', 'Post-quantum verify key', EditSection.security),
  ];
  static const _vlessIdentity = [
    _Spec(
      'encryption',
      'Encryption',
      EditSection.identity,
      always: true,
      hint: 'none',
    ),
    _Spec(
      'flow',
      'Flow',
      EditSection.identity,
      kind: EditKind.choice,
      options: ['xtls-rprx-vision', 'xtls-rprx-vision-udp443'],
      always: true,
    ),
  ];

  static const _vmessSpecs = [
    _Spec('id', 'UUID', EditSection.identity, always: true),
    _Spec('aid', 'Alter ID', EditSection.identity, kind: EditKind.number),
    _Spec(
      'scy',
      'Encryption',
      EditSection.identity,
      kind: EditKind.choice,
      options: ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none', 'zero'],
      always: true,
    ),
    _Spec(
      'net',
      'Transport',
      EditSection.transport,
      kind: EditKind.choice,
      options: _transports,
      always: true,
    ),
    _Spec('type', 'Header type', EditSection.transport),
    _Spec('host', 'Host header', EditSection.transport, always: true),
    _Spec('path', 'Path', EditSection.transport, always: true),
    _Spec(
      'tls',
      'Security',
      EditSection.security,
      kind: EditKind.choice,
      options: ['tls', 'reality'],
      always: true,
    ),
    _Spec('sni', 'SNI (server name)', EditSection.security, always: true),
    _Spec(
      'fp',
      'Fingerprint',
      EditSection.security,
      kind: EditKind.choice,
      options: _fingerprints,
    ),
    _Spec('alpn', 'ALPN', EditSection.security),
    _Spec('v', 'Link version', EditSection.advanced),
  ];

  static const _sshSpecs = [
    _Spec('sshUsername', 'Username', EditSection.identity, always: true),
    _Spec(
      'sshPassword',
      'Password',
      EditSection.identity,
      always: true,
      secret: true,
    ),
    _Spec(
      'sshConfigType',
      'Connection type',
      EditSection.transport,
      kind: EditKind.choice,
      options: ['SSH-DIRECT', 'SSH-WS', 'SSH-SSL', 'SSH-SLOWDNS'],
      always: true,
    ),
    _Spec('httpProxy', 'HTTP proxy', EditSection.transport),
    _Spec(
      'payload',
      'Payload',
      EditSection.transport,
      kind: EditKind.multiline,
    ),
    _Spec('sni', 'SNI (server name)', EditSection.security, always: true),
    _Spec(
      'tlsVersion',
      'TLS version',
      EditSection.security,
      kind: EditKind.choice,
      options: ['DEFAULT', 'TLSv1.2', 'TLSv1.3'],
    ),
    _Spec(
      'authenticateProxy',
      'Proxy needs sign-in',
      EditSection.advanced,
      kind: EditKind.toggle,
    ),
    _Spec('proxyUsername', 'Proxy username', EditSection.advanced),
    _Spec(
      'proxyPassword',
      'Proxy password',
      EditSection.advanced,
      secret: true,
    ),
    _Spec(
      'dnsTTMode',
      'DNS mode',
      EditSection.advanced,
      kind: EditKind.choice,
      options: ['UDP', 'TCP', 'DOH'],
    ),
    _Spec('dnsServer', 'DNS server', EditSection.advanced),
    _Spec('nameserver', 'Nameserver', EditSection.advanced),
    _Spec('publicKey', 'Public key', EditSection.advanced),
    _Spec(
      'udpgwPort',
      'UDPGW port',
      EditSection.advanced,
      kind: EditKind.number,
    ),
    _Spec(
      'udpgwTransparentDNS',
      'UDPGW transparent DNS',
      EditSection.advanced,
      kind: EditKind.toggle,
    ),
  ];

  static const _ssMethods = [
    'aes-128-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
    'none',
  ];

  static List<EditField> _serverFields(
    String name,
    String address,
    String port,
  ) {
    return [
      EditField(
        key: nameKey,
        label: 'Name',
        section: EditSection.server,
        initial: name,
        wasPresent: true,
      ),
      EditField(
        key: addressKey,
        label: 'Server address',
        section: EditSection.server,
        hint: 'example.com or 1.2.3.4',
        initial: address,
        wasPresent: true,
      ),
      EditField(
        key: portKey,
        label: 'Port',
        section: EditSection.server,
        kind: EditKind.number,
        initial: port,
        wasPresent: true,
      ),
    ];
  }

  /// Fields for [values] (in their original order): known keys first, in
  /// spec order, then everything else as custom parameters.
  static List<EditField> _paramFields(
    List<_Spec> specs,
    Map<String, String> values, {
    Set<String> skip = const {},
  }) {
    final result = <EditField>[];
    final known = <String>{};
    for (final spec in specs) {
      known.add(spec.key);
      final present = values.containsKey(spec.key);
      if (!present && !spec.always) continue;
      result.add(
        EditField(
          key: spec.key,
          label: spec.label,
          section: spec.section,
          kind: spec.kind,
          options: spec.options,
          secret: spec.secret,
          hint: spec.hint,
          wasPresent: present,
          initial: values[spec.key] ?? '',
        ),
      );
    }
    for (final entry in values.entries) {
      if (known.contains(entry.key) || skip.contains(entry.key)) continue;
      result.add(customField(entry.key, entry.value, wasPresent: true));
    }
    return result;
  }

  /// A parameter without a dedicated label.
  static EditField customField(
    String key,
    String value, {
    bool wasPresent = false,
  }) {
    return EditField(
      key: key,
      label: key,
      section: EditSection.advanced,
      custom: true,
      wasPresent: wasPresent,
      initial: value,
    );
  }

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static Map<String, String> _queryOf(String query) {
    final values = <String, String>{};
    if (query.isEmpty) return values;
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final key = _decode(eq == -1 ? part : part.substring(0, eq));
      final value = eq == -1 ? '' : part.substring(eq + 1);
      if (key.isEmpty) continue;
      values[key] = _decode(value.replaceAll('+', ' '));
    }
    return values;
  }

  static ConfigDraft _fromUri(String raw, VpnConfig original, String scheme) {
    final uri = Uri.parse(raw);
    final params = _queryOf(uri.query);
    final identity = <EditField>[
      EditField(
        key: secretKey,
        label: scheme == 'vless' ? 'UUID' : 'Password',
        section: EditSection.identity,
        secret: scheme != 'vless',
        wasPresent: true,
        initial: _decode(uri.userInfo),
      ),
    ];
    final specs = [
      if (scheme == 'vless') ..._vlessIdentity,
      ..._uriTransport,
      ..._uriSecurity,
      if (scheme == 'trojan')
        const _Spec(
          'flow',
          'Flow',
          EditSection.identity,
          kind: EditKind.choice,
          options: ['xtls-rprx-vision'],
        ),
    ];
    return ConfigDraft._(
      original: original,
      format: DraftFormat.uri,
      scheme: scheme,
      source: raw,
      fields: [
        ..._serverFields(
          _decode(uri.fragment),
          uri.host,
          uri.hasPort ? '${uri.port}' : '',
        ),
        ...identity,
        ..._paramFields(specs, params),
      ],
    );
  }

  static Map<String, dynamic> _decodeObjectLink(String raw, String prefix) {
    var body = raw.substring(prefix.length).trim();
    body = body.replaceAll('-', '+').replaceAll('_', '/');
    while (body.length % 4 != 0) {
      body += '=';
    }
    final decoded = jsonDecode(utf8.decode(base64.decode(body)));
    if (decoded is! Map) throw const FormatException('Not an object');
    return Map<String, dynamic>.from(decoded);
  }

  static String _asText(Object? value) => value == null ? '' : '$value';

  static ConfigDraft _fromObjectLink(
    String raw,
    VpnConfig original,
    DraftFormat format,
  ) {
    final ssh = format == DraftFormat.ssh;
    final object = _decodeObjectLink(raw, ssh ? 'npvt-ssh://' : 'vmess://');
    final roles = ssh
        ? const {nameKey: 'remarks', addressKey: 'sshHost', portKey: 'sshPort'}
        : const {nameKey: 'ps', addressKey: 'add', portKey: 'port'};
    final values = {
      for (final entry in object.entries) entry.key: _asText(entry.value),
    };
    return ConfigDraft._(
      original: original,
      format: format,
      source: raw,
      object: object,
      roles: roles,
      fields: [
        ..._serverFields(
          values[roles[nameKey]] ?? '',
          values[roles[addressKey]] ?? '',
          values[roles[portKey]] ?? '',
        ),
        ..._paramFields(
          ssh ? _sshSpecs : _vmessSpecs,
          values,
          skip: roles.values.toSet(),
        ),
      ],
    );
  }

  /// `ss://` in SIP002 (`base64(method:password)@host:port?plugin=…`) or the
  /// legacy form (`base64(method:password@host:port)`).
  static ConfigDraft? _fromShadowsocks(String raw, VpnConfig original) {
    var body = raw.substring(5);
    var name = '';
    final hash = body.indexOf('#');
    if (hash != -1) {
      name = _decode(body.substring(hash + 1));
      body = body.substring(0, hash);
    }
    var query = '';
    final question = body.indexOf('?');
    if (question != -1) {
      query = body.substring(question + 1);
      body = body.substring(0, question);
    }
    if (body.endsWith('/')) body = body.substring(0, body.length - 1);

    String userInfo;
    String server;
    if (body.contains('@')) {
      final at = body.lastIndexOf('@');
      userInfo = _base64OrPlain(body.substring(0, at));
      server = body.substring(at + 1);
    } else {
      final decoded = _base64OrPlain(body);
      final at = decoded.lastIndexOf('@');
      if (at == -1) return null;
      userInfo = decoded.substring(0, at);
      server = decoded.substring(at + 1);
    }
    final colon = userInfo.indexOf(':');
    if (colon == -1) return null;
    final endpoint = splitHostPort(server);
    if (endpoint == null) return null;

    return ConfigDraft._(
      original: original,
      format: DraftFormat.shadowsocks,
      source: raw,
      fields: [
        ..._serverFields(name, endpoint.$1, endpoint.$2),
        EditField(
          key: methodKey,
          label: 'Encryption method',
          section: EditSection.identity,
          kind: EditKind.choice,
          options: _ssMethods,
          wasPresent: true,
          initial: userInfo.substring(0, colon),
        ),
        EditField(
          key: secretKey,
          label: 'Password',
          section: EditSection.identity,
          secret: true,
          wasPresent: true,
          initial: userInfo.substring(colon + 1),
        ),
        for (final entry in _queryOf(query).entries)
          customField(entry.key, entry.value, wasPresent: true),
      ],
    );
  }

  static String _base64OrPlain(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    try {
      final decoded = utf8.decode(base64.decode(normalized));
      if (decoded.contains(':')) return decoded;
    } catch (_) {
      // Not base64: SIP002 also allows a percent-encoded method:password.
    }
    return _decode(value);
  }

  /// Splits `host:port` or `[ipv6]:port`.
  static (String, String)? splitHostPort(String value) {
    final text = value.trim();
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end == -1) return null;
      final rest = text.substring(end + 1);
      return (
        text.substring(1, end),
        rest.startsWith(':') ? rest.substring(1) : '',
      );
    }
    final colon = text.lastIndexOf(':');
    if (colon == -1) return (text, '');
    return (text.substring(0, colon), text.substring(colon + 1));
  }

  static ConfigDraft _fromJson(String raw, VpnConfig original) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Not an object');
    final json = Map<String, dynamic>.from(decoded);
    final endpoint = XrayJsonConfig.serverEndpoint(json);
    final remarks = json['remarks']?.toString();
    return ConfigDraft._(
      original: original,
      format: DraftFormat.xrayJson,
      source: raw,
      jsonText: const JsonEncoder.withIndent('  ').convert(json),
      fields: _serverFields(
        (remarks == null || remarks.isEmpty) ? original.name : remarks,
        endpoint?['address']?.toString() ?? original.address,
        endpoint?['port']?.toString() ?? '${original.port}',
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Editing helpers
  // ---------------------------------------------------------------------

  bool get isJson => format == DraftFormat.xrayJson;

  /// Whether parameters can be added under Advanced.
  bool get supportsCustomParameters => !isJson;

  EditField field(String key) => fields.firstWhere((f) => f.key == key);

  EditField? fieldOrNull(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  List<EditField> section(EditSection section) =>
      fields.where((f) => f.section == section).toList();

  bool get hasChanges =>
      _structureChanged ||
      fields.any((f) => f.changed) ||
      jsonText != _initialJson;

  /// Set once a parameter was added or removed.
  bool _structureChanged = false;

  /// Adds a parameter, or returns an error message.
  String? addParameter(String key, String value) {
    final k = key.trim();
    if (k.isEmpty) return 'Enter a parameter name.';
    if (k.startsWith('@') || k.contains('=') || k.contains('&')) {
      return 'This name cannot be used.';
    }
    if (isReservedKey(k)) return 'This setting already has its own field.';
    final existing = fieldOrNull(k);
    if (existing != null) return 'This parameter is already listed.';
    fields.add(customField(k, value.trim()));
    _structureChanged = true;
    return null;
  }

  bool isReservedKey(String key) => _roles.values.contains(key);

  void removeField(EditField field) {
    if (fields.remove(field)) _structureChanged = true;
  }

  // ---------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------

  String get _name => field(nameKey).cleaned;
  String get _address => field(addressKey).cleaned;
  String get _port => field(portKey).cleaned;

  void _validate() {
    final address = _address;
    if (address.isEmpty) {
      throw const ConfigEditException('Enter the server address.');
    }
    if (address.contains(RegExp(r'\s'))) {
      throw const ConfigEditException(
        'The server address cannot contain spaces.',
      );
    }
    final port = int.tryParse(_port);
    if (port == null || port < 1 || port > 65535) {
      throw const ConfigEditException('Port must be a number from 1 to 65535.');
    }
    final secret = fieldOrNull(secretKey);
    if (secret != null && secret.value.isEmpty) {
      throw ConfigEditException('${secret.label} cannot be empty.');
    }
    final method = fieldOrNull(methodKey);
    if (method != null && method.cleaned.isEmpty) {
      throw const ConfigEditException('Choose an encryption method.');
    }
    for (final f in fields) {
      if (f.kind == EditKind.number &&
          f.cleaned.isNotEmpty &&
          int.tryParse(f.cleaned) == null) {
        throw ConfigEditException('${f.label} must be a number.');
      }
    }
  }

  /// Fields other than the name, address, port and identity, that should be
  /// written back: anything with a value, and keys the original had.
  Iterable<EditField> get _parameters => fields.where(
    (f) =>
        !f.key.startsWith('@') &&
        (f.cleaned.isNotEmpty || (f.wasPresent && !f.changed)),
  );

  /// The profile as a link (or JSON text), validated.
  String buildLink() {
    _validate();
    if (!hasChanges) return source;
    switch (format) {
      case DraftFormat.uri:
        return _buildUri();
      case DraftFormat.vmess:
        return 'vmess://${_encodeObject()}';
      case DraftFormat.ssh:
        return 'npvt-ssh://${_encodeObject()}';
      case DraftFormat.shadowsocks:
        return _buildShadowsocks();
      case DraftFormat.xrayJson:
        return jsonEncode(_buildJson());
    }
  }

  static String _hostForUri(String address) =>
      address.contains(':') && !address.startsWith('[')
      ? '[$address]'
      : address;

  String _query() => _parameters
      .map(
        (f) =>
            '${Uri.encodeQueryComponent(f.key)}=${Uri.encodeComponent(f.cleaned)}',
      )
      .join('&');

  String _buildUri() {
    final secret = Uri.encodeComponent(field(secretKey).value);
    final query = _query();
    final name = _name;
    return '$_scheme://$secret@${_hostForUri(_address)}:$_port'
        '${query.isEmpty ? '' : '?$query'}'
        '${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';
  }

  String _buildShadowsocks() {
    final userInfo = base64Url.encode(
      utf8.encode('${field(methodKey).cleaned}:${field(secretKey).value}'),
    );
    final query = _query();
    final name = _name;
    return 'ss://$userInfo@${_hostForUri(_address)}:$_port'
        '${query.isEmpty ? '' : '/?$query'}'
        '${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';
  }

  /// Converts [text] back to the type the original JSON used for [key].
  Object? _typed(String key, EditField? field, String text) {
    final before = _object[key];
    if (before == null && text.isEmpty && _object.containsKey(key)) {
      return null;
    }
    final kind = field?.kind;
    if (before is int || (before == null && kind == EditKind.number)) {
      return int.tryParse(text) ?? text;
    }
    if (before is double) return double.tryParse(text) ?? text;
    if (before is bool || (before == null && kind == EditKind.toggle)) {
      return text == 'true';
    }
    return text;
  }

  String _encodeObject() {
    final result = <String, dynamic>{};
    final written = <String>{};
    void put(String key, String text, EditField? f) {
      result[key] = _typed(key, f, text);
      written.add(key);
    }

    // Keep the original key order; removed custom keys are dropped.
    for (final key in _object.keys) {
      final role = _roles.entries
          .where((e) => e.value == key)
          .map((e) => e.key)
          .firstOrNull;
      if (role != null) {
        final f = field(role);
        if (role == portKey) {
          result[key] = _object[key] is String
              ? f.cleaned
              : int.parse(f.cleaned);
          written.add(key);
        } else {
          put(key, f.cleaned, f);
        }
        continue;
      }
      final f = fieldOrNull(key);
      if (f == null) continue;
      if (f.cleaned.isEmpty && !f.wasPresent) continue;
      put(key, f.cleaned, f);
    }
    for (final role in _roles.entries) {
      if (written.contains(role.value)) continue;
      final f = field(role.key);
      if (role.key == portKey) {
        result[role.value] = format == DraftFormat.vmess
            ? f.cleaned
            : int.parse(f.cleaned);
      } else if (f.cleaned.isNotEmpty) {
        result[role.value] = f.cleaned;
      }
      written.add(role.value);
    }
    for (final f in fields) {
      if (f.key.startsWith('@') || written.contains(f.key)) continue;
      if (f.cleaned.isEmpty) continue;
      put(f.key, f.cleaned, f);
    }
    return base64.encode(utf8.encode(jsonEncode(result)));
  }

  Map<String, dynamic> _buildJson() {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw ConfigEditException(
        'The configuration is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map || !XrayJsonConfig.isXrayConfig(decoded)) {
      throw const ConfigEditException(
        'The configuration needs an "outbounds" list with a server.',
      );
    }
    final json = Map<String, dynamic>.from(decoded);
    final endpoint = XrayJsonConfig.serverEndpoint(json);
    if (endpoint == null) {
      throw const ConfigEditException(
        'No server outbound was found in the configuration.',
      );
    }
    // The fields above the text win when they were edited.
    final address = field(addressKey);
    final port = field(portKey);
    if (address.changed) endpoint['address'] = address.cleaned;
    if (port.changed) endpoint['port'] = int.parse(port.cleaned);
    final name = field(nameKey);
    if (name.changed || json.containsKey('remarks')) {
      json['remarks'] = name.cleaned;
    }
    return json;
  }

  /// The edited profile, ready to replace [original].
  ///
  /// Keeps the route's identity (id, subscription, favorites and history
  /// are keyed by it). The measured latency is cleared when anything that
  /// affects the connection changed.
  VpnConfig build() {
    final link = buildLink();
    if (link == original.rawUrl && _name == original.name) return original;

    VpnConfig? parsed;
    if (isJson) {
      final json = jsonDecode(link) as Map<String, dynamic>;
      parsed = XrayJsonConfig.toVpnConfig(json, fallbackName: _name);
    } else {
      parsed = ConfigParserService.parseConfig(link);
    }
    if (parsed == null) {
      throw const ConfigEditException(
        'The edited profile could not be read. Check the fields you changed.',
      );
    }
    final reset = connectionDiffers(parsed, original);
    return parsed.copyWith(
      id: original.id,
      name: _name.isEmpty ? parsed.name : _name,
      createdAt: original.createdAt,
      isActive: original.isActive,
      country: original.country,
      countryCode: original.countryCode,
      subscriptionId: original.subscriptionId,
      ping: reset ? null : original.ping,
      lastTestedAt: reset ? null : original.lastTestedAt,
      clearPing: reset,
    );
  }

  /// Whether [a] and [b] would connect differently (anything but the name).
  static bool connectionDiffers(VpnConfig a, VpnConfig b) {
    final left = signature(a);
    final right = signature(b);
    if (left == null || right == null) return a.rawUrl != b.rawUrl;
    return left != right;
  }

  /// Every setting of [config] except its name, in a comparable form.
  static String? signature(VpnConfig config) {
    final draft = fromConfig(config);
    if (draft == null) return null;
    if (draft.isJson) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(draft.source) as Map)
          ..remove('remarks');
        return jsonEncode(map);
      } catch (_) {
        return null;
      }
    }
    final entries = [
      for (final f in draft.fields)
        if (f.key != nameKey && f.cleaned.isNotEmpty) '${f.key}=${f.cleaned}',
    ]..sort();
    return '${draft.format.name}|${draft._scheme}|${entries.join('\n')}';
  }
}
