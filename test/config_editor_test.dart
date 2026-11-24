import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/ssh_config.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/providers/config_provider.dart';
import 'package:hesam_void/screens/config_edit_screen.dart';
import 'package:hesam_void/services/config_editor.dart';
import 'package:hesam_void/services/config_parser_service.dart';
import 'package:hesam_void/services/xray_json_config.dart';
import 'package:provider/provider.dart';

const _uuid = '11111111-1111-1111-1111-111111111111';

VpnConfig _saved(String link) {
  final config = ConfigParserService.parseConfig(link)!;
  return config.copyWith(
    id: 'route-1',
    ping: 120,
    lastTestedAt: DateTime(2026, 1, 1),
    subscriptionId: 'sub-1',
  );
}

Map<String, String> _query(String link) =>
    Uri.parse(link.split('#').first).queryParameters;

String _b64(Map<String, dynamic> json) =>
    base64.encode(utf8.encode(jsonEncode(json)));

Map<String, dynamic> _unb64(String link, String prefix) =>
    jsonDecode(utf8.decode(base64.decode(link.substring(prefix.length))))
        as Map<String, dynamic>;

void main() {
  group('VLESS', () {
    const link =
        'vless://$_uuid@old.example.com:443?type=tcp&security=reality'
        '&encryption=mlkem768x25519plus.native.0rtt.abc&flow=xtls-rprx-vision'
        '&sni=www.example.com&fp=chrome&pbk=public-key&sid=ab12'
        '&spx=%2F&headerType=none&packetEncoding=xudp#Germany%201';

    test('changing only the address keeps every other parameter', () {
      final original = _saved(link);
      final draft = ConfigDraft.fromConfig(original)!;
      expect(draft.field(ConfigDraft.addressKey).value, 'old.example.com');
      expect(draft.field(ConfigDraft.nameKey).value, 'Germany 1');

      draft.field(ConfigDraft.addressKey).value = 'new.example.com';
      final updated = draft.build();

      expect(updated.id, 'route-1');
      expect(updated.subscriptionId, 'sub-1');
      expect(updated.address, 'new.example.com');
      expect(updated.port, 443);
      expect(updated.name, 'Germany 1');
      expect(updated.uuid, _uuid);
      expect(updated.ping, isNull, reason: 'a new address needs a new test');
      expect(updated.lastTestedAt, isNull);
      expect(_query(updated.rawUrl), _query(link));
    });

    test('a name-only edit keeps the measured latency', () {
      final original = _saved(link);
      final draft = ConfigDraft.fromConfig(original)!;
      draft.field(ConfigDraft.nameKey).value = 'Frankfurt';
      final updated = draft.build();
      expect(updated.name, 'Frankfurt');
      expect(updated.ping, 120);
      expect(updated.rawUrl, endsWith('#Frankfurt'));
    });

    test('saving without changes returns the original route', () {
      final original = _saved(link);
      expect(
        identical(ConfigDraft.fromConfig(original)!.build(), original),
        isTrue,
      );
    });

    test('custom parameters can be added and removed', () {
      final draft = ConfigDraft.fromConfig(_saved(link))!;
      expect(draft.addParameter('allowInsecure', '1'), isNull);
      expect(draft.addParameter('sni', 'x'), isNotNull);
      expect(draft.field('headerType').custom, isFalse);
      final packet = draft.field('packetEncoding');
      expect(packet.custom, isTrue);
      draft.removeField(packet);
      final query = _query(draft.buildLink());
      expect(query['allowInsecure'], '1');
      expect(query['headerType'], 'none');
      expect(query.containsKey('packetEncoding'), isFalse);
    });

    test('rejects an invalid port and an empty address', () {
      final draft = ConfigDraft.fromConfig(_saved(link))!;
      draft.field(ConfigDraft.portKey).value = '70000';
      expect(draft.build, throwsA(isA<ConfigEditException>()));
      draft.field(ConfigDraft.portKey).value = '443';
      draft.field(ConfigDraft.addressKey).value = ' ';
      expect(draft.build, throwsA(isA<ConfigEditException>()));
    });

    test('writes IPv6 addresses in brackets', () {
      final draft = ConfigDraft.fromConfig(_saved(link))!;
      draft.field(ConfigDraft.addressKey).value = '2001:db8::1';
      final updated = draft.build();
      expect(updated.rawUrl, contains('@[2001:db8::1]:443'));
      expect(updated.address, '2001:db8::1');
    });
  });

  test('Trojan passwords with special characters survive a round trip', () {
    const password = 'p@ss:w/rd#1?';
    final link =
        'trojan://${Uri.encodeComponent(password)}@t.example.com:8443'
        '?type=ws&path=%2Fws&host=cdn.example.com&security=tls#T';
    final draft = ConfigDraft.fromConfig(_saved(link))!;
    expect(draft.field(ConfigDraft.secretKey).value, password);
    draft.field(ConfigDraft.portKey).value = '2083';
    final updated = draft.build();
    expect(Uri.decodeComponent(Uri.parse(updated.rawUrl).userInfo), password);
    expect(updated.port, 2083);
    expect(updated.path, '/ws');
    expect(updated.host, 'cdn.example.com');
  });

  test('VMess keeps value types and unknown keys', () {
    final link =
        'vmess://${_b64({'v': '2', 'ps': 'VM', 'add': 'a.example.com', 'port': '443', 'id': _uuid, 'aid': 0, 'scy': 'auto', 'net': 'ws', 'type': 'none', 'host': 'h.example.com', 'path': '/v', 'tls': 'tls', 'custom': 'keep'})}';
    final draft = ConfigDraft.fromConfig(_saved(link))!;
    draft.field(ConfigDraft.addressKey).value = 'b.example.com';
    draft.field('path').value = '/new';
    final updated = draft.build();
    final json = _unb64(updated.rawUrl, 'vmess://');
    expect(json['add'], 'b.example.com');
    expect(json['port'], '443');
    expect(json['aid'], 0);
    expect(json['path'], '/new');
    expect(json['custom'], 'keep');
    expect(updated.address, 'b.example.com');
  });

  test('Shadowsocks keeps plugin options', () {
    final userInfo = base64Url.encode(utf8.encode('aes-256-gcm:secret'));
    final link =
        'ss://$userInfo@s.example.com:8388/?plugin=v2ray-plugin%3Bmode%3Dwebsocket#SS';
    final original = _saved(link);
    expect(original.port, 8388);
    final draft = ConfigDraft.fromConfig(original)!;
    expect(draft.field(ConfigDraft.methodKey).value, 'aes-256-gcm');
    expect(draft.field('plugin').value, 'v2ray-plugin;mode=websocket');
    draft.field(ConfigDraft.addressKey).value = 'new.example.com';
    final updated = draft.build();
    expect(updated.address, 'new.example.com');
    expect(updated.port, 8388);
    expect(updated.password, 'secret');
    expect(updated.encryption, 'aes-256-gcm');
    expect(updated.rawUrl, contains('plugin=v2ray-plugin%3Bmode%3Dwebsocket'));
  });

  test('SSH profiles keep their settings after an edit', () {
    final link =
        'npvt-ssh://${_b64({'sshConfigType': 'SSH-SSL', 'remarks': 'SSH', 'sshHost': 'old.example.com', 'sshPort': 443, 'sshUsername': 'user', 'sshPassword': 'pw', 'sni': 'sni.example.com', 'udpgwPort': 7300, 'udpgwTransparentDNS': true, 'payload': 'GET / HTTP/1.1[crlf][crlf]'})}';
    final saved = _saved(link);
    expect(saved.rawUrl, startsWith('ssh://'), reason: 'imported as ssh://');
    final draft = ConfigDraft.fromConfig(saved)!;
    expect(draft.field('type').value, 'tls');
    draft.field(ConfigDraft.addressKey).value = 'new.example.com';
    draft.field('udpgw-dns').value = 'false';
    final updated = draft.build();
    final ssh = SshConfig.fromSshUrl(updated.rawUrl, 'x');
    expect(ssh.sshHost, 'new.example.com');
    expect(ssh.sshPort, 443);
    expect(ssh.sshUsername, 'user');
    expect(ssh.sshPassword, 'pw');
    expect(ssh.sni, 'sni.example.com');
    expect(ssh.configType, SshConfigType.ssl);
    expect(ssh.udpgwPort, 7300);
    expect(ssh.udpgwTransparentDNS, isFalse);
    expect(ssh.payload, 'GET / HTTP/1.1[crlf][crlf]');
    expect(updated.address, 'new.example.com');
    expect(updated.isSsh, isTrue);
    expect(updated.id, 'route-1');
  });

  group('Xray JSON', () {
    Map<String, dynamic> profile() => {
      'remarks': 'JSON route',
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'old.example.com',
                'port': 443,
                'users': [
                  {'id': _uuid, 'encryption': 'none'},
                ],
              },
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
    };

    VpnConfig saved() =>
        XrayJsonConfig.toVpnConfig(profile())!.copyWith(id: 'json-1', ping: 80);

    test('the address field updates the server outbound', () {
      final draft = ConfigDraft.fromConfig(saved())!;
      expect(draft.isJson, isTrue);
      expect(draft.field(ConfigDraft.addressKey).value, 'old.example.com');
      draft.field(ConfigDraft.addressKey).value = 'new.example.com';
      final updated = draft.build();
      expect(updated.id, 'json-1');
      expect(updated.isJson, isTrue);
      expect(updated.address, 'new.example.com');
      expect(updated.ping, isNull);
      final endpoint = XrayJsonConfig.serverEndpoint(
        jsonDecode(updated.rawUrl) as Map<String, dynamic>,
      );
      expect(endpoint!['address'], 'new.example.com');
    });

    test('edits in the text are kept when the fields are untouched', () {
      final draft = ConfigDraft.fromConfig(saved())!;
      draft.jsonText = draft.jsonText.replaceFirst('443', '8443');
      expect(draft.build().port, 8443);
    });

    test('invalid JSON is reported', () {
      final draft = ConfigDraft.fromConfig(saved())!;
      draft.jsonText = '{ "outbounds": [';
      expect(draft.build, throwsA(isA<ConfigEditException>()));
    });
  });

  test('a link edited as text replaces the route', () {
    final original = _saved('vless://$_uuid@a.example.com:443?security=tls#A');
    final draft = ConfigDraft.parse(
      'vless://$_uuid@b.example.com:2053?security=tls&sni=b.example.com#B',
      original,
    )!;
    final updated = draft.build();
    expect(updated.id, 'route-1');
    expect(updated.address, 'b.example.com');
    expect(updated.port, 2053);
    expect(updated.name, 'B');
    expect(updated.ping, isNull);
  });

  testWidgets('edit screen shows the server first and switches to link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final config = _saved(
      'vless://$_uuid@edit.example.com:2053?type=ws&path=%2Fws'
      '&security=tls&sni=edit.example.com#Edit%20me',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ConfigProvider(),
        child: MaterialApp(
          home: ConfigEditScreen(config: config, accent: Colors.teal),
        ),
      ),
    );

    expect(find.text('Edit route'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'edit.example.com'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2053'), findsOneWidget);
    // Detailed sections start collapsed.
    expect(find.text('Transport'), findsOneWidget);
    expect(find.widgetWithText(TextField, '/ws'), findsNothing);
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '/ws'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'edit.example.com'),
      'other.example.com',
    );
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('@other.example.com:2053'), findsOneWidget);
  });
}
