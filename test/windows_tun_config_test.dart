import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/services/windows_xray_service.dart';

void main() {
  group('Windows Xray TUN configuration', () {
    test('owns a full system route and keeps Core outside its own TUN', () {
      final config = buildWindowsTunConfiguration(
        'vless://11111111-1111-4111-8111-111111111111@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp#desktop',
      );

      final inbound = (config['inbounds'] as List).single as Map;
      final settings = inbound['settings'] as Map;
      expect(inbound['protocol'], 'tun');
      expect(settings['userLevel'], 0);
      expect(settings['autoSystemRoutingTable'], <String>['0.0.0.0/0', '::/0']);
      expect(settings['autoOutboundsInterface'], 'auto');
      expect(settings['name'], 'hesamvoid');
    });

    test('normalizes legacy Reality publicKey into modern password', () {
      final config = buildWindowsTunConfiguration(
        'vless://11111111-1111-4111-8111-111111111111@example.com:443?encryption=mlkem768x25519plus.native.0rtt.test&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=public-key-for-contract-test&sid=abcd&spx=%2F&type=tcp#reality',
      );

      final outbound = (config['outbounds'] as List).first as Map;
      final stream = outbound['streamSettings'] as Map;
      final reality = stream['realitySettings'] as Map;
      expect(reality['password'], 'public-key-for-contract-test');
      expect(reality.containsKey('publicKey'), isFalse);
    });

    test('removes legacy TLS allowInsecure before Core receives JSON', () {
      final config = buildWindowsTunConfiguration(
        'vless://11111111-1111-4111-8111-111111111111@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp#tls',
      );

      expect(jsonEncode(config), isNot(contains('allowInsecure')));
    });
  });
}
