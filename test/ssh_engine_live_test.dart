// Live tests of the SSH engine against real servers on this machine.
//
// They run only when HV_SSH_LIVE=1 and these are listening on 127.0.0.1:
//   sshd 2222 (user hvtest), stunnel 2443 -> 2222, raw WebSocket relay
//   2080, framed WebSocket relay 2082, HTTP CONNECT proxy 2081,
//   badvpn-udpgw 7300, UDP echo 9999, HTTP 8099 serving hello.txt,
//   and a DNS responder on 127.0.0.2:53 used by udpgw (answers 10.9.8.7).
// HV_SSH_PASSWORD and HV_SSH_KEY (path to the private key) configure
// sign-in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/ssh_config.dart';
import 'package:hesam_void/services/ssh/socks_gateway.dart';
import 'package:hesam_void/services/ssh/ssh_check.dart';
import 'package:hesam_void/services/ssh/ssh_session.dart';
import 'package:hesam_void/widgets/ssh_check_sheet.dart';

final _live = Platform.environment['HV_SSH_LIVE'] == '1';
final _password = Platform.environment['HV_SSH_PASSWORD'] ?? '';

SshConfig _config({
  SshConfigType type = SshConfigType.direct,
  int port = 2222,
  String? password,
  String? key,
  String? sni,
  String? path,
  bool wsTls = false,
  bool framing = false,
  String? proxy,
  String? payload,
  int udpgw = 7300,
  bool transparentDns = true,
  String? dns,
}) => SshConfig(
  id: 'live',
  remarks: 'Live',
  configType: type,
  sshHost: '127.0.0.1',
  sshPort: port,
  sshUsername: 'hvtest',
  sshPassword: password ?? _password,
  privateKey: key,
  sni: sni,
  wsPath: path,
  wsTls: wsTls,
  wsFraming: framing,
  httpProxy: proxy,
  payload: payload,
  udpgwPort: udpgw,
  udpgwTransparentDNS: transparentDns,
  dnsServer: dns,
);

/// A running tunnel: SSH session plus the loopback SOCKS gateway.
class _Tunnel {
  final SshSession session;
  final SocksGateway gateway;
  final SshUdpBridge bridge;
  _Tunnel(this.session, this.gateway, this.bridge);

  static Future<_Tunnel> open(SshConfig config) async {
    final session = await SshSession.connect(config);
    late _Tunnel tunnel;
    final bridge = SshUdpBridge(config, () => tunnel.session);
    final gateway = SocksGateway(openTcp: session.openTcp, udp: bridge);
    await gateway.start();
    tunnel = _Tunnel(session, gateway, bridge);
    return tunnel;
  }

  Future<void> close() async {
    await gateway.close();
    await bridge.close();
    session.close();
  }
}

/// Fetches http://127.0.0.1:8099/hello.txt through the SOCKS gateway.
Future<String> _httpThroughSocks(int socksPort) async {
  final socket = await Socket.connect('127.0.0.1', socksPort);
  final reader = _Reader(socket);
  socket.add([5, 1, 0]);
  expect(await reader.take(2), [5, 0]);
  socket.add([5, 1, 0, 1, 127, 0, 0, 1, 8099 >> 8, 8099 & 0xff]);
  final reply = await reader.take(10);
  expect(reply[1], 0, reason: 'SOCKS CONNECT should succeed');
  socket.add(utf8.encode('GET /hello.txt HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n'));
  final body = await reader.rest();
  await socket.close();
  return utf8.decode(body, allowMalformed: true);
}

