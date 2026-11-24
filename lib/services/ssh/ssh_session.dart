import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_config.dart';
import 'socks_gateway.dart';
import 'ssh_transport.dart';
import 'udpgw.dart';

/// Why signing in or connecting failed, in words a person can act on.
class SshSessionException implements Exception {
  final SshCheckStep step;
  final String message;
  const SshSessionException(this.step, this.message);

  @override
  String toString() => message;
}

/// The steps of opening an SSH tunnel, in order.
enum SshCheckStep { reach, tls, upgrade, signIn, udpgw, dns }

/// An authenticated SSH connection that can open TCP streams.
class SshSession {
  final SshConfig config;
  final SSHClient client;
  final String? banner;

  SshSession._(this.config, this.client, this.banner);

  static Future<SshSession> connect(
    SshConfig config, {
    Duration timeout = const Duration(seconds: 20),
    void Function(SshCheckStep step)? onStep,
  }) async {
    final socket = await _openSocket(config, timeout, onStep);

    List<SSHKeyPair>? identities;
    if (config.usesPrivateKey) {
      try {
        identities = SSHKeyPair.fromPem(
          config.privateKey!.trim(),
          (config.keyPassphrase ?? '').isEmpty ? null : config.keyPassphrase,
        );
      } catch (_) {
        socket.destroy();
        throw const SshSessionException(
          SshCheckStep.signIn,
          'The private key could not be read. Check the key and its passphrase.',
        );
      }
    }

    final bannerParts = <String>[];
    final client = SSHClient(
      socket,
      username: config.sshUsername,
      identities: identities,
      onPasswordRequest: config.usesPrivateKey
          ? null
          : () => config.sshPassword,
      onUserInfoRequest: config.usesPrivateKey
          ? null
          : (request) => [for (final _ in request.prompts) config.sshPassword],
      onUserauthBanner: bannerParts.add,
      keepAliveInterval: const Duration(seconds: 15),
    );
    try {
      await client.authenticated.timeout(timeout);
    } catch (error) {
      client.close();
      throw SshSessionException(SshCheckStep.signIn, _signInMessage(error));
    }
    onStep?.call(SshCheckStep.signIn);
    final banner = bannerParts.join('\n').trim();
    return SshSession._(config, client, banner.isEmpty ? null : banner);
  }

  static Future<SSHSocket> _openSocket(
    SshConfig config,
    Duration timeout,
    void Function(SshCheckStep step)? onStep,
  ) async {
    try {
      return await SshTransport.open(
        config,
        timeout: timeout,
        onStep: (stage) => onStep?.call(switch (stage) {
          SshTransportStage.connect => SshCheckStep.reach,
          SshTransportStage.tls => SshCheckStep.tls,
          SshTransportStage.upgrade => SshCheckStep.upgrade,
        }),
      );
    } on SshTransportException catch (error) {
      throw SshSessionException(switch (error.stage) {
        SshTransportStage.connect => SshCheckStep.reach,
        SshTransportStage.tls => SshCheckStep.tls,
        SshTransportStage.upgrade => SshCheckStep.upgrade,
      }, error.message);
    }
  }

  static String _signInMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (error is SSHAuthFailError || text.contains('auth')) {
      if (text.contains('too many') || text.contains('maxlogins')) {
        return 'This account is already in use on another device.';
      }
      return 'The server refused the sign-in. Check the user name and '
          'password, or the account may have expired.';
    }
    if (error is TimeoutException || text.contains('timeout')) {
      return 'The server did not finish the SSH handshake in time.';
    }
    if (text.contains('version') || text.contains('ssh-')) {
      return 'The server did not answer as an SSH server. Check the port '
          'and connection type.';
    }
    if (text.contains('closed') || text.contains('reset')) {
      return 'The server closed the connection during sign-in.';
    }
    final short = error.toString();
    return 'SSH sign-in failed: '
        '${short.length > 120 ? '${short.substring(0, 120)}…' : short}';
  }

  Future<void> get done => client.done;
  bool get isClosed => client.isClosed;

  Future<TunnelStream> openTcp(String host, int port) async {
    final channel = await client.forwardLocal(host, port);
    return TunnelStream(channel.stream, channel.sink);
  }

  void close() => client.close();
}

/// Carries UDP for the SOCKS gateway: through the server's UDP gateway
/// when it has one, and DNS over TCP inside SSH otherwise.
class SshUdpBridge implements UdpForwarder {
  final SshConfig config;
  final SshSession? Function() session;

  SshUdpBridge(this.config, this.session);

  UdpgwSession? _udpgw;
  Future<UdpgwSession?>? _opening;
  DateTime? _retryAfter;
  final List<void Function(UdpgwSession?)> _waiting = [];

