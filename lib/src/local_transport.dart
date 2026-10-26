import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'codec.dart';
import 'message.dart';
import 'rijndael.dart';
import 'tags.g.dart';
import 'transport.dart';

/// Direct RSCP over TCP in the local network (port 5033 by default).
///
/// Every frame is encrypted with Rijndael-256-CBC ([RscpCipher]); the key is the RSCP password set on
/// the unit. After connecting, the client authenticates with the portal user and the portal password
/// in plain text (inside the encrypted channel). A wrong RSCP password shows up as the unit closing
/// the connection or as undecodable frames, a wrong portal login as auth level 0.
class LocalTransport extends RscpTransport {
  static const int defaultPort = 5033;

  final String host;
  final int port;
  final String username, password;
  final List<int> _rscpPassword;
  final Duration timeout;
  final void Function(String)? log;

  Socket? _socket;
  RscpCipher? _cipher;
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _plain = BytesBuilder();
  final Queue<_Pending> _queue = Queue();
  _Pending? _inFlight;
  RscpAuthLevel _authLevel = RscpAuthLevel.none;

  LocalTransport({
    required this.host,
    required this.username,
    required this.password,
    required String rscpPassword,
    this.port = defaultPort,
    this.timeout = const Duration(seconds: 5),
    this.log,
  }) : _rscpPassword = utf8.encode(rscpPassword) {
    if (_rscpPassword.length > 32) {
      throw ArgumentError('RSCP password must be at most 32 bytes');
    }
  }

  RscpAuthLevel get authLevel => _authLevel;

  @override
  bool get isConnected => _socket != null && _authLevel != RscpAuthLevel.none;

  void _log(String s) => log?.call(s);

  @override
  Future<void> connect() async {
    await close();
    _log('connecting to $host:$port');
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _cipher = RscpCipher(_rscpPassword);
    _sub = socket.listen(_onData, onError: _onError, onDone: _onDone);
    final List<RscpMessage> r;
    try {
      r = await _request([
        RscpMessage.container(RscpTag.RSCP_REQ_AUTHENTICATION, [
          RscpMessage.cstring(RscpTag.RSCP_AUTHENTICATION_USER, username),
          RscpMessage.cstring(RscpTag.RSCP_AUTHENTICATION_PASSWORD, password),
        ]),
      ]);
    } on RscpTransportException catch (e) {
      await close();
      // The unit drops the connection when the frame cannot be decrypted.
      throw RscpAuthException(
        'no answer to authentication (RSCP password wrong?): ${e.message}',
      );
    }
    final a = r.isEmpty ? null : r.first;
    final level = (a == null || a.isError) ? 0 : (a.asInt ?? 0);
    if (level == 0) {
      await close();
      throw RscpAuthException(
        'login rejected (portal user or password wrong?)',
      );
    }
    _authLevel = RscpAuthLevel.fromValue(level);
    _log('authenticated, level ${_authLevel.name}');
  }

  @override
  Future<void> close() async {
    _failAll(RscpTransportException('connection closed'));
    _authLevel = RscpAuthLevel.none;
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    _cipher = null;
    _plain.clear();
  }

  @override
  Future<List<RscpMessage>> send(List<RscpMessage> requests) {
    if (!isConnected) {
      return Future.error(RscpTransportException('not connected'));
    }
    return _request(requests);
  }

  Future<List<RscpMessage>> _request(List<RscpMessage> requests) {
    final p = _Pending(requests);
    _queue.add(p);
    _pump();
    return p.completer.future.timeout(
      timeout,
      onTimeout: () {
        // After a lost answer the CBC chain is out of step; only a reconnect helps.
        close();
        throw RscpTransportException(
          'request timed out after ${timeout.inSeconds}s',
        );
      },
    );
  }

  void _pump() {
    if (_inFlight != null || _queue.isEmpty || _socket == null) return;
    final p = _queue.removeFirst();
    _inFlight = p;
    _socket!.add(_cipher!.encrypt(RscpCodec.frameMessages(p.requests)));
  }

  void _onData(Uint8List data) {
    final cipher = _cipher;
    if (cipher == null) return;
    _plain.add(cipher.decrypt(data));
    var buf = _plain.takeBytes();
    var offset = 0;
    while (buf.length - offset >= 18) {
      final RscpFrame f;
      try {
        f = RscpCodec.decodeFrame(buf, offset);
      } on RscpFormatException catch (e) {
        if (e.message.contains('truncated')) break;
        _log('bad frame: ${e.message}');
        close();
        return;
      }
      // Each answer was encrypted on its own, so the next one starts at a block boundary.
      const bs = Rijndael256.blockSize;
      offset += (f.length + bs - 1) ~/ bs * bs;
      _deliver(f.messages);
    }
    if (offset < buf.length) _plain.add(Uint8List.sublistView(buf, offset));
  }

  void _deliver(List<RscpMessage> responses) {
    final p = _inFlight;
    if (p == null) {
      _log(
        'unsolicited response: ${responses.map((m) => m.tagName).join(', ')}',
      );
      return;
    }
    _inFlight = null;
    if (!p.completer.isCompleted) p.completer.complete(responses);
    _pump();
  }

  void _onError(Object e) {
    _log('socket error: $e');
    _failAll(RscpTransportException('socket error: $e'));
  }

  void _onDone() {
    _log('socket closed by peer');
    _failAll(RscpTransportException('connection closed by the unit'));
    _socket?.destroy();
    _socket = null;
    _authLevel = RscpAuthLevel.none;
  }

  void _failAll(RscpTransportException e) {
    final all = [?_inFlight, ..._queue];
    _inFlight = null;
    _queue.clear();
    for (final p in all) {
      if (!p.completer.isCompleted) p.completer.completeError(e);
    }
  }
}

class _Pending {
  final List<RscpMessage> requests;
  final Completer<List<RscpMessage>> completer = Completer();
  _Pending(this.requests);
}