/// Sends one UDP datagram through SOCKS UDP ASSOCIATE and returns the reply.
Future<(InternetAddress, int, Uint8List)?> _udpThroughSocks(
  int socksPort,
  InternetAddress target,
  int port,
  List<int> data,
) async {
  final control = await Socket.connect('127.0.0.1', socksPort);
  final reader = _Reader(control);
  control.add([5, 1, 0]);
  await reader.take(2);
  control.add([5, 3, 0, 1, 0, 0, 0, 0, 0, 0]);
  final reply = await reader.take(10);
  expect(reply[1], 0, reason: 'UDP ASSOCIATE should succeed');
  final relayPort = (reply[8] << 8) | reply[9];
  final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final completer = Completer<(InternetAddress, int, Uint8List)?>();
  udp.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = udp.receive();
    if (dg == null || completer.isCompleted) return;
    final d = dg.data;
    final from = InternetAddress.fromRawAddress(
      Uint8List.fromList(d.sublist(4, 8)),
    );
    final fromPort = (d[8] << 8) | d[9];
    completer.complete((from, fromPort, Uint8List.fromList(d.sublist(10))));
  });
  udp.send(
    [0, 0, 0, 1, ...target.rawAddress, port >> 8, port & 0xff, ...data],
    InternetAddress.loopbackIPv4,
    relayPort,
  );
  try {
    return await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  } finally {
    udp.close();
    control.destroy();
  }
}

class _Reader {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  Completer<void>? _waiter;

  _Reader(Socket socket) {
    socket.listen(
      (data) {
        _buffer.add(data);
        _waiter?.complete();
        _waiter = null;
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
        _waiter?.complete();
        _waiter = null;
      },
    );
  }

  Future<List<int>> take(int count) async {
    while (_buffer.length < count) {
      if (_done.isCompleted) throw StateError('closed');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(const Duration(seconds: 10));
    }
    final bytes = _buffer.takeBytes();
    _buffer.add(bytes.sublist(count));
    return bytes.sublist(0, count);
  }

  Future<List<int>> rest() async {
    await _done.future.timeout(const Duration(seconds: 10));
    return _buffer.takeBytes();
  }
}

Future<void> _expectWorks(SshConfig config) async {
  final tunnel = await _Tunnel.open(config);
  try {
    final body = await _httpThroughSocks(tunnel.gateway.port);
    expect(body, contains('hello-through-ssh'));
  } finally {
    await tunnel.close();
  }
}

