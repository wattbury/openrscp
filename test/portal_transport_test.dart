import 'dart:typed_data';

import 'package:openrscp/openrscp.dart';
import 'package:test/test.dart';

/// Builds what the relay sends: a frame around one outer TLV.
Uint8List _server(RscpMessage m) => RscpCodec.frame(RscpCodec.encode(m));

/// SERVER_REQ_RSCP_CMD on [conId] carrying [inner] as RSCP frame.
Uint8List _cmd(int conId, List<RscpMessage> inner) {
  final f = RscpCodec.frameMessages(inner);
  return _server(
    RscpMessage.container(RscpTag.SERVER_REQ_RSCP_CMD, [
      RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, conId),
      RscpMessage.int32(RscpTag.SERVER_RSCP_DATA_LEN, f.length),
      RscpMessage.bytes(RscpTag.SERVER_RSCP_DATA, f),
    ]),
  );
}

Uint8List _register(int id, int level) => _server(
  RscpMessage.container(RscpTag.SERVER_REGISTER_CONNECTION, [
    RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, id),
    RscpMessage.uchar8(RscpTag.SERVER_AUTH_LEVEL, level),
  ]),
);

/// Decodes what the client sent: outer tag, and for RSCP_CMD the connection id and inner tags.
({RscpTag? tag, int? conId, List<RscpTag?> inner}) _decodeSent(
  Uint8List frame,
) {
  final outer = RscpCodec.decodeFrame(frame).messages.single;
  final raw = outer.valueOf<Uint8List>(RscpTag.SERVER_RSCP_DATA);
  return (
    tag: outer.tagEnum,
    conId: outer.valueOf<int>(RscpTag.SERVER_CONNECTION_ID),
    inner: raw == null
        ? const []
        : RscpCodec.decodeFrame(raw).messages.map((m) => m.tagEnum).toList(),
  );
}

void main() {
  late PortalTransport t;
  late List<Uint8List> sent;

  Future<void> handshake() async {
    t.handleIncoming(
      _server(RscpMessage.uchar8(RscpTag.RSCP_REQ_SET_PROTOCOL_VERSION, 2)),
    );
    t.handleIncoming(_register(100, 60));
    t.handleIncoming(
      _cmd(100, [
        RscpMessage.none(RscpTag.INFO_REQ_IP_ADDRESS),
        RscpMessage.none(RscpTag.INFO_REQ_INFO),
      ]),
    );
    t.handleIncoming(
      _cmd(100, [RscpMessage.cstring(RscpTag.INFO_SERIAL_NUMBER, 'WEB_abc')]),
    );
    t.handleIncoming(_register(200, 10));
    await t.handshakeDone;
  }

  setUp(() {
    sent = [];
    t = PortalTransport(
      username: 'u@example.org',
      password: 'secret',
      serial: '722229021808',
    )..attachForTesting(sent.add);
  });

  test('handshake: echoes protocol version, answers INFO, requests virtual connection once', () async {
    await handshake();
    final s = sent.map(_decodeSent).toList();
    expect(s[0].tag, RscpTag.RSCP_SET_PROTOCOL_VERSION);
    expect(s[1].tag, RscpTag.SERVER_CONNECTION_REGISTERED);
    expect(s[2].tag, RscpTag.SERVER_REQ_RSCP_CMD);
    expect(s[2].conId, 100);
    expect(s[2].inner, [RscpTag.INFO_IP_ADDRESS, RscpTag.INFO_INFO]);
    expect(s[3].tag, RscpTag.SERVER_REQ_NEW_VIRTUAL_CONNECTION);
    expect(s[4].tag, RscpTag.SERVER_CONNECTION_REGISTERED);
    expect(t.isConnected, isTrue);
    expect(t.authLevel, RscpAuthLevel.user);

    final vc = RscpCodec.decodeFrame(sent[3]).messages.single;
    expect(vc.valueOf<String>(RscpTag.SERVER_IDENTIFIER), 'S10-722229021808');
    expect(
      vc.valueOf<String>(RscpTag.SERVER_PASSWD),
      '5ebe2294ecd0e0f08eab7690d2a6ee69',
    ); // md5("secret")
  });

  test('INFO_SERIAL_NUMBER on the virtual connection is a response, not a new handshake (regression)', () async {
    await handshake();
    sent.clear();
    final f = t.send([
      RscpMessage.none(RscpTag.INFO_REQ_SERIAL_NUMBER),
      RscpMessage.none(RscpTag.INFO_REQ_SW_RELEASE),
    ]);
    expect(_decodeSent(sent.single).conId, 200);
    t.handleIncoming(
      _cmd(200, [
        RscpMessage.cstring(RscpTag.INFO_SERIAL_NUMBER, 'S10-722229021808'),
        RscpMessage.cstring(RscpTag.INFO_SW_RELEASE, 'S10_2026_027'),
      ]),
    );
    final r = await f;
    expect(r.map((m) => m.tagEnum), [
      RscpTag.INFO_SERIAL_NUMBER,
      RscpTag.INFO_SW_RELEASE,
    ]);
    expect(sent.length, 1, reason: 'no second virtual connection request');
  });

  test('requests are serialized: second waits for the first answer', () async {
    await handshake();
    sent.clear();
    final a = t.sendOne(RscpMessage.none(RscpTag.EMS_REQ_POWER_PV));
    final b = t.sendOne(RscpMessage.none(RscpTag.EMS_REQ_BAT_SOC));
    expect(sent.length, 1);
    t.handleIncoming(
      _cmd(200, [RscpMessage.int32(RscpTag.EMS_POWER_PV, 3420)]),
    );
    expect((await a).value, 3420);
    expect(sent.length, 2);
    t.handleIncoming(_cmd(200, [RscpMessage.uchar8(RscpTag.EMS_BAT_SOC, 68)]));
    expect((await b).value, 68);
  });

  test('rejected login fails the handshake with RscpAuthException', () async {
    t.handleIncoming(_register(100, 60));
    t.handleIncoming(
      _cmd(100, [RscpMessage.cstring(RscpTag.INFO_SERIAL_NUMBER, 'WEB_abc')]),
    );
    final done = t.handshakeDone;
    t.handleIncoming(
      _server(
        RscpMessage.container(RscpTag.SERVER_REGISTER_CONNECTION, [
          RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, -1),
          RscpMessage.uchar8(RscpTag.SERVER_AUTH_LEVEL, 0),
          RscpMessage.uchar8(RscpTag.SERVER_STATUS, 16),
        ]),
      ),
    );
    await expectLater(done, throwsA(isA<RscpAuthException>()));
    expect(t.isConnected, isFalse);
  });

  test('ping is answered', () {
    t.handleIncoming(_server(RscpMessage.none(RscpTag.SERVER_REQ_PING)));
    expect(_decodeSent(sent.single).tag, RscpTag.SERVER_PING);
  });
}
