// Live check against the real relay with made-up credentials: the relay must run the whole handshake
// and then reject the login. Runs natively and in a browser (`dart test -p chrome test/live`).
@Tags(['live'])
library;

import 'package:openrscp/openrscp.dart';
import 'package:test/test.dart';

void main() {
  test('relay handshake runs and rejects unknown credentials', () async {
    final log = <String>[];
    final t = PortalTransport(
      username: 'openrscp-handshake-test@example.invalid',
      password: 'invalid',
      serial: 'S10-000000000000',
      log: log.add,
    );
    addTearDown(() => printOnFailure(log.join('\n')));
    await expectLater(t.connect(), throwsA(isA<RscpAuthException>()));
    await t.close();
    expect(
      log.any((l) => l.startsWith('connection registered')),
      isTrue,
      reason: log.join('\n'),
    );
  });
}
