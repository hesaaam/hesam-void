import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A byte stream to a remote host, opened through the tunnel.
class TunnelStream {
  final Stream<Uint8List> stream;
  final StreamSink<List<int>> sink;
  const TunnelStream(this.stream, this.sink);
}

typedef TcpOpener = Future<TunnelStream> Function(String host, int port);

/// Sends UDP datagrams through the tunnel and delivers replies.
abstract class UdpForwarder {
  void send({
    required String key,
    required InternetAddress address,
    required int port,
    required Uint8List data,
    required void Function(InternetAddress from, int port, Uint8List data)
    reply,
  });

  /// The local sender [key] is gone.
  void forget(String key);
}

/// A loopback SOCKS5 server that carries TCP (CONNECT) and UDP (UDP
/// ASSOCIATE) through the tunnel. The VPN engine sends all device traffic
/// here.
class SocksGateway {
  final TcpOpener openTcp;
  final UdpForwarder? udp;
  final void Function()? onActivity;

  static const _handshakeTimeout = Duration(seconds: 12);

  SocksGateway({required this.openTcp, this.udp, this.onActivity});

  ServerSocket? _server;
  final Set<Socket> _clients = <Socket>{};
  final Set<RawDatagramSocket> _udpSockets = <RawDatagramSocket>{};
  int uploaded = 0;
  int downloaded = 0;
  int active = 0;
  int _associations = 0;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// Listens on loopback, trying [preferredPorts] first.
  Future<int> start({List<int> preferredPorts = const []}) async {
    Object? lastError;
    for (final candidate in <int>{...preferredPorts, 0}) {
      try {
        final server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
        );
        _server = server;
        server.listen(_handle, onError: (_) {});
        return server.port;
      } catch (error) {
        lastError = error;
      }
    }
    throw SocketException('Unable to bind a local SOCKS5 port: $lastError');
  }

  Future<void> close() async {
    for (final socket in _udpSockets.toList()) {
      socket.close();
    }
    _udpSockets.clear();
    for (final socket in _clients.toList()) {
      socket.destroy();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    active = 0;
  }

  void _changed() => onActivity?.call();

  void _handle(Socket client) {
    _clients.add(client);
    active++;
    _changed();

    final buffer = <int>[];
    var stage = 0; // 0 methods, 1 request, 2 relaying, 3 udp control
    var busy = false;
    var closed = false;
    TunnelStream? remote;
    StreamSubscription<Uint8List>? remoteSubscription;
    RawDatagramSocket? udpSocket;
    String? udpKey;
    late final StreamSubscription<Uint8List> clientSubscription;
    Timer? handshakeTimer;

    Future<void> finish() async {
      if (closed) return;
      closed = true;
      handshakeTimer?.cancel();
      await remoteSubscription?.cancel();
      try {
        await remote?.sink.close();
      } catch (_) {}
      if (udpSocket != null) {
        udpSocket!.close();
        _udpSockets.remove(udpSocket);
        if (udpKey != null) udp?.forget(udpKey!);
      }
      client.destroy();
      _clients.remove(client);
      if (active > 0) active--;
      _changed();
    }

    Future<void> connect(String host, int port, Uint8List early) async {
      try {
        final opened = await openTcp(host, port);
        if (closed) {
          await opened.sink.close();
          return;
        }
        remote = opened;
        client.add(_reply(0x00, InternetAddress.loopbackIPv4, 0));
        if (early.isNotEmpty) {
          opened.sink.add(early);
          uploaded += early.length;
        }
        remoteSubscription = opened.stream.listen(
          (data) {
            if (closed) return;
            client.add(data);
            downloaded += data.length;
          },
          onError: (_, _) => finish(),
          onDone: finish,
          cancelOnError: true,
        );
        stage = 2;
        busy = false;
        handshakeTimer?.cancel();
        clientSubscription.resume();
      } catch (_) {
        if (!closed) client.add(_reply(0x05, InternetAddress.loopbackIPv4, 0));
        await finish();
      }
    }

    Future<void> associate() async {
      final forwarder = udp;
      if (forwarder == null) {
        client.add(_reply(0x07, InternetAddress.loopbackIPv4, 0));
        await finish();
        return;
      }
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        udpSocket = socket;
        _udpSockets.add(socket);
        final key = 'u${_associations++}';
        udpKey = key;
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            final dg = datagram!;
            final parsed = _parseUdp(dg.data);
            if (parsed == null) continue;
            uploaded += parsed.$3.length;
            final senderAddress = dg.address;
            final senderPort = dg.port;
            forwarder.send(
              key: key,
              address: parsed.$1,
              port: parsed.$2,
              data: parsed.$3,
              reply: (from, fromPort, data) {
                if (closed) return;
                downloaded += data.length;
                socket.send(
                  _wrapUdp(from, fromPort, data),
                  senderAddress,
                  senderPort,
                );
              },
            );
          }
        });
        client.add(_reply(0x00, InternetAddress.loopbackIPv4, socket.port));
        stage = 3;
        busy = false;
        handshakeTimer?.cancel();
        clientSubscription.resume();
      } catch (_) {
        if (!closed) client.add(_reply(0x01, InternetAddress.loopbackIPv4, 0));
        await finish();
      }
    }

    void onData(Uint8List data) {
      if (closed) return;
      if (stage == 2) {
        remote?.sink.add(data);
        uploaded += data.length;
        return;
      }
      if (stage == 3 || busy) return;
      buffer.addAll(data);
      if (stage == 0) {
        if (buffer.length < 2) return;
        final count = buffer[1];
        if (buffer.length < count + 2) return;
        final methods = buffer.sublist(2, count + 2);
        buffer.removeRange(0, count + 2);
        if (buffer.isEmpty && !methods.contains(0x00)) {
          client.add(const [0x05, 0xff]);
          finish();
          return;
        }
        client.add(const [0x05, 0x00]);
        stage = 1;
      }
      if (stage != 1) return;
      final request = _parseRequest(buffer);
      if (request == null) return;
      if (request.error != null) {
        client.add(_reply(request.error!, InternetAddress.loopbackIPv4, 0));
        finish();
        return;
      }
      busy = true;
      clientSubscription.pause();
      if (request.command == 0x03) {
        associate();
      } else {
        connect(request.host!, request.port, request.early ?? Uint8List(0));
      }
    }

    clientSubscription = client.listen(
      onData,
      onError: (_, _) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    handshakeTimer = Timer(_handshakeTimeout, () {
      if (stage < 2) finish();
    });
  }

  static _Request? _parseRequest(List<int> buffer) {
    if (buffer.length < 4) return null;
    if (buffer[0] != 0x05) return const _Request.error(0x07);
    final command = buffer[1];
    if (command != 0x01 && command != 0x03) return const _Request.error(0x07);
    final type = buffer[3];
    String host;
    int end;
    if (type == 0x01) {
      end = 10;
      if (buffer.length < end) return null;
      host = buffer.sublist(4, 8).join('.');
    } else if (type == 0x03) {
      if (buffer.length < 5) return null;
      final length = buffer[4];
      end = 7 + length;
      if (buffer.length < end) return null;
      host = String.fromCharCodes(buffer.sublist(5, 5 + length));
    } else if (type == 0x04) {
      end = 22;
      if (buffer.length < end) return null;
      host = InternetAddress.fromRawAddress(
        Uint8List.fromList(buffer.sublist(4, 20)),
      ).address;
    } else {
      return const _Request.error(0x08);
    }
    final port = (buffer[end - 2] << 8) | buffer[end - 1];
    final early = Uint8List.fromList(buffer.sublist(end));
    buffer.clear();
    return _Request(command, host, port, early);
  }

  static List<int> _reply(int code, InternetAddress address, int port) => [
    0x05,
    code,
    0x00,
    0x01,
    ...address.rawAddress,
    (port >> 8) & 0xff,
    port & 0xff,
  ];

  /// SOCKS5 UDP request: RSV(2) FRAG ATYP ADDR PORT DATA.
  static (InternetAddress, int, Uint8List)? _parseUdp(Uint8List packet) {
    if (packet.length < 10 || packet[2] != 0) return null;
    final type = packet[3];
    InternetAddress address;
    int offset;
    if (type == 0x01) {
      address = InternetAddress.fromRawAddress(
        Uint8List.fromList(packet.sublist(4, 8)),
      );
      offset = 8;
    } else if (type == 0x04) {
      if (packet.length < 22) return null;
      address = InternetAddress.fromRawAddress(
        Uint8List.fromList(packet.sublist(4, 20)),
      );
      offset = 20;
    } else {
      // Domain names would have to be resolved outside the tunnel.
      return null;
    }
    final port = (packet[offset] << 8) | packet[offset + 1];
    return (address, port, Uint8List.sublistView(packet, offset + 2));
  }

  static Uint8List _wrapUdp(InternetAddress from, int port, Uint8List data) {
    final raw = from.rawAddress;
    final out = Uint8List(4 + raw.length + 2 + data.length);
    out[3] = raw.length == 4 ? 0x01 : 0x04;
    out.setAll(4, raw);
    out[4 + raw.length] = (port >> 8) & 0xff;
    out[5 + raw.length] = port & 0xff;
    out.setAll(6 + raw.length, data);
    return out;
  }
}

class _Request {
  final int command;
  final String? host;
  final int port;
  final Uint8List? early;
  final int? error;

  _Request(this.command, this.host, this.port, this.early) : error = null;
  const _Request.error(this.error)
    : command = 0,
      host = null,
      port = 0,
      early = null;
}
