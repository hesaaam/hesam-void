import 'dart:convert';

import '../models/vpn_config.dart';
import 'config_parser_service.dart';
import 'xray_json_config.dart';

enum ContentFormat {
  links,
  base64Links,
  xrayJson,
  singBox,
  clash,
  empty,
  unknown,
}

/// Routes found in a subscription response or pasted text.
class ParsedRoutes {
  final List<VpnConfig> configs;

  /// Entries recognised as routes but not supported (e.g. hysteria2://).
  final int unsupported;
  final ContentFormat format;

  const ParsedRoutes({
    required this.configs,
    required this.unsupported,
    required this.format,
  });

  bool get isUnsupportedFormat =>
      format == ContentFormat.singBox || format == ContentFormat.clash;

  /// A short, human description of why nothing could be imported.
  String get emptyReason {
    switch (format) {
      case ContentFormat.singBox:
        return 'This is a sing-box profile. Only links and Xray JSON are '
            'supported.';
      case ContentFormat.clash:
        return 'This is a Clash profile. Only links and Xray JSON are '
            'supported.';
      case ContentFormat.empty:
        return 'The subscription returned no content.';
      case ContentFormat.links:
      case ContentFormat.base64Links:
      case ContentFormat.xrayJson:
        return unsupported > 0
            ? 'Its $unsupported route${unsupported == 1 ? ' uses' : 's use'} '
                  'a protocol this app does not support yet.'
            : 'No supported routes were found.';
      case ContentFormat.unknown:
        return 'The content is not a list of routes.';
    }
  }
}

/// Usage and expiry from the `subscription-userinfo` response header.
class SubscriptionUserInfo {
  final int? upload;
  final int? download;
  final int? total;
  final DateTime? expire;

  const SubscriptionUserInfo({
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  static SubscriptionUserInfo? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final values = <String, int>{};
    for (final part in header.split(';')) {
      final pair = part.split('=');
      if (pair.length != 2) continue;
      final value = int.tryParse(pair[1].trim().split('.').first);
      if (value != null) values[pair[0].trim().toLowerCase()] = value;
    }
    if (values.isEmpty) return null;
    final expire = values['expire'];
    return SubscriptionUserInfo(
      upload: values['upload'],
      download: values['download'],
      // 0 conventionally means unlimited.
      total: (values['total'] ?? 0) > 0 ? values['total'] : null,
      expire: expire == null || expire <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expire * 1000),
    );
  }
}

class SubscriptionParser {
  const SubscriptionParser._();

  static final RegExp _schemeLine = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  /// Parses subscription bodies and pasted text: link lists (plain or base64)
  /// and Xray JSON (one object or an array).
  static ParsedRoutes parse(String text) {
    var body = text.replaceFirst('﻿', '').trim();
    if (body.isEmpty) {
      return const ParsedRoutes(
        configs: [],
        unsupported: 0,
        format: ContentFormat.empty,
      );
    }

    if (body.startsWith('{') || body.startsWith('[')) {
      final json = _tryJson(body);
      if (json != null) return _parseJson(json);
    }

    if (RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(body)) {
      return const ParsedRoutes(
        configs: [],
        unsupported: 0,
        format: ContentFormat.clash,
      );
    }

    var format = ContentFormat.links;
    if (!body.contains('://')) {
      final decoded = _tryBase64(body);
      if (decoded == null) {
        return const ParsedRoutes(
          configs: [],
          unsupported: 0,
          format: ContentFormat.unknown,
        );
      }
      final trimmed = decoded.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        final json = _tryJson(trimmed);
        if (json != null) return _parseJson(json);
      }
      body = trimmed;
      format = ContentFormat.base64Links;
    }

