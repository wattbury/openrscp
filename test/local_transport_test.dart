import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openrscp/openrscp.dart';
import 'package:test/test.dart';

/// Minimal fake S10: decrypts frames, answers authentication and a power request.
class FakeUnit {
  final String rscpPassword, user, password;
  late final ServerSocket server;
  final received = <RscpMessage>[];
  FakeUnit(this.rscpPassword, this.user, this.password);

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) {
      final cipher = RscpCipher(utf8.encode(rscpPassword));
      var buf = Uint8List(0);
      client.listen((data) {
        buf = Uint8List.fromList(buf + cipher.decrypt(data));
        while (buf.length >= 18) {
          final RscpFrame f;
          try {
            f = RscpCodec.decodeFrame(buf);
          } on RscpFormatException {
            return;
          }
          buf = buf.sublist((f.length + 31) ~/ 32 * 32);
          final answers = <RscpMessage>[];
          for (final m in f.messages) {
            received.add(m);
            if (m.tagEnum == RscpTag.RSCP_REQ_AUTHENTICATION) {
              final ok =
                  m.find(RscpTag.RSCP_AUTHENTICATION_USER)?.value == user &&
                  m.find(RscpTag.RSCP_AUTHENTICATION_PASSWORD)?.value ==
                      password;
              answers.add(
                RscpMessage.uchar8(RscpTag.RSCP_AUTHENTICATION, ok ? 10 : 0),
              );
            } else if (m.tagEnum == RscpTag.EMS_REQ_POWER_PV) {
              answers.add(RscpMessage.int32(RscpTag.EMS_POWER_PV, 3420));
            }
          }
          final out = cipher.encrypt(RscpCodec.frameMessages(answers));
          // Deliver in two chunks to exercise reassembly.
          client.add(out.sublist(0, 7));
          client.add(out.sublist(7));
        }
      });
    });
  }

  int get port => server.port;
  Future<void> stop() => server.close();
}

void main() {
  late FakeUnit unit;
  setUp(() async {
    unit = FakeUnit('geheim', 'name@beispiel.de', 'portalpass');
    await unit.start();
  });
  tearDown(() => unit.stop());

  test('authenticates and answers requests', () async {
    final t = LocalTransport(
      host: '127.0.0.1',
      port: unit.port,
      username: 'name@beispiel.de',
      password: 'portalpass',
      rscpPassword: 'geheim',
    );
    await t.connect();
    expect(t.authLevel, RscpAuthLevel.user);
    for (var i = 0; i < 3; i++) {
      final m = await t.sendOne(RscpMessage.none(RscpTag.EMS_REQ_POWER_PV));
      expect(m.asInt, 3420);
    }
    await t.close();
  });

  test('wrong portal password is an auth error', () async {
    final t = LocalTransport(
      host: '127.0.0.1',
      port: unit.port,
      username: 'name@beispiel.de',
      password: 'falsch',
      rscpPassword: 'geheim',
    );
    await expectLater(t.connect(), throwsA(isA<RscpAuthException>()));
  });

  test('wrong RSCP password times out as auth error', () async {
    final t = LocalTransport(
      host: '127.0.0.1',
      port: unit.port,
      username: 'name@beispiel.de',
      password: 'portalpass',
      rscpPassword: 'anders',
      timeout: const Duration(milliseconds: 500),
    );
    await expectLater(t.connect(), throwsA(isA<RscpAuthException>()));
  });
}
