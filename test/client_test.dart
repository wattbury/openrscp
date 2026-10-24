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
  pvTrackerTests();
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

RscpMessage _pviValue(RscpTag t, int index, double v) =>
    RscpMessage.container(t, [
      RscpMessage.uint16(RscpTag.PVI_INDEX, index),
      RscpMessage.float32(RscpTag.PVI_VALUE, v),
    ]);

/// PVI responses as a real S10E sent them on 2026-10-25 (night): used count 1, but both inputs carry a field.
List<RscpMessage> _pviHandler(
  List<RscpMessage> req, {
  required Map<int, List<double>> inputs,
  int used = 1,
  int max = 2,
}) {
  final r = req.single;
  final dcPower = r.find(RscpTag.PVI_REQ_DC_POWER);
  if (dcPower == null) {
    return [
      RscpMessage.container(RscpTag.PVI_DATA, [
        RscpMessage.uint16(RscpTag.PVI_INDEX, 0),
        RscpMessage.uchar8(RscpTag.PVI_DC_MAX_STRING_COUNT, max),
        RscpMessage.uchar8(RscpTag.PVI_USED_STRING_COUNT, used),
      ]),
    ];
  }
  final i = dcPower.value as int;
  final x = inputs[i]!; // power, voltage, current, maxPower, energyWh
  return [
    RscpMessage.container(RscpTag.PVI_DATA, [
      RscpMessage.uint16(RscpTag.PVI_INDEX, 0),
      _pviValue(RscpTag.PVI_DC_POWER, i, x[0]),
      _pviValue(RscpTag.PVI_DC_VOLTAGE, i, x[1]),
      _pviValue(RscpTag.PVI_DC_CURRENT, i, x[2]),
      _pviValue(RscpTag.PVI_DC_MAX_POWER, i, x[3]),
      _pviValue(RscpTag.PVI_DC_STRING_ENERGY_ALL, i, x[4]),
    ]),
  ];
}

void pvTrackerTests() {
  group('pvTrackers', () {
    test(
      'both inputs active although the unit reports one used string',
      () async {
        final c = E3dcClient(
          FakeTransport(
            (req) => _pviHandler(
              req,
              inputs: {
                0: [0, 39, 0, 6000, 30881600],
                1: [0, 93, 0, 6000, 1120600],
              },
            ),
          ),
        );
        final t = await c.pvTrackers();
        expect(t.length, 2);
        expect(t.every((x) => x.active), isTrue);
        expect(t[1].voltageV, closeTo(93, 0.01));
        expect(t[1].energyAllWh, closeTo(1120600, 1));
      },
    );

    test('an unused input without voltage and energy is inactive', () async {
      final c = E3dcClient(
        FakeTransport(
          (req) => _pviHandler(
            req,
            used: 1,
            max: 2,
            inputs: {
              0: [3420, 412, 8.3, 6000, 1000000],
              1: [0, 0, 0, 6000, 0],
            },
          ),
        ),
      );
      final t = await c.pvTrackers();
      expect(t[0].active, isTrue);
      expect(t[1].active, isFalse);
    });
  });
}
