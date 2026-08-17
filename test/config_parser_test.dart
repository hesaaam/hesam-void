import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:hesam_void/models/ssh_config.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/services/config_parser_service.dart';

void main() {
  group('ConfigParserService', () {
    test('parses a VLESS Reality configuration', () {
      final config = ConfigParserService.parseConfig(
        'vless://11111111-1111-1111-1111-111111111111@example.com:443?type=tcp&security=reality&sni=www.example.com&fp=chrome&pbk=public-key&sid=abcd#Primary',
      );

      expect(config, isNotNull);
      expect(config!.protocol, VpnProtocol.vless);
      expect(config.isReality, isTrue);
      expect(config.name, 'Primary');
      expect(config.address, 'example.com');
      expect(config.port, 443);
    });

    test('preserves VLESS Reality Vision ML-KEM settings for Xray', () {
      const raw =
          'vless://33333333-3333-3333-3333-333333333333@reality.example.com:443?encryption=mlkem768x25519plus.native.0rtt.test-verification-key&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=test-public-key&sid=6bad&spx=%2F&type=tcp&headerType=none#Reality%20Vision';

      final parsed = ConfigParserService.parseConfig(raw);
      final fullConfig = FlutterV2ray.parseFromURL(raw).getFullConfiguration();
      final xray = jsonDecode(fullConfig) as Map<String, dynamic>;
      final outbound =
          (xray['outbounds'] as List).first as Map<String, dynamic>;
      final user =
          ((outbound['settings'] as Map<String, dynamic>)['vnext'] as List)
                  .first['users']
              as List;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      final reality = stream['realitySettings'] as Map<String, dynamic>;

      expect(parsed, isNotNull);
      expect(parsed!.isReality, isTrue);
      expect(parsed.flow, 'xtls-rprx-vision');
      expect(parsed.rawUrl, contains('mlkem768x25519plus.native.0rtt'));
      expect(
        (user.first as Map<String, dynamic>)['encryption'],
        'mlkem768x25519plus.native.0rtt.test-verification-key',
      );
      expect((user.first as Map<String, dynamic>)['flow'], 'xtls-rprx-vision');
      expect(stream['security'], 'reality');
      expect(reality['password'], 'test-public-key');
      expect(reality['shortId'], '6bad');
      expect(reality['spiderX'], '/');
    });

    test('parses a VMess JSON configuration', () {
      final encoded = base64.encode(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'v': '2',
            'ps': 'VMess profile',
            'add': 'vmess.example.com',
            'port': '443',
            'id': '22222222-2222-2222-2222-222222222222',
            'net': 'ws',
            'tls': 'tls',
            'host': 'cdn.example.com',
            'path': '/ws',
          }),
        ),
      );
      final config = ConfigParserService.parseConfig('vmess://$encoded');

      expect(config, isNotNull);
      expect(config!.protocol, VpnProtocol.vmess);
      expect(config.transport, TransportType.ws);
      expect(config.security, SecurityType.tls);
      expect(config.host, 'cdn.example.com');
    });

    test('parses a Shadowsocks SIP002 configuration', () {
      final credentials = base64Url.encode(
        utf8.encode('chacha20-ietf-poly1305:password'),
      );
      final config = ConfigParserService.parseConfig(
        'ss://$credentials@ss.example.com:8388#SS%20One',
      );

      expect(config, isNotNull);
      expect(config!.protocol, VpnProtocol.shadowsocks);
      expect(config.address, 'ss.example.com');
      expect(config.port, 8388);
      expect(config.name, 'SS One');
    });

    test('round-trips a NPVT SSH profile', () {
      final source = SshConfig(
        id: 'ssh-profile',
        remarks: 'Tunnel One',
        configType: SshConfigType.websocket,
        sshHost: 'ssh.example.com',
        sshPort: 443,
        sshUsername: 'user',
        sshPassword: 'secret',
        sni: 'cdn.example.com',
        payload: '/ssh',
      );

      final parsedSsh = SshConfig.fromNpvtUrl(source.toNpvtUrl(), 'parsed');
      final parsedVpn = ConfigParserService.parseConfig(source.toNpvtUrl());

      expect(parsedSsh.configType, SshConfigType.websocket);
      expect(parsedSsh.sshHost, 'ssh.example.com');
      expect(parsedSsh.payload, '/ssh');
      expect(parsedVpn, isNotNull);
      expect(parsedVpn!.isSsh, isTrue);
      expect(parsedVpn.sshUsername, 'user');
    });

    test('rejects unsupported configuration schemes', () {
      expect(ConfigParserService.parseConfig('https://example.com'), isNull);
      expect(
        ConfigParserService.isValidConfigUrl('https://example.com'),
        isFalse,
      );
    });
  });
}