    final configs = <VpnConfig>[];
    final seen = <String>{};
    var unsupported = 0;
    final base = DateTime.now();
    for (final raw in body.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final config = ConfigParserService.parseConfig(line);
      if (config == null) {
        if (_schemeLine.hasMatch(line)) unsupported++;
        continue;
      }
      if (!seen.add(config.rawUrl)) continue;
      // Keeps the provider's order when lists are sorted newest first.
      configs.add(
        config.copyWith(
          createdAt: base.subtract(Duration(milliseconds: configs.length)),
        ),
      );
    }
    return ParsedRoutes(
      configs: configs,
      unsupported: unsupported,
      format: format,
    );
  }

  static ParsedRoutes _parseJson(Object json) {
    final items = json is List ? json : [json];
    final configs = <VpnConfig>[];
    final seen = <String>{};
    var unsupported = 0;
    var singBox = 0;
    final base = DateTime.now();
    for (final item in items) {
      if (XrayJsonConfig.isXrayConfig(item)) {
        final config = XrayJsonConfig.toVpnConfig(
          Map<String, dynamic>.from(item as Map),
          fallbackName: 'JSON route ${configs.length + 1}',
          createdAt: base.subtract(Duration(milliseconds: configs.length)),
        );
        if (config == null) {
          unsupported++;
        } else if (seen.add(config.rawUrl)) {
          configs.add(config);
        }
      } else if (XrayJsonConfig.isSingBoxConfig(item)) {
        singBox++;
      } else {
        unsupported++;
      }
    }
    final format = configs.isEmpty && singBox > 0 && unsupported == 0
        ? ContentFormat.singBox
        : (configs.isEmpty && unsupported == 0
              ? ContentFormat.unknown
              : ContentFormat.xrayJson);
    return ParsedRoutes(
      configs: configs,
      unsupported: unsupported + singBox,
      format: format,
    );
  }

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String? _tryBase64(String text) {
    var compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) {
      return null;
    }
    compact = compact.replaceAll('-', '+').replaceAll('_', '/');
    compact = compact.replaceAll('=', '');
    compact += '=' * ((4 - compact.length % 4) % 4);
    try {
      return utf8.decode(base64.decode(compact), allowMalformed: false);
    } catch (_) {
      return null;
    }
  }

  /// Folder name from `profile-title` (plain or `base64:` encoded).
  static String? decodeProfileTitle(String? header) {
    final value = header?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.toLowerCase().startsWith('base64:')) {
      final decoded = _tryBase64(value.substring(7));
      return decoded?.trim().isEmpty ?? true ? null : decoded!.trim();
    }
    return value;
  }

  /// Folder name from a `content-disposition` filename, without extension.
  static String? nameFromContentDisposition(String? header) {
    if (header == null) return null;
    final match = RegExp(
      r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(header);
    final file = match?.group(1);
    if (file == null) return null;
    final name = Uri.decodeComponent(file).replaceAll(RegExp(r'\.[^.]+$'), '');
    return name.trim().isEmpty ? null : name.trim();
  }

  /// Hours suggested by `profile-update-interval`, if any.
  static int? updateIntervalHours(String? header) {
    final hours = int.tryParse(header?.trim() ?? '');
    return hours == null || hours <= 0 ? null : hours;
  }
}

/// Result of applying a refreshed subscription to the stored routes.
class SubscriptionMerge {
  /// Every route of the subscription after the refresh, in provider order.
  final List<VpnConfig> routes;
  final List<VpnConfig> added;
  final List<VpnConfig> removed;

  const SubscriptionMerge({
    required this.routes,
    required this.added,
    required this.removed,
  });

  /// Matches routes by their link so unchanged ones keep their identity,
  /// latency and local health history.
  static SubscriptionMerge apply({
    required String subscriptionId,
    required List<VpnConfig> existing,
    required List<VpnConfig> incoming,
  }) {
    final byLink = {for (final config in existing) config.rawUrl: config};
    final routes = <VpnConfig>[];
    final added = <VpnConfig>[];
    for (final fresh in incoming) {
      final kept = byLink.remove(fresh.rawUrl);
      if (kept != null) {
        routes.add(kept.copyWith(name: fresh.name, createdAt: fresh.createdAt));
      } else {
        final created = fresh.copyWith(subscriptionId: subscriptionId);
        routes.add(created);
        added.add(created);
      }
    }
    return SubscriptionMerge(
      routes: routes,
      added: added,
      removed: byLink.values.toList(),
    );
  }
}
