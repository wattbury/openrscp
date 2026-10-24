import 'package:openrscp/openrscp.dart';
import 'package:test/test.dart';

/// Answers each request with a canned response chosen by the request.
class FakeTransport extends RscpTransport {
  final List<RscpMessage> Function(List<RscpMessage>) handler;
  final List<List<RscpMessage>> sent = [];
  FakeTransport(this.handler);
  @override
  bool get isConnected => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {}
  @override
  Future<List<RscpMessage>> send(List<RscpMessage> requests) async {
    sent.add(requests);
    return handler(requests);
  }
}

int _wbIndex(List<RscpMessage> req) =>
    req.single.valueOf<int>(RscpTag.WB_INDEX)!;

RscpMessage _wbData(int index, {bool? connected, int? sw}) =>
    RscpMessage.container(RscpTag.WB_DATA, [
      RscpMessage.uchar8(RscpTag.WB_INDEX, index),
      if (connected != null)
        RscpMessage.container(RscpTag.WB_DEVICE_STATE, [
          RscpMessage.bool(RscpTag.WB_DEVICE_CONNECTED, connected),
          RscpMessage.bool(RscpTag.WB_DEVICE_WORKING, connected),
          RscpMessage.bool(RscpTag.WB_DEVICE_IN_SERVICE, false),
        ])
      else
        RscpMessage(
          RscpTag.WB_DEVICE_STATE.value,
          RscpType.error,
          RscpErrorCode.RSCP_ERR_NOT_AVAILABLE,
        ),
      if (sw != null)
        RscpMessage.uint32(RscpTag.WB_APP_SOFTWARE, sw)
      else
        RscpMessage(
          RscpTag.WB_APP_SOFTWARE.value,
          RscpType.error,
          RscpErrorCode.RSCP_ERR_NOT_AVAILABLE,
        ),
    ]);

void main() {
  test('no wallbox: errors in the WB_DATA container mean absent', () async {
    final c = E3dcClient(FakeTransport((req) => [_wbData(_wbIndex(req))]));
    final w = await c.wallbox(0);
    expect(w.present, isFalse);
    expect(w.connected, isNull);
    expect(await c.detectWallboxes(), isEmpty);
  });

  test('no wallbox: top-level error means absent', () async {
    final c = E3dcClient(
      FakeTransport(
        (req) => [
          RscpMessage(
            RscpTag.WB_DATA.value,
            RscpType.error,
            RscpErrorCode.RSCP_ERR_NOT_AVAILABLE,
          ),
        ],
      ),
    );
    expect((await c.wallbox(0)).present, isFalse);
  });

  test(
    'one connected wallbox at index 0, probing stops at the first gap',
    () async {
      final t = FakeTransport((req) {
        final i = _wbIndex(req);
        return [i == 0 ? _wbData(0, connected: true, sw: 2051) : _wbData(i)];
      });
      final found = await E3dcClient(t).detectWallboxes();
      expect(found.single.index, 0);
      expect(found.single.connected, isTrue);
      expect(found.single.appSoftware, 2051);
      expect(
        t.sent.length,
        2,
        reason: 'slot 0 present, slot 1 absent, then stop',
      );
    },
  );

  test('app software alone counts as present', () async {
    final c = E3dcClient(FakeTransport((req) => [_wbData(0, sw: 17)]));
    expect((await c.wallbox(0)).present, isTrue);
  });
}
