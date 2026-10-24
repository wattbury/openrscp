import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'codec.dart';
import 'message.dart';
import 'tags.g.dart';
import 'transport.dart';

/// RSCP over the E3/DC portal relay (`wss://s10.e3dc.com/ws`).
///
/// The relay forwards RSCP frames to the owner's unit. Authentication uses the portal login
/// (password as MD5 hex) and the unit's serial number; the RSCP password is not involved.
/// Protocol as reverse-engineered by python-e3dc; undocumented and subject to change by E3/DC.
///
/// Handshake:
///   server  RSCP_REQ_SET_PROTOCOL_VERSION      -> client echoes RSCP_SET_PROTOCOL_VERSION
///   server  SERVER_REGISTER_CONNECTION          -> client SERVER_CONNECTION_REGISTERED (conId, authLevel)
///   server  SERVER_REQ_RSCP_CMD { INFO_REQ_* }  -> client answers with pseudo device info
///   server  SERVER_REQ_RSCP_CMD { INFO_SERIAL_NUMBER } -> client SERVER_REQ_NEW_VIRTUAL_CONNECTION (user, md5, serial)
///   server  SERVER_REGISTER_CONNECTION          -> virtConId (-1 = login rejected), virtAuthLevel
/// Afterwards each request is wrapped in SERVER_REQ_RSCP_CMD with the virtual connection id.
class PortalTransport extends RscpTransport {
  static final Uri defaultEndpoint = Uri.parse('wss://s10.e3dc.com/ws');

  final String username;
  final String passwordMd5;
  final String serialWithPrefix;
  final Uri endpoint;
  final Duration timeout;
  final void Function(String)? log;

  WebSocket? _ws;
  void Function(Uint8List)? _sink;
  bool _virtRequested = false;
  StreamSubscription? _sub;
  int _conId = 0;
  int _authLevel = 0;
  int? _virtConId;
  int _virtAuthLevel = 0;
  Completer<void>? _connected;
  final Queue<_Pending> _queue = Queue();
  _Pending? _inFlight;