void main() {
  group('SSH engine (live)', skip: _live ? false : 'set HV_SSH_LIVE=1', () {
    test('direct: password sign-in, TCP and the server banner', () async {
      final tunnel = await _Tunnel.open(_config());
      try {
        expect(tunnel.session.banner, contains('Account expires'));
        expect(
          await _httpThroughSocks(tunnel.gateway.port),
          contains('hello-through-ssh'),
        );
      } finally {
        await tunnel.close();
      }
    });

    test('a wrong password is reported as a sign-in failure', () async {
      await expectLater(
        SshSession.connect(_config(password: 'wrong-password')),
        throwsA(
          isA<SshSessionException>().having(
            (e) => e.step,
            'step',
            SshCheckStep.signIn,
          ),
        ),
      );
    });

    test('private key sign-in', () async {
      final keyPath = Platform.environment['HV_SSH_KEY'];
      if (keyPath == null) return markTestSkipped('HV_SSH_KEY not set');
      await _expectWorks(
        _config(password: '', key: File(keyPath).readAsStringSync()),
      );
    });

    test('SSL/TLS with a custom SNI', () async {
      await _expectWorks(
        _config(
          type: SshConfigType.ssl,
          port: 2443,
          sni: 'allowed.example.com',
        ),
      );
    });

    test('WebSocket, raw after 101', () async {
      await _expectWorks(
        _config(type: SshConfigType.websocket, port: 2080, path: '/ssh'),
      );
    });

    test('WebSocket with frames', () async {
      await _expectWorks(
        _config(
          type: SshConfigType.websocket,
          port: 2082,
          path: '/ws',
          framing: true,
        ),
      );
    });

    test('through an HTTP proxy', () async {
      await _expectWorks(_config(proxy: '127.0.0.1:2081'));
    });

    test('custom payload with placeholders and a split', () async {
      await _expectWorks(
        _config(
          port: 2080,
          payload:
              'GET /cdn HTTP/1.1[crlf]Host: [host][crlf][split]'
              'Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]',
        ),
      );
    });

    test('UDP through the server UDP gateway', () async {
      final tunnel = await _Tunnel.open(_config());
      try {
        final reply = await _udpThroughSocks(
          tunnel.gateway.port,
          InternetAddress('127.0.0.1'),
          9999,
          utf8.encode('ping-udp'),
        );
        expect(reply, isNotNull);
        expect(utf8.decode(reply!.$3), 'echo:ping-udp');
        expect(reply.$2, 9999);
      } finally {
        await tunnel.close();
      }
    });

    test('DNS answered by the server through the UDP gateway', () async {
      final tunnel = await _Tunnel.open(_config());
      try {
        final (id, query) = DnsMessage.query('example.org');
        final reply = await _udpThroughSocks(
          tunnel.gateway.port,
          InternetAddress('1.1.1.1'),
          53,
          query,
        );
        expect(reply, isNotNull);
        expect(DnsMessage.isAnswer(reply!.$3, id), isTrue);
        expect(reply.$3.sublist(reply.$3.length - 4), [10, 9, 8, 7]);
        expect(
          reply.$1.address,
          '1.1.1.1',
          reason:
              'reply looks like it '
              'came from the address the app asked',
        );
      } finally {
        await tunnel.close();
      }
    });

    test('DNS over TCP inside SSH when there is no UDP gateway', () async {
      final tunnel = await _Tunnel.open(_config(udpgw: 0, dns: '127.0.0.2'));
      try {
        final (id, query) = DnsMessage.query('example.org');
        final reply = await _udpThroughSocks(
          tunnel.gateway.port,
          InternetAddress('1.1.1.1'),
          53,
          query,
        );
        expect(reply, isNotNull);
        expect(DnsMessage.isAnswer(reply!.$3, id), isTrue);
      } finally {
        await tunnel.close();
      }
    });

    test('server check reports every step', () async {
      final steps = <SshCheckStep>[];
      final report = await SshCheck.run(
        _config(type: SshConfigType.ssl, port: 2443, sni: 'a.example.com'),
        onResult: (r) => steps.add(r.step),
      );
      expect(steps, [
        SshCheckStep.reach,
        SshCheckStep.tls,
        SshCheckStep.signIn,
        SshCheckStep.udpgw,
        SshCheckStep.dns,
      ]);
      expect(
        report.results.map((r) => r.outcome),
        everyElement(SshCheckOutcome.passed),
      );
      expect(report.canConnect, isTrue);
      expect(report.banner, contains('Account expires'));
    });

    test('server check warns when the UDP gateway is missing', () async {
      final report = await SshCheck.run(_config(udpgw: 7399, dns: '127.0.0.2'));
      final udp = report.results.firstWhere(
        (r) => r.step == SshCheckStep.udpgw,
      );
      expect(udp.outcome, SshCheckOutcome.warning);
      final dns = report.results.firstWhere((r) => r.step == SshCheckStep.dns);
      expect(dns.outcome, SshCheckOutcome.passed);
      expect(report.canConnect, isTrue);
    });

    test('server check stops at a refused sign-in', () async {
      final report = await SshCheck.run(_config(password: 'nope'));
      final signIn = report.results.firstWhere(
        (r) => r.step == SshCheckStep.signIn,
      );
      expect(signIn.outcome, SshCheckOutcome.failed);
      expect(report.canConnect, isFalse);
    });

    testWidgets('check sheet walks through each step', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SshCheckSheet(
              config: _config(udpgw: 0, dns: '127.0.0.2'),
              accent: Colors.teal,
            ),
          ),
        ),
      );
      expect(find.text('Checking server…'), findsOneWidget);
      // Let real sockets make progress while the widget tree keeps pumping.
      for (
        var i = 0;
        i < 60 && find.text('Ready to connect').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Ready to connect'), findsOneWidget);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Account expires: 2026-12-31'), findsOneWidget);
    });
  });
}
