import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/ssh_config.dart';
import 'package:hesam_void/services/config_parser_service.dart';
import 'package:hesam_void/services/ssh/ssh_session.dart';
import 'package:hesam_void/services/ssh/ssh_transport.dart';
import 'package:hesam_void/services/ssh/udpgw.dart';

void main() {
  group('ssh:// links', () {
    test('round-trip every setting', () {
      final source = SshConfig(
        id: 'a',
        remarks: 'Frankfurt SSL',
        configType: SshConfigType.ssl,
        sshHost: 'de1.example.net',
        sshPort: 443,
        sshUsername: 'user01',
        sshPassword: 'p@ss:word/#1',
        sni: 'allowed.example.com',
        payload: 'GET / HTTP/1.1[crlf]Host: [host][crlf][crlf]',
        udpgwPort: 7300,
        udpgwTransparentDNS: false,
        dnsServer: '1.1.1.1',
      );
      final link = source.toSshUrl();
      expect(link, startsWith('ssh://user01:'));
      final parsed = SshConfig.fromSshUrl(link, 'b');
      expect(parsed.remarks, 'Frankfurt SSL');
      expect(parsed.configType, SshConfigType.ssl);
      expect(parsed.sshHost, 'de1.example.net');
      expect(parsed.sshPort, 443);
      expect(parsed.sshUsername, 'user01');
      expect(parsed.sshPassword, 'p@ss:word/#1');
      expect(parsed.sni, 'allowed.example.com');
      expect(parsed.payload, source.payload);
      expect(parsed.udpgwPort, 7300);
      expect(parsed.udpgwTransparentDNS, isFalse);
      expect(parsed.dnsServer, '1.1.1.1');
      expect(parsed.usesTls, isTrue);
    });

    test('WebSocket and private key settings survive a round trip', () {
      final source = SshConfig(
        id: 'a',
        remarks: 'WS',
        configType: SshConfigType.websocket,
        sshHost: '2001:db8::5',
        sshPort: 80,
        sshUsername: 'u',
        sshPassword: '',
        privateKey:
            '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END '
            'OPENSSH PRIVATE KEY-----',
        wsPath: '/ssh',
        wsHost: 'cdn.example.com',
        wsFraming: true,
        udpgwPort: 0,
      );
      final parsed = SshConfig.fromSshUrl(source.toSshUrl(), 'b');
      expect(parsed.sshHost, '2001:db8::5');
      expect(parsed.wsPath, '/ssh');
      expect(parsed.wsHost, 'cdn.example.com');
      expect(parsed.wsFraming, isTrue);
      expect(parsed.wsTls, isFalse);
      expect(parsed.udpEnabled, isFalse);
      expect(parsed.privateKey, source.privateKey);
      expect(parsed.usesPrivateKey, isTrue);
    });

    test('a short hand-written link uses sensible defaults', () {
      final parsed = SshConfig.fromSshUrl('ssh://me:secret@1.2.3.4', 'x');
      expect(parsed.sshPort, 22);
      expect(parsed.configType, SshConfigType.direct);
      expect(parsed.udpgwPort, 7300);
      expect(parsed.udpgwTransparentDNS, isTrue);
      expect(parsed.remarks, 'me@1.2.3.4');
    });

    test('NPV Tunnel links are imported as ssh:// routes', () {
      final npvt =
          'npvt-ssh://${base64.encode(utf8.encode(jsonEncode({'sshConfigType': 'SSH-DIRECT', 'remarks': 'Ssh', 'sshHost': 'ssh.example.com', 'sshPort': 22, 'sshUsername': 'user', 'sshPassword': 'pw', 'udpgwPort': 7300, 'udpgwTransparentDNS': true})))}';
      final route = ConfigParserService.parseConfig(npvt);
      expect(route, isNotNull);
      expect(route!.isSsh, isTrue);
      expect(route.rawUrl, startsWith('ssh://'));
      final ssh = SshConfig.tryParse(route.rawUrl, route.id)!;
      expect(ssh.sshHost, 'ssh.example.com');
      expect(ssh.sshPassword, 'pw');
      expect(ssh.udpgwPort, 7300);
    });

    test('NPV WebSocket path stored in the payload becomes the path', () {
      final npvt = SshConfig(
        id: 'a',
        remarks: 'WS',
        configType: SshConfigType.websocket,
        sshHost: 'h.example.com',
        sshPort: 443,
        sshUsername: 'u',
        sshPassword: 'p',
        sni: 'cdn.example.com',
        payload: '/ssh',
      ).toNpvtUrl();
      final parsed = SshConfig.fromNpvtUrl(npvt, 'b');
      expect(parsed.wsPath, '/ssh');
      expect(parsed.wsTls, isTrue);
    });
  });

  test('payload placeholders', () {
    final config = SshConfig(
      id: 'a',
      remarks: 'a',
      configType: SshConfigType.direct,
      sshHost: 'h.example.com',
      sshPort: 22,
      sshUsername: 'u',
      sshPassword: 'p',
    );
    final text = SshTransport.expandPayload(
      'GET / [protocol][crlf]Host: [host_port][crlf][split]X: [unknown][lf]',
      config,
    );
    expect(text, startsWith('GET / HTTP/1.1\r\nHost: h.example.com:22\r\n'));
    expect(text, contains('X: [unknown]\n'));
    expect(text, contains('\u0000split\u0000'));
  });

  group('udpgw codec', () {
    test('encodes the badvpn wire format', () {
      final bytes = UdpgwCodec.encode(
        UdpgwPacket(
          flags: UdpgwCodec.flagDns,
          conid: 0x0102,
          address: InternetAddress('1.2.3.4'),
          port: 53,
          data: Uint8List.fromList([9, 9]),
        ),
      );
      // length 11 (LE), flags, conid LE, ip, port BE, data
      expect(bytes, [11, 0, 4, 2, 1, 1, 2, 3, 4, 0, 53, 9, 9]);
    });

    test('decodes replies split across reads', () {
      final decoder = UdpgwDecoder();
      final packet = UdpgwCodec.encode(
        UdpgwPacket(
          flags: 0,
          conid: 7,
          address: InternetAddress('2001:db8::1'),
          port: 443,
          data: Uint8List.fromList(utf8.encode('hello')),
        ),
      );
      expect(decoder.add(packet.sublist(0, 5)), isEmpty);
      final out = decoder.add(packet.sublist(5));
      expect(out, hasLength(1));
      expect(out.single.conid, 7);
      expect(out.single.address!.address, '2001:db8::1');
      expect(out.single.port, 443);
      expect(utf8.decode(out.single.data), 'hello');
    });

    test('keep-alive has no address', () {
      expect(UdpgwCodec.keepAlive(), [3, 0, 1, 0, 0]);
    });
  });

  test('WebSocket frames round-trip', () {
    final payload = Uint8List.fromList(List<int>.generate(300, (i) => i % 256));
    final frame = WebSocketFrames.encode(payload);
    final decoded = WebSocketFrames.decode(frame, 0)!;
    expect(decoded.opcode, 2);
    expect(decoded.payload, payload);
    expect(decoded.next, frame.length);
    expect(WebSocketFrames.decode(frame.sublist(0, 10), 0), isNull);
  });

  test('DNS query and answer check', () {
    final (id, query) = DnsMessage.query('example.org');
    expect(query.length, 12 + 13 + 4);
    final answer = Uint8List.fromList([
      ...query.sublist(0, 2),
      0x81,
      0x80,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      0,
      ...query.sublist(12),
    ]);
    expect(DnsMessage.isAnswer(answer, id), isTrue);
    expect(DnsMessage.isAnswer(answer, id + 1), isFalse);
  });
}