  @override
  void send({
    required String key,
    required InternetAddress address,
    required int port,
    required Uint8List data,
    required void Function(InternetAddress from, int port, Uint8List data)
    reply,
  }) {
    final isDns = port == 53;
    if (config.udpEnabled) {
      void viaGateway(UdpgwSession? gateway) {
        if (gateway == null) {
          if (isDns) _dnsOverTcp(address, data, reply);
          return;
        }
        gateway.send(
          key: key,
          address: address,
          port: port,
          data: data,
          dns: isDns && config.udpgwTransparentDNS,
          onReply: (packet) =>
              reply(packet.address ?? address, packet.port, packet.data),
        );
      }

      final gateway = _udpgw;
      if (gateway != null && !gateway.isClosed) {
        viaGateway(gateway);
      } else {
        if (_waiting.length < 256) _waiting.add(viaGateway);
        _openGateway();
      }
      return;
    }
    if (isDns) _dnsOverTcp(address, data, reply);
  }

  void _openGateway() {
    if (_opening != null) return;
    final retryAfter = _retryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      _flush(null);
      return;
    }
    _opening = _open().then((gateway) {
      _opening = null;
      _udpgw = gateway;
      if (gateway == null) {
        _retryAfter = DateTime.now().add(const Duration(seconds: 20));
      }
      _flush(gateway);
      return gateway;
    });
  }

  void _flush(UdpgwSession? gateway) {
    final waiting = List.of(_waiting);
    _waiting.clear();
    for (final callback in waiting) {
      callback(gateway);
    }
  }

  Future<UdpgwSession?> _open() async {
    final active = session();
    if (active == null || active.isClosed) return null;
    try {
      final stream = await active
          .openTcp('127.0.0.1', config.udpgwPort)
          .timeout(const Duration(seconds: 8));
      return UdpgwSession(stream.stream, stream.sink);
    } catch (_) {
      return null;
    }
  }

  Future<void> _dnsOverTcp(
    InternetAddress address,
    Uint8List query,
    void Function(InternetAddress from, int port, Uint8List data) reply,
  ) async {
    final active = session();
    if (active == null || active.isClosed || query.length > 65535) return;
    final custom = InternetAddress.tryParse(config.dnsServer ?? '');
    final server = custom ?? address;
    try {
      final answer = await DnsOverTcp.ask(active.openTcp, server, query);
      if (answer != null) reply(address, 53, answer);
    } catch (_) {}
  }

  @override
  void forget(String key) => _udpgw?.forget(key);

  /// Drops the gateway connection (for example after reconnecting).
  void reset() {
    unawaited(_udpgw?.close());
    _udpgw = null;
    _retryAfter = null;
  }

  Future<void> close() async {
    _flush(null);
    await _udpgw?.close();
    _udpgw = null;
  }
}

/// DNS over a TCP stream (RFC 1035 §4.2.2): a 2-byte length then the
/// message.
class DnsOverTcp {
  const DnsOverTcp._();

  static Future<Uint8List?> ask(
    TcpOpener open,
    InternetAddress server,
    Uint8List query, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final stream = await open(server.address, 53).timeout(timeout);
    final framed = Uint8List(query.length + 2)
      ..[0] = (query.length >> 8) & 0xff
      ..[1] = query.length & 0xff
      ..setAll(2, query);
    stream.sink.add(framed);
    final buffer = BytesBuilder(copy: false);
    final completer = Completer<Uint8List?>();
    late final StreamSubscription<Uint8List> subscription;
    subscription = stream.stream.listen(
      (data) {
        buffer.add(data);
        final bytes = buffer.toBytes();
        if (bytes.length >= 2) {
          final length = (bytes[0] << 8) | bytes[1];
          if (bytes.length >= length + 2 && !completer.isCompleted) {
            completer.complete(
              Uint8List.fromList(bytes.sublist(2, length + 2)),
            );
          }
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await subscription.cancel();
      try {
        await stream.sink.close();
      } catch (_) {}
    }
  }
}

/// Builds and reads the few DNS messages the server check needs.
class DnsMessage {
  const DnsMessage._();

  static final Random _random = Random();

  /// A recursive A-record query for [name].
  static (int, Uint8List) query(String name) {
    final id = _random.nextInt(0xffff);
    final bytes = BytesBuilder();
    bytes.add([id >> 8, id & 0xff, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      bytes.addByte(label.length);
      bytes.add(label.codeUnits);
    }
    bytes.add([0, 0, 1, 0, 1]);
    return (id, bytes.takeBytes());
  }

  /// Whether [answer] answers query [id] successfully with records.
  static bool isAnswer(Uint8List answer, int id) {
    if (answer.length < 12) return false;
    final answerId = (answer[0] << 8) | answer[1];
    final isResponse = answer[2] & 0x80 != 0;
    final rcode = answer[3] & 0x0f;
    final count = (answer[6] << 8) | answer[7];
    return answerId == id && isResponse && rcode == 0 && count > 0;
  }
}
