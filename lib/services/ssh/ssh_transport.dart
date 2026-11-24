import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_config.dart';

/// Which step of opening the connection failed.
enum SshTransportStage { connect, tls, upgrade }

class SshTransportException implements Exception {
  final SshTransportStage stage;
  final String message;
  const SshTransportException(this.stage, this.message);

  @override
  String toString() => message;
}

/// Opens the byte stream SSH runs over: a plain TCP connection, TLS with a
/// chosen server name, a WebSocket upgrade (raw or framed), an HTTP proxy,
/// or a custom payload sent before SSH starts.
class SshTransport {
  const SshTransport._();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  /// Called with each finished step, for the server check.
  static Future<SSHSocket> open(
    SshConfig config, {
    Duration timeout = const Duration(seconds: 20),
    void Function(SshTransportStage stage)? onStep,
  }) async {
    if (config.configType == SshConfigType.slowDns) {
      throw const SshTransportException(
        SshTransportStage.connect,
        'SSH over SlowDNS is not supported yet.',
      );
    }
    final proxy = _proxyEndpoint(config.httpProxy);
    if (proxy != null && config.usesTls) {
      throw const SshTransportException(
        SshTransportStage.connect,
        'An HTTP proxy cannot be combined with SSL/TLS yet.',
      );
    }

    final host = proxy?.$1 ?? config.sshHost;
    final port = proxy?.$2 ?? config.sshPort;
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (error) {
      throw SshTransportException(
        SshTransportStage.connect,
        _connectMessage(error, host, port),
      );
    }
    onStep?.call(SshTransportStage.connect);

    if (config.usesTls) {
      try {
        socket = await SecureSocket.secure(
          socket,
          host: config.tlsServerName,
          // TLS only disguises the connection here; SSH itself encrypts and
          // authenticates, and these servers commonly use self-signed
          // certificates.
          onBadCertificate: (_) => true,
        ).timeout(timeout);
      } catch (error) {
        socket.destroy();
        throw SshTransportException(
          SshTransportStage.tls,
          'TLS handshake failed with SNI ${config.tlsServerName}: '
          '${_short(error)}',
        );
      }
      onStep?.call(SshTransportStage.tls);
    }

    final channel = _ByteChannel(socket);
    try {
      final request = _firstRequest(config, proxy != null);
      if (request != null) {
        await channel.sendPayload(request);
        await channel.skipHttpResponses(timeout);
        onStep?.call(SshTransportStage.upgrade);
      }
    } on SshTransportException {
      channel.destroy();
      rethrow;
    } catch (error) {
      channel.destroy();
      throw SshTransportException(
        SshTransportStage.upgrade,
        'The server did not accept the request: ${_short(error)}',
      );
    }

    final framed =
        config.configType == SshConfigType.websocket && config.wsFraming;
    return framed ? _WebSocketFramedSocket(channel) : channel.handOver();
  }

  static (String, int)? _proxyEndpoint(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final colon = text.lastIndexOf(':');
    if (colon <= 0) return null;
    final port = int.tryParse(text.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return (text.substring(0, colon), port);
  }

  /// The HTTP request sent before SSH, or null to start SSH right away.
  static String? _firstRequest(SshConfig config, bool viaProxy) {
    final payload = config.payload;
    if (payload != null && payload.trim().isNotEmpty) {
      return expandPayload(payload, config);
    }
    if (config.configType == SshConfigType.websocket) {
      final path = (config.wsPath == null || config.wsPath!.isEmpty)
          ? '/'
          : config.wsPath!;
      final hostHeader = (config.wsHost == null || config.wsHost!.isEmpty)
          ? config.sshHost
          : config.wsHost!;
      final key = base64.encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );
      return 'GET $path HTTP/1.1\r\n'
          'Host: $hostHeader\r\n'
          'User-Agent: $userAgent\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: 13\r\n\r\n';
    }
    if (viaProxy) {
      final target = '${config.sshHost}:${config.sshPort}';
      final auth = config.authenticateProxy
          ? 'Proxy-Authorization: Basic ${base64.encode(utf8.encode('${config.proxyUsername ?? ''}:${config.proxyPassword ?? ''}'))}\r\n'
          : '';
      return 'CONNECT $target HTTP/1.1\r\nHost: $target\r\n$auth\r\n';
    }
    return null;
  }

  /// Replaces payload placeholders. `[split]` marks are kept for sending.
  static String expandPayload(String payload, SshConfig config) {
    final hostPort = '${config.sshHost}:${config.sshPort}';
    final values = <String, String>{
      'host': config.sshHost,
      'port': '${config.sshPort}',
      'host_port': hostPort,
      'ssh': hostPort,
      'sni': config.tlsServerName,
      'protocol': 'HTTP/1.1',
      'method': 'CONNECT',
      'ua': userAgent,
      'user_agent': userAgent,
      'raw': 'CONNECT $hostPort HTTP/1.1',
      'netdata': 'CONNECT $hostPort HTTP/1.1',
      'real_raw': 'CONNECT $hostPort HTTP/1.1',
      'crlf': '\r\n',
      'lfcr': '\n\r',
      'lf': '\n',
      'cr': '\r',
    };
    return payload.replaceAllMapped(RegExp(r'\[([a-zA-Z_]+)\]'), (match) {
      final key = match.group(1)!.toLowerCase();
      if (key == 'split' || key == 'delay_split' || key == 'instant_split') {
        return _splitMark;
      }
      return values[key] ?? match.group(0)!;
    });
  }