  PortalTransport({
    required this.username,
    required String password,
    required String serial,
    bool passwordIsMd5 = false,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 10),
    this.log,
  }) : passwordMd5 = passwordIsMd5
           ? password
           : md5.convert(utf8.encode(password)).toString(),
       serialWithPrefix = serial.toUpperCase().startsWith('S10-')
           ? serial
           : 'S10-$serial',
       endpoint = endpoint ?? defaultEndpoint;

  /// Auth level of the virtual connection (10 = user).
  RscpAuthLevel get authLevel => RscpAuthLevel.fromValue(_virtAuthLevel);

  @override
  bool get isConnected => _virtConId != null && _sink != null;

  @override
  Future<void> connect() async {
    await close();
    _connected = Completer<void>();
    _log('connecting to $endpoint');
    final ws = await WebSocket.connect(endpoint.toString()).timeout(timeout);
    _ws = ws;
    _sink = ws.add;
    _sub = _ws!.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    await _connected!.future.timeout(
      timeout,
      onTimeout: () {
        throw RscpTransportException(
          'portal handshake timed out after ${timeout.inSeconds}s',
        );
      },
    );
  }

  @override
  Future<void> close() async {
    _failAll(RscpTransportException('connection closed'));
    await _sub?.cancel();
    _sub = null;
    await _ws?.close();
    _ws = null;
    _sink = null;
    _virtRequested = false;
    _conId = 0;
    _authLevel = 0;
    _virtConId = null;
    _virtAuthLevel = 0;
  }

  @override
  Future<List<RscpMessage>> send(List<RscpMessage> requests) {
    if (!isConnected) {
      return Future.error(RscpTransportException('not connected'));
    }
    final p = _Pending(requests);
    _queue.add(p);
    _pump();
    return p.completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_inFlight, p)) _inFlight = null;
        _pump();
        throw RscpTransportException(
          'request timed out after ${timeout.inSeconds}s',
        );
      },
    );
  }

  // ---------- internals ----------

  void _pump() {
    if (_inFlight != null || _queue.isEmpty || !isConnected) return;
    final p = _queue.removeFirst();
    _inFlight = p;
    final inner = RscpCodec.frameMessages(p.requests);
    _sendCmd(inner, _virtConId!, _virtAuthLevel);
  }

  void _sendCmd(Uint8List innerFrame, int conId, int authLevel) {
    final outer = RscpMessage.container(RscpTag.SERVER_REQ_RSCP_CMD, [
      RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, conId),
      RscpMessage.uchar8(RscpTag.SERVER_AUTH_LEVEL, authLevel),
      RscpMessage.int32(RscpTag.SERVER_RSCP_DATA_LEN, innerFrame.length),
      RscpMessage.bytes(RscpTag.SERVER_RSCP_DATA, innerFrame),
    ]);
    _sendFrame(outer);
  }

  void _sendFrame(RscpMessage m) =>
      _sink?.call(RscpCodec.frame(RscpCodec.encode(m)));

  /// Test hook: route outgoing frames to [sink] instead of a websocket and start the handshake state machine.
  @visibleForTesting
  void attachForTesting(void Function(Uint8List) sink) {
    _sink = sink;
    _connected = Completer<void>();
  }

  /// Test hook: completes when the virtual connection is registered (after [attachForTesting]).
  @visibleForTesting
  Future<void> get handshakeDone => _connected?.future ?? Future.value();

  /// Test hook: feed one incoming websocket message.
  @visibleForTesting
  void handleIncoming(Uint8List bytes) => _onData(bytes);

  void _onData(dynamic data) {
    if (data is! List<int> || data.isEmpty) return;
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final RscpMessage msg;
    try {
      msg = RscpCodec.decodeOne(bytes).$1;
    } catch (e) {
      _log('undecodable message: $e');
      return;
    }
    final tag = msg.tagEnum;
    switch (tag) {
      case RscpTag.RSCP_REQ_SET_PROTOCOL_VERSION:
        _log('protocol version ${msg.value}, acknowledging');
        _sendFrame(
          RscpMessage(
            RscpTag.RSCP_SET_PROTOCOL_VERSION.value,
            msg.type,
            msg.value,
          ),
        );
      case RscpTag.SERVER_REQ_PING:
        _sendFrame(RscpMessage.none(RscpTag.SERVER_PING));
      case RscpTag.SERVER_REGISTER_CONNECTION:
        _onRegister(msg);
      case RscpTag.SERVER_UNREGISTER_CONNECTION:
        _log('server unregistered connection');
      case RscpTag.SERVER_REQ_RSCP_CMD:
        _onCmd(msg);
      default:
        _log('unhandled ${msg.tagName}');
    }
  }

  void _onRegister(RscpMessage msg) {
    final id = msg.valueOf<int>(RscpTag.SERVER_CONNECTION_ID) ?? 0;
    final level = msg.valueOf<int>(RscpTag.SERVER_AUTH_LEVEL) ?? 0;
    if (_conId == 0) {
      _conId = id;
      _authLevel = level;
      _log('connection registered: conId=$id authLevel=$level');
    } else if (id == -1) {
      final status = msg.valueOf<int>(RscpTag.SERVER_STATUS);
      _log('virtual connection rejected (status $status)');
      _connected?.completeError(
        RscpAuthException(
          'portal rejected credentials or serial (status $status)',
        ),
      );
      _connected = null;
    } else {
      _virtConId = id;
      _virtAuthLevel = level;
      _log('virtual connection registered: virtConId=$id authLevel=$level');
      if (_connected != null && !_connected!.isCompleted) {
        _connected!.complete();
      }
      _pump();
    }
    _sendFrame(
      RscpMessage.container(RscpTag.SERVER_CONNECTION_REGISTERED, [
        RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, id),
        RscpMessage.uchar8(RscpTag.SERVER_AUTH_LEVEL, level),
      ]),
    );
  }

  void _onCmd(RscpMessage msg) {
    final raw = msg.valueOf<Uint8List>(RscpTag.SERVER_RSCP_DATA);
    if (raw == null) return;
    final List<RscpMessage> inner;
    try {
      inner = RscpCodec.decodeFrame(raw).messages;
    } catch (e) {
      _log('bad inner frame: $e');
      return;
    }
    // Messages on the base connection belong to the handshake (the portal asks for device info and
    // assigns a pseudo serial). Messages on the virtual connection are answers to our requests, even
    // when they carry the same tags, e.g. INFO_SERIAL_NUMBER as answer to INFO_REQ_SERIAL_NUMBER.
    final outerId = msg.valueOf<int>(RscpTag.SERVER_CONNECTION_ID);
    final handshake =
        _virtConId == null ||
        (outerId != null && outerId == _conId && outerId != _virtConId);
    final replies = <RscpMessage>[];
    final responses = <RscpMessage>[];
    for (final m in inner) {
      if (!handshake) {
        responses.add(m);
        continue;
      }
      final r = _infoReply(m);
      if (r != null) {
        replies.add(r);
      } else if (m.tagEnum == RscpTag.INFO_SERIAL_NUMBER) {
        if (_virtRequested) continue;
        _virtRequested = true;
        _log(
          'portal assigned serial ${m.value}; requesting virtual connection for $serialWithPrefix',
        );
        _requestVirtualConnection();
      } else {
        _log('ignored handshake message ${m.tagName}');
      }
    }
    if (replies.isNotEmpty) {
      _sendCmd(RscpCodec.frameMessages(replies), _conId, _authLevel);
    }
    if (responses.isNotEmpty) {
      final p = _inFlight;
      if (p != null) {
        _inFlight = null;
        p.completer.complete(responses);
        _pump();
      } else {
        _log(
          'unsolicited response: ${responses.map((m) => m.tagName).join(', ')}',
        );
      }
    }
  }

  RscpMessage? _infoReply(RscpMessage m) {
    final now = DateTime.now();
    switch (m.tagEnum) {
      case RscpTag.INFO_REQ_IP_ADDRESS:
        return RscpMessage.cstring(RscpTag.INFO_IP_ADDRESS, '0.0.0.0');
      case RscpTag.INFO_REQ_SUBNET_MASK:
        return RscpMessage.cstring(RscpTag.INFO_SUBNET_MASK, '0.0.0.0');
      case RscpTag.INFO_REQ_GATEWAY:
        return RscpMessage.cstring(RscpTag.INFO_GATEWAY, '0.0.0.0');
      case RscpTag.INFO_REQ_DNS:
        return RscpMessage.cstring(RscpTag.INFO_DNS, '0.0.0.0');
      case RscpTag.INFO_REQ_DHCP_STATUS:
        return RscpMessage.bool(RscpTag.INFO_DHCP_STATUS, false);
      case RscpTag.INFO_REQ_TIME:
        return RscpMessage.bytes(RscpTag.INFO_TIME, _webTimestamp(now));
      case RscpTag.INFO_REQ_UTC_TIME:
        return RscpMessage.bytes(
          RscpTag.INFO_UTC_TIME,
          _webTimestamp(now.toUtc()),
        );
      case RscpTag.INFO_REQ_TIME_ZONE:
        final h = now.timeZoneOffset.inHours;
        return RscpMessage.cstring(
          RscpTag.INFO_TIME_ZONE,
          'GMT${h >= 0 ? '+' : '-'}${h.abs()}',
        );
      case RscpTag.INFO_REQ_A35_SERIAL_NUMBER:
        return RscpMessage.cstring(RscpTag.INFO_A35_SERIAL_NUMBER, '123456');
      case RscpTag.INFO_REQ_INFO:
        final pseudo =
            'WEB_${md5.convert(utf8.encode('$username$_conId')).toString()}';
        return RscpMessage.container(RscpTag.INFO_INFO, [
          RscpMessage.cstring(RscpTag.INFO_SERIAL_NUMBER, pseudo),
          RscpMessage.cstring(RscpTag.INFO_PRODUCTION_DATE, '570412800000'),
          RscpMessage.cstring(RscpTag.INFO_MAC_ADDRESS, '00:00:00:00:00:00'),
        ]);
      default:
        return null;
    }
  }

  /// The relay's own 12-byte time format: double seconds + uint32 milliseconds (as python-e3dc sends it).
  static Uint8List _webTimestamp(DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    final out = Uint8List(12);
    final bd = out.buffer.asByteData();
    bd.setFloat64(0, (ms ~/ 1000).toDouble(), Endian.little);
    bd.setUint32(8, ms % 1000, Endian.little);
    return out;
  }

  void _requestVirtualConnection() {
    _sendFrame(
      RscpMessage.container(RscpTag.SERVER_REQ_NEW_VIRTUAL_CONNECTION, [
        RscpMessage.cstring(RscpTag.SERVER_USER, username),
        RscpMessage.cstring(RscpTag.SERVER_PASSWD, passwordMd5),
        RscpMessage.cstring(RscpTag.SERVER_IDENTIFIER, serialWithPrefix),
        RscpMessage.int32(RscpTag.SERVER_TYPE, 4),
        RscpMessage.int32(RscpTag.SERVER_HASH_CODE, 1234567890),
      ]),
    );
  }

  void _onError(Object e) {
    _log('websocket error: $e');
    _failAll(RscpTransportException('websocket error: $e'));
  }

  void _onDone() {
    _log('websocket closed');
    _virtConId = null;
    _failAll(RscpTransportException('connection closed by server'));
  }

  void _failAll(Object error) {
    final c = _connected;
    if (c != null && !c.isCompleted) c.completeError(error);
    _connected = null;
    final f = _inFlight;
    _inFlight = null;
    if (f != null && !f.completer.isCompleted) f.completer.completeError(error);
    while (_queue.isNotEmpty) {
      final p = _queue.removeFirst();
      if (!p.completer.isCompleted) p.completer.completeError(error);
    }
  }

  void _log(String s) => log?.call(s);
}

class _Pending {
  final List<RscpMessage> requests;
  final Completer<List<RscpMessage>> completer = Completer();
  _Pending(this.requests);
}
