import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/vpn_config.dart';
import '../models/ssh_config.dart';

/// Professional VPN Configuration Parser
/// Supports: VLESS, VMess, Trojan, Shadowsocks, SSH (npvt-ssh://)
class ConfigParserService {
  static const _uuid = Uuid();

  /// Parse a single config URL - returns VpnConfig or null
  /// For SSH configs, use parseSshConfig() instead
  static VpnConfig? parseConfig(String url) {
    url = url.trim();
    if (url.isEmpty) return null;

    try {
      if (url.startsWith('vless://')) {
        return _parseVless(url);
      } else if (url.startsWith('vmess://')) {
        return _parseVmess(url);
      } else if (url.startsWith('trojan://')) {
        return _parseTrojan(url);
      } else if (url.startsWith('ss://')) {
        return _parseShadowsocks(url);
      } else if (url.startsWith('npvt-ssh://') || url.startsWith('ssh://')) {
        // Convert SSH to VpnConfig for unified handling
        return _parseSshToVpnConfig(url);
      }
    } catch (e) {
      // Return null for unparseable configs
      return null;
    }
    return null;
  }

  /// Parse SSH config from npvt-ssh:// URL
  static SshConfig? parseSshConfig(String url) {
    url = url.trim();
    if (url.isEmpty) return null;

    try {
      if (url.startsWith('npvt-ssh://')) {
        return SshConfig.fromNpvtUrl(url, _uuid.v4());
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Convert SSH URL to VpnConfig for unified storage
  static VpnConfig? _parseSshToVpnConfig(String url) {
    try {
      SshConfig? sshConfig;

      if (url.startsWith('npvt-ssh://')) {
        sshConfig = SshConfig.fromNpvtUrl(url, _uuid.v4());
      }

      if (sshConfig == null) return null;

      // Convert SSH config to VpnConfig format
      return VpnConfig(
        id: sshConfig.id,
        name: sshConfig.remarks.isNotEmpty ? sshConfig.remarks : 'SSH Server',
        rawUrl: url,
        protocolString: 'ssh',
        address: sshConfig.sshHost,
        port: sshConfig.sshPort,
        uuid: sshConfig.sshUsername, // Store username in uuid field
        password: sshConfig.sshPassword,
        transportString: sshConfig.configType.shortName.toLowerCase(),
        securityString: sshConfig.sni != null && sshConfig.sni!.isNotEmpty
            ? 'tls'
            : 'none',
        sni: sshConfig.sni,
        host: sshConfig.httpProxy,
        encryption: sshConfig.tlsVersion,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse multiple configs from text (one per line or separated)
  static List<VpnConfig> parseMultipleConfigs(String text) {
    final configs = <VpnConfig>[];

    // Split by newlines and common separators
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      final config = parseConfig(line);
      if (config != null) {
        configs.add(config);
      }
    }

    return configs;
  }

  /// Parse VLESS URL
  /// Format: vless://uuid@address:port?params#name
  static VpnConfig? _parseVless(String url) {
    final uri = Uri.parse(url);
    final uuid = uri.userInfo;
    final address = uri.host;
    final port = uri.port;
    final params = uri.queryParameters;
    final name = Uri.decodeComponent(
      uri.fragment.isNotEmpty ? uri.fragment : 'VLESS Server',
    );

    return VpnConfig(
      id: _uuid.v4(),
      name: name,
      rawUrl: url,
      protocolString: 'vless',
      address: address,
      port: port,
      uuid: uuid,
      transportString: params['type'] ?? 'tcp',
      securityString: params['security'] ?? 'none',
      sni: params['sni'],
      fingerprint: params['fp'],
      publicKey: params['pbk'],
      shortId: params['sid'],
      path: params['path'],
      host: params['host'],
      encryption: params['encryption'] ?? 'none',
      flow: params['flow'],
    );
  }

  /// Parse VMess URL (Base64 encoded JSON)
  /// Format: vmess://base64encodedJson
  static VpnConfig? _parseVmess(String url) {
    final base64Part = url.substring(8); // Remove 'vmess://'

    // Handle both standard and URL-safe base64
    String normalized = base64Part.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }

    final jsonStr = utf8.decode(base64.decode(normalized));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    final address = json['add']?.toString() ?? '';
    final port = int.tryParse(json['port']?.toString() ?? '443') ?? 443;
    final uuid = json['id']?.toString() ?? '';
    final name = json['ps']?.toString() ?? 'VMess Server';

    return VpnConfig(
      id: _uuid.v4(),
      name: name,
      rawUrl: url,
      protocolString: 'vmess',
      address: address,
      port: port,
      uuid: uuid,
      transportString: json['net']?.toString() ?? 'tcp',
      securityString: json['tls']?.toString() ?? 'none',
      sni: json['sni']?.toString(),
      host: json['host']?.toString(),
      path: json['path']?.toString(),
      encryption: json['type']?.toString() ?? 'auto',
    );
  }

  /// Parse Trojan URL
  /// Format: trojan://password@address:port?params#name
  static VpnConfig? _parseTrojan(String url) {
    final uri = Uri.parse(url);
    final password = uri.userInfo;
    final address = uri.host;
    final port = uri.port;
    final params = uri.queryParameters;
    final name = Uri.decodeComponent(
      uri.fragment.isNotEmpty ? uri.fragment : 'Trojan Server',
    );

    return VpnConfig(
      id: _uuid.v4(),
      name: name,
      rawUrl: url,
      protocolString: 'trojan',
      address: address,
      port: port,
      password: password,
      transportString: params['type'] ?? 'tcp',
      securityString: params['security'] ?? 'tls',
      sni: params['sni'] ?? address,
      fingerprint: params['fp'],
      path: params['path'],
      host: params['host'],
    );
  }

  /// Parse Shadowsocks URL
  /// Format: ss://base64(method:password)@address:port#name
  /// Or: ss://base64(method:password@address:port)#name
  static VpnConfig? _parseShadowsocks(String url) {
    String name = 'Shadowsocks Server';

    // Extract name from fragment
    final fragmentIndex = url.indexOf('#');
    if (fragmentIndex != -1) {
      name = Uri.decodeComponent(url.substring(fragmentIndex + 1));
      url = url.substring(0, fragmentIndex);
    }

    // Remove 'ss://'
    String remaining = url.substring(5);

    String method;
    String password;
    String address;
    int port;

    // Check if it's the SIP002 format (base64@host:port)
    if (remaining.contains('@')) {
      final atIndex = remaining.lastIndexOf('@');
      final encodedPart = remaining.substring(0, atIndex);
      final serverPart = remaining.substring(atIndex + 1);

      // Decode the method:password part
      String decoded;
      try {
        String normalized = encodedPart
            .replaceAll('-', '+')
            .replaceAll('_', '/');
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        decoded = utf8.decode(base64.decode(normalized));
      } catch (e) {
        decoded = encodedPart;
      }

      final colonIndex = decoded.indexOf(':');
      if (colonIndex != -1) {
        method = decoded.substring(0, colonIndex);
        password = decoded.substring(colonIndex + 1);
      } else {
        method = 'chacha20-ietf-poly1305';
        password = decoded;
      }

      // Parse server address and port
      final serverColonIndex = serverPart.lastIndexOf(':');
      if (serverColonIndex != -1) {
        address = serverPart.substring(0, serverColonIndex);
        port = int.tryParse(serverPart.substring(serverColonIndex + 1)) ?? 443;
      } else {
        address = serverPart;
        port = 443;
      }
    } else {
      // Legacy format: everything is base64 encoded
      String normalized = remaining.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = utf8.decode(base64.decode(normalized));

      // Parse method:password@address:port
      final atIndex = decoded.indexOf('@');
      if (atIndex == -1) return null;

      final methodPassword = decoded.substring(0, atIndex);
      final serverPart = decoded.substring(atIndex + 1);

      final colonIndex = methodPassword.indexOf(':');
      method = methodPassword.substring(0, colonIndex);
      password = methodPassword.substring(colonIndex + 1);

      final serverColonIndex = serverPart.lastIndexOf(':');
      address = serverPart.substring(0, serverColonIndex);
      port = int.tryParse(serverPart.substring(serverColonIndex + 1)) ?? 443;
    }

    return VpnConfig(
      id: _uuid.v4(),
      name: name,
      rawUrl: url + (name != 'Shadowsocks Server' ? '#$name' : ''),
      protocolString: 'ss',
      address: address,
      port: port,
      password: password,
      encryption: method,
      transportString: 'tcp',
      securityString: 'none',
    );
  }

  /// Export config back to URL format
  static String exportToUrl(VpnConfig config) {
    return config.rawUrl;
  }

  /// Validate if a string is a valid config URL
  static bool isValidConfigUrl(String url) {
    url = url.trim().toLowerCase();
    return url.startsWith('vless://') ||
        url.startsWith('vmess://') ||
        url.startsWith('trojan://') ||
        url.startsWith('ss://') ||
        url.startsWith('npvt-ssh://') ||
        url.startsWith('ssh://');
  }

  /// Check if URL is SSH protocol
  static bool isSshUrl(String url) {
    url = url.trim().toLowerCase();
    return url.startsWith('npvt-ssh://') || url.startsWith('ssh://');
  }

  /// Get protocol type from URL without full parsing
  static VpnProtocol getProtocolFromUrl(String url) {
    url = url.trim().toLowerCase();
    if (url.startsWith('vless://')) return VpnProtocol.vless;
    if (url.startsWith('vmess://')) return VpnProtocol.vmess;
    if (url.startsWith('trojan://')) return VpnProtocol.trojan;
    if (url.startsWith('ss://')) return VpnProtocol.shadowsocks;
    if (url.startsWith('npvt-ssh://') || url.startsWith('ssh://'))
      return VpnProtocol.ssh;
    return VpnProtocol.unknown;
  }

  /// Get detailed info from SSH config URL
  static Map<String, dynamic>? getSshConfigDetails(String url) {
    try {
      final sshConfig = parseSshConfig(url);
      if (sshConfig == null) return null;

      return {
        'type': sshConfig.configType.displayName,
        'host': sshConfig.sshHost,
        'port': sshConfig.sshPort,
        'username': sshConfig.sshUsername,
        'remarks': sshConfig.remarks,
        'hasSni': sshConfig.sni != null && sshConfig.sni!.isNotEmpty,
        'tlsVersion': sshConfig.tlsVersion,
        'dnsMode': sshConfig.dnsTTMode.name,
        'udpgwPort': sshConfig.udpgwPort,
      };
    } catch (e) {
      return null;
    }
  }
}
