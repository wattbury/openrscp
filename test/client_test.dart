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
  if ((r.valueOf<int>(RscpTag.PVI_INDEX) ?? 0) != 0) {
    return [
      RscpMessage(
        RscpTag.PVI_DATA.value,
        RscpType.error,
        RscpErrorCode.RSCP_ERR_NOT_AVAILABLE,
      ),
    ];
  }
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
        expect(
          t[1].reportedMaxPowerW,
          6000,
          reason: 'reported as is, not interpreted',
        );
        expect(
          t.every((x) => x.pviIndex == 0),
          isTrue,
          reason: 'probing stops at the first inverter that does not answer',
        );
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

  test(
    'dbHistory returns the sum and one bucket per value container',
    () async {
      RscpMessage values(double idx, double pv, double home) =>
          RscpMessage.container(RscpTag.DB_VALUE_CONTAINER, [
            RscpMessage.float32(RscpTag.DB_GRAPH_INDEX, idx),
            RscpMessage.float32(RscpTag.DB_DC_POWER, pv),
            RscpMessage.float32(RscpTag.DB_CONSUMPTION, home),
          ]);
      final t = FakeTransport(
        (_) => [
          RscpMessage.container(RscpTag.DB_HISTORY_DATA_DAY, [
            RscpMessage.container(RscpTag.DB_SUM_CONTAINER, [
              RscpMessage.float32(RscpTag.DB_DC_POWER, 300),
              RscpMessage.float32(RscpTag.DB_CONSUMPTION, 120),
            ]),
            values(0, 100, 40),
            values(1, 200, 80),
          ]),
        ],
      );
      final start = DateTime(2026, 10, 24);
      final h = await E3dcClient(t)
          .dbHistory(start, const Duration(hours: 1), const Duration(hours: 2));
      final req = t.sent.single.single;
      // Local midnight goes out as wall-clock time, whatever the machine's time zone.
      expect(
        req.valueOf<int>(RscpTag.DB_REQ_HISTORY_TIME_START),
        DateTime.utc(2026, 10, 24).millisecondsSinceEpoch ~/ 1000,
      );
      expect(req.valueOf<int>(RscpTag.DB_REQ_HISTORY_TIME_INTERVAL), 3600);
      expect(req.valueOf<int>(RscpTag.DB_REQ_HISTORY_TIME_SPAN), 7200);
      expect(h.sum.solarWh, 300);
      expect(h.buckets.map((b) => b.solar), [100, 200]);
      expect(h.buckets.last.index, 1);
      expect(h.buckets.first.house, 40);
    },
  );

  test('power settings: uchar8 flags count as true', () async {
    final t = FakeTransport(
      (_) => [
        RscpMessage.container(RscpTag.EMS_GET_POWER_SETTINGS, [
          RscpMessage.bool(RscpTag.EMS_POWER_LIMITS_USED, true),
          RscpMessage.uchar8(RscpTag.EMS_POWERSAVE_ENABLED, 1),
          RscpMessage.uchar8(RscpTag.EMS_WEATHER_REGULATED_CHARGE_ENABLED, 0),
          RscpMessage.uint32(RscpTag.EMS_MAX_CHARGE_POWER, 4500),
        ]),
      ],
    );
    final p = await E3dcClient(t).powerSettings();
    expect(p.powerLimitsUsed, isTrue);
    expect(p.powerSaveEnabled, isTrue);
    expect(p.weatherRegulatedChargeEnabled, isFalse);
    expect(p.maxChargePowerW, 4500);
  });

  test(
    'setPowerSettings sends only given values with python-e3dc types',
    () async {
      final t = FakeTransport(
        (_) => [
          RscpMessage.container(RscpTag.EMS_SET_POWER_SETTINGS, [
            RscpMessage.char8(RscpTag.EMS_RES_MAX_CHARGE_POWER, 0),
            RscpMessage.char8(RscpTag.EMS_RES_POWERSAVE_ENABLED, 1),
          ]),
        ],
      );
      final r = await E3dcClient(t)
          .setPowerSettings(maxChargePowerW: 3000, powerSave: true);
      final sent = t.sent.single.single;
      expect(sent.children.map((c) => c.tagName), [
        'EMS_MAX_CHARGE_POWER',
        'EMS_POWERSAVE_ENABLED',
      ]);
      expect(sent.children.first.type, RscpType.uint32);
      expect(sent.children.last.type, RscpType.uchar8);
      expect(r.ok, isTrue);
      expect(r.adjusted, isTrue);
    },
  );

  test('idle periods: read and write', () async {
    RscpMessage at(RscpTag t, int h, int m) => RscpMessage.container(t, [
      RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_HOUR, h),
      RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_MINUTE, m),
    ]);
    final t = FakeTransport((req) {
      if (req.single.tagEnum == RscpTag.EMS_REQ_SET_IDLE_PERIODS) {
        return [RscpMessage.bool(RscpTag.EMS_SET_IDLE_PERIODS, true)];
      }
      return [
        RscpMessage.container(RscpTag.EMS_GET_IDLE_PERIODS, [
          RscpMessage.container(RscpTag.EMS_IDLE_PERIOD, [
            RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_TYPE, 1),
            RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_DAY, 2),
            RscpMessage.bool(RscpTag.EMS_IDLE_PERIOD_ACTIVE, true),
            at(RscpTag.EMS_IDLE_PERIOD_START, 0, 0),
            at(RscpTag.EMS_IDLE_PERIOD_END, 6, 30),
          ]),
        ]),
      ];
    });
    final c = E3dcClient(t);
    final p = (await c.idlePeriods()).single;
    expect(p.type, IdleType.discharge);
    expect(p.day, 2);
    expect(p.active, isTrue);
    expect([p.endHour, p.endMinute], [6, 30]);
    expect(await c.setIdlePeriods([p.copyWith(active: false)]), isTrue);
    final sent = t.sent.last.single;
    expect(
      sent.children.single.find(RscpTag.EMS_IDLE_PERIOD_ACTIVE)!.value,
      false,
    );
    expect(
      () => c.setIdlePeriods([p.copyWith(startHour: 7)]),
      throwsArgumentError,
    );
  });

  test('facilityLocation reads only postcode, city and country', () async {
    final t = FakeTransport(
      (_) => [
        RscpMessage.container(RscpTag.INFO_GET_FACILITY, [
          RscpMessage.cstring(RscpTag.INFO_NAME, 'Name'),
          RscpMessage.cstring(RscpTag.INFO_POSTCODE, '12345 '),
          RscpMessage.cstring(RscpTag.INFO_CITY, 'Beispielstadt'),
          RscpMessage.cstring(RscpTag.INFO_COUNTRY, 'DE'),
        ]),
      ],
    );
    final f = await E3dcClient(t).facilityLocation();
    expect(f.postcode, '12345');
    expect(f.city, 'Beispielstadt');
    expect(f.country, 'DE');
  });
}
