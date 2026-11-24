import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One message of the badvpn-udpgw protocol.
class UdpgwPacket {
  final int flags;
  final int conid;
  final InternetAddress? address;
  final int port;
  final Uint8List data;

  const UdpgwPacket({
    required this.flags,
    required this.conid,
    this.address,
    this.port = 0,
    required this.data,
  });
}

/// Wire format of badvpn-udpgw, as used by SSH VPN servers.
///
/// Every message is a little-endian 16-bit length followed by: flags (1
/// byte), connection id (16-bit little-endian), the remote address (4 or
/// 16 bytes) and port (big-endian), then the datagram.
class UdpgwCodec {
  const UdpgwCodec._();

  static const flagKeepAlive = 0x01;
  static const flagRebind = 0x02;
  static const flagDns = 0x04;
  static const flagIpv6 = 0x08;

  static Uint8List encode(UdpgwPacket packet) {
    final keepAlive = packet.flags & flagKeepAlive != 0;
    final address = packet.address;
    final ipv6 = address?.type == InternetAddressType.IPv6;
    final addressBytes = keepAlive || address == null
        ? const <int>[]
        : address.rawAddress;
    final flags = packet.flags | (ipv6 && !keepAlive ? flagIpv6 : 0);
    final bodyLength =
        3 +
        (keepAlive ? 0 : addressBytes.length + 2) +
        (keepAlive ? 0 : packet.data.length);
    if (bodyLength > 0xffff) {
      throw ArgumentError('Datagram too large for udpgw.');
    }
    final out = Uint8List(2 + bodyLength);
    out[0] = bodyLength & 0xff;
    out[1] = (bodyLength >> 8) & 0xff;
    out[2] = flags;
    out[3] = packet.conid & 0xff;
    out[4] = (packet.conid >> 8) & 0xff;
    if (!keepAlive) {
      out.setAll(5, addressBytes);
      final portAt = 5 + addressBytes.length;
      out[portAt] = (packet.port >> 8) & 0xff;
      out[portAt + 1] = packet.port & 0xff;
      out.setAll(portAt + 2, packet.data);
    }
    return out;
  }

  static Uint8List keepAlive() =>
      encode(UdpgwPacket(flags: flagKeepAlive, conid: 0, data: Uint8List(0)));
}

/// Splits the udpgw byte stream back into packets.
class UdpgwDecoder {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  List<UdpgwPacket> add(List<int> data) {
    _buffer.add(data);
    final bytes = _buffer.takeBytes();
    final packets = <UdpgwPacket>[];
    var offset = 0;
    while (bytes.length - offset >= 2) {
      final length = bytes[offset] | (bytes[offset + 1] << 8);
      if (bytes.length - offset - 2 < length) break;
      final body = Uint8List.sublistView(
        bytes,
        offset + 2,
        offset + 2 + length,
      );
      offset += 2 + length;
      final packet = _parse(body);
      if (packet != null) packets.add(packet);
    }
    if (offset < bytes.length) _buffer.add(bytes.sublist(offset));
    return packets;
  }

  static UdpgwPacket? _parse(Uint8List body) {
    if (body.length < 3) return null;
    final flags = body[0];
    final conid = body[1] | (body[2] << 8);
    if (flags & UdpgwCodec.flagKeepAlive != 0) return null;
    final ipv6 = flags & UdpgwCodec.flagIpv6 != 0;
    final addressLength = ipv6 ? 16 : 4;
    if (body.length < 3 + addressLength + 2) return null;
    final address = InternetAddress.fromRawAddress(
      Uint8List.fromList(body.sublist(3, 3 + addressLength)),
    );
    final portAt = 3 + addressLength;
    final port = (body[portAt] << 8) | body[portAt + 1];
    return UdpgwPacket(
      flags: flags,
      conid: conid,
      address: address,
      port: port,
      data: Uint8List.fromList(body.sublist(portAt + 2)),
    );
  }
}

/// A connection to the server's UDP gateway over one SSH channel.
///
/// Each remote endpoint gets its own connection id, as the gateway keeps
/// one UDP socket per id. Replies are delivered to the callback registered
/// for that id.
class UdpgwSession {
  final StreamSink<List<int>> _sink;
  final UdpgwDecoder _decoder = UdpgwDecoder();
  final Map<String, int> _ids = <String, int>{};
  final Map<int, void Function(UdpgwPacket)> _handlers = {};
  final List<String> _order = <String>[];
  late final StreamSubscription<List<int>> _subscription;
  Timer? _keepAlive;
  int _next = 1;
  bool _closed = false;
  final Completer<void> _done = Completer<void>();

  static const maxConnections = 512;

  UdpgwSession(
    Stream<List<int>> stream,
    this._sink, {
    Duration keepAlive = const Duration(seconds: 10),
  }) {
    _subscription = stream.listen(
      _onData,
      onError: (_) => close(),
      onDone: close,
      cancelOnError: true,
    );
    _keepAlive = Timer.periodic(keepAlive, (_) {
      if (_closed) return;
      try {
        _sink.add(UdpgwCodec.keepAlive());
      } catch (_) {
        close();
      }
    });
  }

  bool get isClosed => _closed;
  Future<void> get done => _done.future;

  void _onData(List<int> data) {
    for (final packet in _decoder.add(data)) {
      _handlers[packet.conid]?.call(packet);
    }
  }

  /// Sends [data] to [address]:[port]; replies go to [onReply].
  /// [key] identifies the local sender, so different apps talking to the
  /// same endpoint do not share replies.
  void send({
    required String key,
    required InternetAddress address,
    required int port,
    required List<int> data,
    required bool dns,
    required void Function(UdpgwPacket) onReply,
  }) {
    if (_closed) return;
    final id = '$key|${address.address}|$port';
    var conid = _ids[id];
    if (conid == null) {
      if (_order.length >= maxConnections) {
        final oldest = _order.removeAt(0);
        final freed = _ids.remove(oldest);
        if (freed != null) _handlers.remove(freed);
      }
      conid = _allocate();
      _ids[id] = conid;
      _order.add(id);
    }
    _handlers[conid] = onReply;
    _sink.add(
      UdpgwCodec.encode(
        UdpgwPacket(
          flags: dns ? UdpgwCodec.flagDns : 0,
          conid: conid,
          address: address,
          port: port,
          data: Uint8List.fromList(data),
        ),
      ),
    );
  }

  int _allocate() {
    for (var tries = 0; tries < 65535; tries++) {
      final candidate = _next;
      _next = _next >= 65535 ? 1 : _next + 1;
      if (!_handlers.containsKey(candidate)) return candidate;
    }
    return 1;
  }

  /// Stops sending to every endpoint of [key] (its local socket closed).
  void forget(String key) {
    final prefix = '$key|';
    final stale = _ids.keys.where((id) => id.startsWith(prefix)).toList();
    for (final id in stale) {
      final conid = _ids.remove(id);
      _order.remove(id);
      if (conid != null) _handlers.remove(conid);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _keepAlive?.cancel();
    _handlers.clear();
    _ids.clear();
    _order.clear();
    await _subscription.cancel();
    try {
      await _sink.close();
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
  }
}