  static const _splitMark = '\u0000split\u0000';

  static String _connectMessage(Object error, String host, int port) {
    final text = error.toString().toLowerCase();
    if (text.contains('refused')) {
      return 'Connection refused by $host:$port.';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return '$host:$port did not answer in time.';
    }
    if (text.contains('host lookup') || text.contains('no address')) {
      return 'The address $host could not be found.';
    }
    if (text.contains('unreachable')) return 'The network is unreachable.';
    return 'Could not reach $host:$port: ${_short(error)}';
  }

  static String _short(Object error) {
    final text = error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }
}

/// A socket that is first read by hand (HTTP responses) and then handed to
/// SSH with any bytes already received.
class _ByteChannel {
  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  Completer<void>? _waiter;
  StreamController<Uint8List>? _output;
  Object? _error;
  bool _closed = false;

  _ByteChannel(this._socket) {
    _subscription = _socket.listen(
      (data) {
        final output = _output;
        if (output != null) {
          output.add(data);
        } else {
          _pending.add(data);
          _wake();
        }
      },
      onError: (Object error) {
        _error = error;
        _output?.addError(error);
        _wake();
      },
      onDone: () {
        _closed = true;
        _output?.close();
        _wake();
      },
      cancelOnError: false,
    );
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<bool> _waitForData(Duration timeout) async {
    if (_pending.isNotEmpty) return true;
    if (_closed || _error != null) return false;
    _waiter = Completer<void>();
    try {
      await _waiter!.future.timeout(timeout);
    } on TimeoutException {
      return false;
    }
    return _pending.isNotEmpty;
  }

  Future<void> sendPayload(String request) async {
    final parts = request.split(SshTransport._splitMark);
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      _socket.add(latin1.encode(parts[i]));
      await _socket.flush();
      if (i < parts.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Drops `HTTP/…` response blocks in front of the SSH stream.
  Future<void> skipHttpResponses(Duration timeout) async {
    for (var round = 0; round < 4; round++) {
      final first = round == 0;
      final hasData = await _waitForData(
        first ? timeout : const Duration(milliseconds: 700),
      );
      if (!hasData) {
        if (first) {
          throw SshTransportException(
            SshTransportStage.upgrade,
            _closed
                ? 'The server closed the connection after the request.'
                : 'The server did not answer the request.',
          );
        }
        return;
      }
      var bytes = _pending.toBytes();
      // Too short to tell yet: wait for a few more bytes.
      while (bytes.length < 5 && _isPrefixOf(bytes, 'HTTP/')) {
        if (!await _moreData(const Duration(seconds: 3))) break;
        bytes = _pending.toBytes();
      }
      if (!_startsWith(bytes, 'HTTP/')) return;
      // Wait for the whole header block.
      while (_indexOfHeaderEnd(bytes) == -1) {
        if (!await _moreData(timeout)) {
          throw const SshTransportException(
            SshTransportStage.upgrade,
            'The server sent an incomplete HTTP response.',
          );
        }
        bytes = _pending.toBytes();
      }
      final end = _indexOfHeaderEnd(bytes);
      final statusLine = latin1
          .decode(bytes.sublist(0, end))
          .split('\r\n')
          .first;
      final code = int.tryParse(statusLine.split(' ').elementAtOrNull(1) ?? '');
      if (code != null && code >= 400 && code != 101) {
        // Some relays still pass SSH after an error status; only stop when
        // nothing follows.
        final rest = bytes.sublist(end + 4);
        if (rest.isEmpty && !await _peek(const Duration(milliseconds: 1500))) {
          throw SshTransportException(
            SshTransportStage.upgrade,
            'The server refused the request: $statusLine',
          );
        }
      }
      _pending.clear();
      _pending.add(bytes.sublist(end + 4));
    }
  }

  Future<bool> _moreData(Duration timeout) async {
    final before = _pending.length;
    _waiter = Completer<void>();
    try {
      await _waiter!.future.timeout(timeout);
    } on TimeoutException {
      return false;
    }
    return _pending.length > before;
  }

  Future<bool> _peek(Duration timeout) async {
    final before = _pending.length;
    if (_closed) return false;
    _waiter = Completer<void>();
    try {
      await _waiter!.future.timeout(timeout);
    } on TimeoutException {
      return false;
    }
    return _pending.length > before;
  }

  static bool _startsWith(Uint8List bytes, String prefix) {
    if (bytes.length < prefix.length) return false;
    return latin1.decode(bytes.sublist(0, prefix.length)) == prefix;
  }

  static bool _isPrefixOf(Uint8List bytes, String text) {
    if (bytes.length > text.length) return false;
    return latin1.decode(bytes) == text.substring(0, bytes.length);
  }

  static int _indexOfHeaderEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// Stream of everything received from now on, starting with bytes
  /// already buffered.
  Stream<Uint8List> takeStream() {
    final output = StreamController<Uint8List>(sync: true);
    final leftover = _pending.takeBytes();
    if (leftover.isNotEmpty) output.add(leftover);
    if (_error != null) output.addError(_error!);
    if (_closed) {
      output.close();
    }
    _output = output;
    return output.stream;
  }

  Socket get socket => _socket;

  SSHSocket handOver() => _ChannelSshSocket(this);

  void destroy() {
    _subscription.cancel();
    _socket.destroy();
  }
}

class _ChannelSshSocket implements SSHSocket {
  final _ByteChannel _channel;
  late final Stream<Uint8List> _stream = _channel.takeStream();

  _ChannelSshSocket(this._channel);

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _channel.socket;

  @override
  Future<void> get done => _channel.socket.done;

  @override
  Future<void> close() async {
    await _channel.socket.close();
  }

  @override
  void destroy() => _channel.destroy();
}

/// SSH carried inside WebSocket binary frames (websockify-style servers).
class _WebSocketFramedSocket implements SSHSocket {
  final _ByteChannel _channel;
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  late final _FrameSink _sink = _FrameSink(_channel.socket);
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  _WebSocketFramedSocket(this._channel) {
    _channel.takeStream().listen(
      _onData,
      onError: _incoming.addError,
      onDone: _incoming.close,
    );
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (true) {
      final frame = WebSocketFrames.decode(bytes, offset);
      if (frame == null) break;
      offset = frame.next;
      switch (frame.opcode) {
        case 0x0:
        case 0x1:
        case 0x2:
          if (frame.payload.isNotEmpty) _incoming.add(frame.payload);
        case 0x8:
          _incoming.close();
          _channel.socket.destroy();
          return;
        case 0x9:
          _channel.socket.add(
            WebSocketFrames.encode(frame.payload, opcode: 0xA),
          );
        default:
          break;
      }
    }
    if (offset < bytes.length) _buffer.add(bytes.sublist(offset));
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => _sink;

  @override
  Future<void> get done => _channel.socket.done;

  @override
  Future<void> close() async {
    try {
      _channel.socket.add(WebSocketFrames.encode(const [], opcode: 0x8));
    } catch (_) {}
    await _channel.socket.close();
  }

  @override
  void destroy() => _channel.destroy();
}

class _FrameSink implements StreamSink<List<int>> {
  final Socket _socket;
  _FrameSink(this._socket);

  @override
  void add(List<int> data) => _socket.add(WebSocketFrames.encode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;
}

class WebSocketFrame {
  final int opcode;
  final Uint8List payload;
  final int next;
  const WebSocketFrame(this.opcode, this.payload, this.next);
}

/// Minimal RFC 6455 framing for the client side.
class WebSocketFrames {
  const WebSocketFrames._();

  static final Random _random = Random.secure();

  static Uint8List encode(List<int> payload, {int opcode = 0x2}) {
    final length = payload.length;
    final header = BytesBuilder();
    header.addByte(0x80 | opcode);
    if (length < 126) {
      header.addByte(0x80 | length);
    } else if (length < 65536) {
      header.addByte(0x80 | 126);
      header.add([(length >> 8) & 0xff, length & 0xff]);
    } else {
      header.addByte(0x80 | 127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        header.addByte((length >> shift) & 0xff);
      }
    }
    final mask = List<int>.generate(4, (_) => _random.nextInt(256));
    header.add(mask);
    final out = Uint8List(header.length + length);
    out.setAll(0, header.takeBytes());
    final start = out.length - length;
    for (var i = 0; i < length; i++) {
      out[start + i] = payload[i] ^ mask[i & 3];
    }
    return out;
  }

  /// Decodes one frame at [offset], or null when it is not complete yet.
  static WebSocketFrame? decode(Uint8List bytes, int offset) {
    if (bytes.length - offset < 2) return null;
    final opcode = bytes[offset] & 0x0f;
    final masked = (bytes[offset + 1] & 0x80) != 0;
    var length = bytes[offset + 1] & 0x7f;
    var position = offset + 2;
    if (length == 126) {
      if (bytes.length < position + 2) return null;
      length = (bytes[position] << 8) | bytes[position + 1];
      position += 2;
    } else if (length == 127) {
      if (bytes.length < position + 8) return null;
      length = 0;
      for (var i = 0; i < 8; i++) {
        length = (length << 8) | bytes[position + i];
      }
      position += 8;
    }
    List<int>? mask;
    if (masked) {
      if (bytes.length < position + 4) return null;
      mask = bytes.sublist(position, position + 4);
      position += 4;
    }
    if (bytes.length < position + length) return null;
    final payload = Uint8List.fromList(
      bytes.sublist(position, position + length),
    );
    if (mask != null) {
      for (var i = 0; i < payload.length; i++) {
        payload[i] ^= mask[i & 3];
      }
    }
    return WebSocketFrame(opcode, payload, position + length);
  }
}
