import 'message.dart';
import 'tags.g.dart';
import 'transport.dart';

/// Live power values (W), as the EMS reports them.
/// Sign convention: grid > 0 = purchase, < 0 = feed-in; battery > 0 = charging, < 0 = discharging.
class LiveSnapshot {
  final int solarW,
      batteryW,
      houseW,
      gridW,
      additionalW,
      wallboxW,
      wallboxSolarW;
  final int soc;
  final double autarkyPct, selfConsumptionPct;
  final DateTime receivedAt;
  const LiveSnapshot({
    required this.solarW,
    required this.batteryW,
    required this.houseW,
    required this.gridW,
    required this.additionalW,
    required this.wallboxW,
    required this.wallboxSolarW,
    required this.soc,
    required this.autarkyPct,
    required this.selfConsumptionPct,
    required this.receivedAt,
  });

  Map<String, Object> toJson() => {
    'solarW': solarW,
    'batteryW': batteryW,
    'houseW': houseW,
    'gridW': gridW,
    'additionalW': additionalW,
    'wallboxW': wallboxW,
    'wallboxSolarW': wallboxSolarW,
    'soc': soc,
    'autarkyPct': autarkyPct,
    'selfConsumptionPct': selfConsumptionPct,
    'receivedAt': receivedAt.toIso8601String(),
  };
}

class SystemInfo {
  final String serial, swRelease, productionDate, macAddress;
  final int installedPeakPowerW;
  final double derateAtPercent;
  final int derateAtPowerW;
  const SystemInfo({
    required this.serial,
    required this.swRelease,
    required this.productionDate,
    required this.macAddress,
    required this.installedPeakPowerW,
    required this.derateAtPercent,
    required this.derateAtPowerW,
  });
  Map<String, Object> toJson() => {
    'serial': serial,
    'swRelease': swRelease,
    'productionDate': productionDate,
    'macAddress': macAddress,
    'installedPeakPowerW': installedPeakPowerW,
    'derateAtPercent': derateAtPercent,
    'derateAtPowerW': derateAtPowerW,
  };
}

class PowerSettings {
  final bool powerLimitsUsed, powerSaveEnabled, weatherRegulatedChargeEnabled;
  final int maxChargePowerW, maxDischargePowerW, dischargeStartPowerW;
  const PowerSettings({
    required this.powerLimitsUsed,
    required this.powerSaveEnabled,
    required this.weatherRegulatedChargeEnabled,
    required this.maxChargePowerW,
    required this.maxDischargePowerW,
    required this.dischargeStartPowerW,
  });
  Map<String, Object> toJson() => {
    'powerLimitsUsed': powerLimitsUsed,
    'powerSaveEnabled': powerSaveEnabled,
    'weatherRegulatedChargeEnabled': weatherRegulatedChargeEnabled,
    'maxChargePowerW': maxChargePowerW,
    'maxDischargePowerW': maxDischargePowerW,
    'dischargeStartPowerW': dischargeStartPowerW,
  };
}

/// Summed energy values (Wh) for a period from the unit's database.
///
/// Mapping (verified against autarky on a real S10E): DB_GRID_POWER_OUT is energy drawn from the grid
/// (purchase), DB_GRID_POWER_IN is energy sent into the grid (feed-in). The names are from the grid's view.
class DbSummary {
  final DateTime start;
  final Duration span;
  final double solarWh,
      houseWh,
      gridPurchaseWh,
      gridFeedInWh,
      batteryInWh,
      batteryOutWh,
      autarkyPct,
      consumedProductionPct,
      socPct;
  const DbSummary({
    required this.start,
    required this.span,
    required this.solarWh,
    required this.houseWh,
    required this.gridPurchaseWh,
    required this.gridFeedInWh,
    required this.batteryInWh,
    required this.batteryOutWh,
    required this.autarkyPct,
    required this.consumedProductionPct,
    required this.socPct,
  });
  Map<String, Object> toJson() => {
    'start': start.toIso8601String(),
    'spanSeconds': span.inSeconds,
    'solarWh': solarWh,
    'houseWh': houseWh,
    'gridPurchaseWh': gridPurchaseWh,
    'gridFeedInWh': gridFeedInWh,
    'batteryInWh': batteryInWh,
    'batteryOutWh': batteryOutWh,
    'autarkyPct': autarkyPct,
    'consumedProductionPct': consumedProductionPct,
    'socPct': socPct,
  };
}

/// One interval of a database time series, as the unit returns it in DB_VALUE_CONTAINER.
///
/// The values are passed on unconverted. Whether they are energy per interval (Wh) or average
/// power (W) is not documented; compare their sum with [DbHistory.sum] to find out
/// (example/db_history.dart does that).
class DbBucket {
  /// DB_GRAPH_INDEX as reported; the position of the bucket within the requested span.
  final double index;
  final double solar,
      house,
      gridPurchase,
      gridFeedIn,
      batteryIn,
      batteryOut,
      autarkyPct,
      consumedProductionPct,
      socPct;
  const DbBucket({
    required this.index,
    required this.solar,
    required this.house,
    required this.gridPurchase,
    required this.gridFeedIn,
    required this.batteryIn,
    required this.batteryOut,
    required this.autarkyPct,
    required this.consumedProductionPct,
    required this.socPct,
  });

  Map<String, Object> toJson() => {
    'index': index,
    'solar': solar,
    'house': house,
    'gridPurchase': gridPurchase,
    'gridFeedIn': gridFeedIn,
    'batteryIn': batteryIn,
    'batteryOut': batteryOut,
    'autarkyPct': autarkyPct,
    'consumedProductionPct': consumedProductionPct,
    'socPct': socPct,
  };
}

/// A database query split into intervals: the total for the whole span plus one bucket each.
class DbHistory {
  final DateTime start;
  final Duration interval, span;
  final DbSummary sum;
  final List<DbBucket> buckets;
  const DbHistory({
    required this.start,
    required this.interval,
    required this.span,
    required this.sum,
    required this.buckets,
  });
}

/// Per-field answers of a setter: 0 accepted, 1 accepted but adjusted, −1 rejected.
class SetResult {
  final Map<String, int> codes;
  const SetResult(this.codes);
  bool get ok => !codes.values.contains(-1);
  bool get adjusted => codes.values.contains(1);
  @override
  String toString() => 'SetResult($codes)';
}

enum IdleType { charge, discharge }

/// One charge or discharge lock period. [day] 0..6 as the unit counts it (0 = Monday in the
/// E3/DC portal; check against the unit's display before relying on it).
class IdlePeriod {
  final IdleType type;
  final int day, startHour, startMinute, endHour, endMinute;
  final bool active;
  const IdlePeriod({
    required this.type,
    required this.day,
    required this.active,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  bool get isValid =>
      day >= 0 &&
      day <= 6 &&
      startHour >= 0 &&
      startHour < 24 &&
      endHour >= 0 &&
      endHour < 24 &&
      startMinute >= 0 &&
      startMinute < 60 &&
      endMinute >= 0 &&
      endMinute < 60 &&
      startHour * 60 + startMinute < endHour * 60 + endMinute;

  IdlePeriod copyWith({
    bool? active,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
  }) => IdlePeriod(
    type: type,
    day: day,
    active: active ?? this.active,
    startHour: startHour ?? this.startHour,
    startMinute: startMinute ?? this.startMinute,
    endHour: endHour ?? this.endHour,
    endMinute: endMinute ?? this.endMinute,
  );

  @override
  bool operator ==(Object other) =>
      other is IdlePeriod &&
      other.type == type &&
      other.day == day &&
      other.active == active &&
      other.startHour == startHour &&
      other.startMinute == startMinute &&
      other.endHour == endHour &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(
    type,
    day,
    active,
    startHour,
    startMinute,
    endHour,
    endMinute,
  );

  @override
  String toString() =>
      '${type.name} day $day ${active ? 'on' : 'off'} '
      '$startHour:${startMinute.toString().padLeft(2, '0')}-'
      '$endHour:${endMinute.toString().padLeft(2, '0')}';
}

/// Presence and state of one wallbox slot.
///
/// A slot counts as present when the system reports the device as connected or returns an
/// app software version. Systems without a wallbox answer with an error or empty values.
class WallboxInfo {
  final int index;
  final bool present;
  final bool? connected, working, inService;
  final int? appSoftware;
  const WallboxInfo({
    required this.index,
    required this.present,
    this.connected,
    this.working,
    this.inService,
    this.appSoftware,
  });
  Map<String, Object?> toJson() => {
    'index': index,
    'present': present,
    'connected': connected,
    'working': working,
    'inService': inService,
    'appSoftware': appSoftware,
  };
}

/// One DC input of a PV inverter. RSCP calls it a "string"; electrically it is an MPP tracker
/// that may carry several parallel strings, which the unit only measures together.
class PvTracker {
  /// Inverter (PVI) index; 0 on most systems, higher on systems with several inverters.
  final int pviIndex;

  /// Input index within the inverter.
  final int index;
  final double? powerW, voltageV, currentA, energyAllWh;

  /// Value the unit reports as PVI_DC_MAX_POWER for this input. Its meaning differs by device
  /// and is not documented: an S10E reported 6000 W per input while its inverter handles
  /// 12 kW DC in total and one input carries 7.1 kWp without clipping. Do not treat it as a
  /// hard limit or as the installed module power; the app asks the user for kWp instead.
  final double? reportedMaxPowerW;

  /// True when the input shows signs of a connected PV field: lifetime energy, power or
  /// a voltage of at least 20 V. PVI_USED_STRING_COUNT is not reliable for this (a real
  /// system with two active trackers reported 1).
  final bool active;
  const PvTracker({
    required this.pviIndex,
    required this.index,
    required this.active,
    this.powerW,
    this.voltageV,
    this.currentA,
    this.reportedMaxPowerW,
    this.energyAllWh,
  });
  Map<String, Object?> toJson() => {
    'pviIndex': pviIndex,
    'index': index,
    'active': active,
    'powerW': powerW,
    'voltageV': voltageV,
    'currentA': currentA,
    'reportedMaxPowerW': reportedMaxPowerW,
    'energyAllWh': energyAllWh,
  };
}

/// High-level requests on top of any [RscpTransport].
class E3dcClient {
  final RscpTransport transport;
  E3dcClient(this.transport);

  Map<int, RscpMessage> _byTag(List<RscpMessage> ms) => {
    for (final m in ms) m.tag: m,
  };

  static void _check(RscpMessage? m, RscpTag t) {
    if (m == null) {
      throw RscpTransportException('missing ${t.name} in response');
    }
    if (m.isError) throw RscpTransportException('${t.name}: ${m.value}');
  }

  /// One batched request for everything the dashboard needs every second.
  Future<LiveSnapshot> live() async {
    const tags = [
      RscpTag.EMS_REQ_POWER_PV,
      RscpTag.EMS_REQ_POWER_BAT,
      RscpTag.EMS_REQ_POWER_HOME,
      RscpTag.EMS_REQ_POWER_GRID,
      RscpTag.EMS_REQ_POWER_ADD,
      RscpTag.EMS_REQ_POWER_WB_ALL,
      RscpTag.EMS_REQ_POWER_WB_SOLAR,
      RscpTag.EMS_REQ_BAT_SOC,
      RscpTag.EMS_REQ_AUTARKY,
      RscpTag.EMS_REQ_SELF_CONSUMPTION,
    ];
    final r = _byTag(
      await transport.send([for (final t in tags) RscpMessage.none(t)]),
    );
    int i(RscpTag t) => r[t.value]?.asInt ?? 0;
    double d(RscpTag t) => r[t.value]?.asDouble ?? 0;
    _check(r[RscpTag.EMS_POWER_PV.value], RscpTag.EMS_POWER_PV);
    return LiveSnapshot(
      solarW: i(RscpTag.EMS_POWER_PV),
      batteryW: i(RscpTag.EMS_POWER_BAT),
      houseW: i(RscpTag.EMS_POWER_HOME),
      gridW: i(RscpTag.EMS_POWER_GRID),
      additionalW: i(RscpTag.EMS_POWER_ADD),
      wallboxW: i(RscpTag.EMS_POWER_WB_ALL),
      wallboxSolarW: i(RscpTag.EMS_POWER_WB_SOLAR),
      soc: i(RscpTag.EMS_BAT_SOC),
      autarkyPct: d(RscpTag.EMS_AUTARKY),
      selfConsumptionPct: d(RscpTag.EMS_SELF_CONSUMPTION),
      receivedAt: DateTime.now(),
    );
  }

  Future<SystemInfo> systemInfo() async {
    final r = _byTag(
      await transport.send([
        RscpMessage.none(RscpTag.INFO_REQ_SERIAL_NUMBER),
        RscpMessage.none(RscpTag.INFO_REQ_SW_RELEASE),
        RscpMessage.none(RscpTag.INFO_REQ_PRODUCTION_DATE),
        RscpMessage.none(RscpTag.INFO_REQ_MAC_ADDRESS),
        RscpMessage.none(RscpTag.EMS_REQ_INSTALLED_PEAK_POWER),
        RscpMessage.none(RscpTag.EMS_REQ_DERATE_AT_PERCENT_VALUE),
        RscpMessage.none(RscpTag.EMS_REQ_DERATE_AT_POWER_VALUE),
      ]),
    );
    _check(r[RscpTag.INFO_SERIAL_NUMBER.value], RscpTag.INFO_SERIAL_NUMBER);
    String s(RscpTag t) => (r[t.value]?.value ?? '').toString();
    return SystemInfo(
      serial: s(RscpTag.INFO_SERIAL_NUMBER),
      swRelease: s(RscpTag.INFO_SW_RELEASE),
      productionDate: s(RscpTag.INFO_PRODUCTION_DATE),
      macAddress: s(RscpTag.INFO_MAC_ADDRESS),
      installedPeakPowerW:
          r[RscpTag.EMS_INSTALLED_PEAK_POWER.value]?.asInt ?? 0,
      derateAtPercent:
          (r[RscpTag.EMS_DERATE_AT_PERCENT_VALUE.value]?.asDouble ?? 0) * 100,
      derateAtPowerW: r[RscpTag.EMS_DERATE_AT_POWER_VALUE.value]?.asInt ?? 0,
    );
  }

  Future<PowerSettings> powerSettings() async {
    final m = await transport.sendOne(
      RscpMessage.none(RscpTag.EMS_REQ_GET_POWER_SETTINGS),
    );
    _check(m, RscpTag.EMS_GET_POWER_SETTINGS);
    return PowerSettings(
      // The unit reports some flags as bool and others as uchar8 (0/1).
      powerLimitsUsed: _flag(m, RscpTag.EMS_POWER_LIMITS_USED),
      powerSaveEnabled: _flag(m, RscpTag.EMS_POWERSAVE_ENABLED),
      weatherRegulatedChargeEnabled: _flag(
        m,
        RscpTag.EMS_WEATHER_REGULATED_CHARGE_ENABLED,
      ),
      maxChargePowerW: m.find(RscpTag.EMS_MAX_CHARGE_POWER)?.asInt ?? 0,
      maxDischargePowerW: m.find(RscpTag.EMS_MAX_DISCHARGE_POWER)?.asInt ?? 0,
      dischargeStartPowerW:
          m.find(RscpTag.EMS_DISCHARGE_START_POWER)?.asInt ?? 0,
    );
  }

  static bool _flag(RscpMessage m, RscpTag t) => (m.find(t)?.asInt ?? 0) != 0;

  /// Changes power settings; only the given values are sent. Types follow python-e3dc, which has
  /// used these requests for years: the limit switch as bool, powers as uint32, power save and
  /// weather-regulated charging as uchar8. Read the settings back afterwards to confirm.
  Future<SetResult> setPowerSettings({
    bool? limitsUsed,
    int? maxChargePowerW,
    int? maxDischargePowerW,
    int? dischargeStartPowerW,
    bool? powerSave,
    bool? weatherRegulatedCharge,
  }) async {
    final items = [
      if (limitsUsed != null)
        RscpMessage.bool(RscpTag.EMS_POWER_LIMITS_USED, limitsUsed),
      if (maxDischargePowerW != null)
        RscpMessage.uint32(RscpTag.EMS_MAX_DISCHARGE_POWER, maxDischargePowerW),
      if (maxChargePowerW != null)
        RscpMessage.uint32(RscpTag.EMS_MAX_CHARGE_POWER, maxChargePowerW),
      if (dischargeStartPowerW != null)
        RscpMessage.uint32(
          RscpTag.EMS_DISCHARGE_START_POWER,
          dischargeStartPowerW,
        ),
      if (powerSave != null)
        RscpMessage.uchar8(RscpTag.EMS_POWERSAVE_ENABLED, powerSave ? 1 : 0),
      if (weatherRegulatedCharge != null)
        RscpMessage.uchar8(
          RscpTag.EMS_WEATHER_REGULATED_CHARGE_ENABLED,
          weatherRegulatedCharge ? 1 : 0,
        ),
    ];
    if (items.isEmpty) return const SetResult({});
    final m = await transport.sendOne(
      RscpMessage.container(RscpTag.EMS_REQ_SET_POWER_SETTINGS, items),
    );
    _check(m, RscpTag.EMS_SET_POWER_SETTINGS);
    return SetResult({
      for (final c in m.children) c.tagName: c.isError ? -1 : (c.asInt ?? -1),
    });
  }

  /// Limits and defaults of the unit (EMS_REQ_GET_SYS_SPECS), e.g. maxBatChargePower,
  /// maxBatDischargPower (sic, as the unit spells it), startDischargeDefault, maxAcPower.
  Future<Map<String, int>> sysSpecs() async {
    final m = await transport.sendOne(
      RscpMessage.none(RscpTag.EMS_REQ_GET_SYS_SPECS),
    );
    _check(m, RscpTag.EMS_GET_SYS_SPECS);
    return {
      for (final c in m.children)
        if (c.tag == RscpTag.EMS_SYS_SPEC.value &&
            c.valueOf<String>(RscpTag.EMS_SYS_SPEC_NAME) != null &&
            c.find(RscpTag.EMS_SYS_SPEC_VALUE_INT)?.asInt != null)
          c.valueOf<String>(RscpTag.EMS_SYS_SPEC_NAME)!: c
              .find(RscpTag.EMS_SYS_SPEC_VALUE_INT)!
              .asInt!,
    };
  }

  /// Charge and discharge lock periods ("Sperrzeiten"), one per type and weekday.
  Future<List<IdlePeriod>> idlePeriods() async {
    final m = await transport.sendOne(
      RscpMessage.none(RscpTag.EMS_REQ_GET_IDLE_PERIODS),
    );
    _check(m, RscpTag.EMS_GET_IDLE_PERIODS);
    int i(RscpMessage? c, RscpTag t) => c?.find(t)?.asInt ?? 0;
    return [
      for (final p in m.children)
        if (p.tag == RscpTag.EMS_IDLE_PERIOD.value)
          IdlePeriod(
            type: i(p, RscpTag.EMS_IDLE_PERIOD_TYPE) == 0
                ? IdleType.charge
                : IdleType.discharge,
            day: i(p, RscpTag.EMS_IDLE_PERIOD_DAY),
            active: _flag(p, RscpTag.EMS_IDLE_PERIOD_ACTIVE),
            startHour: i(
              p.find(RscpTag.EMS_IDLE_PERIOD_START),
              RscpTag.EMS_IDLE_PERIOD_HOUR,
            ),
            startMinute: i(
              p.find(RscpTag.EMS_IDLE_PERIOD_START),
              RscpTag.EMS_IDLE_PERIOD_MINUTE,
            ),
            endHour: i(
              p.find(RscpTag.EMS_IDLE_PERIOD_END),
              RscpTag.EMS_IDLE_PERIOD_HOUR,
            ),
            endMinute: i(
              p.find(RscpTag.EMS_IDLE_PERIOD_END),
              RscpTag.EMS_IDLE_PERIOD_MINUTE,
            ),
          ),
    ];
  }

  /// Writes lock periods. As in python-e3dc, each period must end after it starts on the same day.
  /// Returns true when the unit confirms; read back with [idlePeriods] to check.
  Future<bool> setIdlePeriods(List<IdlePeriod> periods) async {
    for (final p in periods) {
      if (!p.isValid) throw ArgumentError('invalid idle period: $p');
    }
    RscpMessage time(RscpTag t, int h, int min) => RscpMessage.container(t, [
      RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_HOUR, h),
      RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_MINUTE, min),
    ]);
    final m = await transport.sendOne(
      RscpMessage.container(RscpTag.EMS_REQ_SET_IDLE_PERIODS, [
        for (final p in periods)
          RscpMessage.container(RscpTag.EMS_IDLE_PERIOD, [
            RscpMessage.uchar8(
              RscpTag.EMS_IDLE_PERIOD_TYPE,
              p.type == IdleType.charge ? 0 : 1,
            ),
            RscpMessage.uchar8(RscpTag.EMS_IDLE_PERIOD_DAY, p.day),
            RscpMessage.bool(RscpTag.EMS_IDLE_PERIOD_ACTIVE, p.active),
            time(RscpTag.EMS_IDLE_PERIOD_START, p.startHour, p.startMinute),
            time(RscpTag.EMS_IDLE_PERIOD_END, p.endHour, p.endMinute),
          ]),
      ]),
    );
    if (m.tag != RscpTag.EMS_SET_IDLE_PERIODS.value || m.isError) return false;
    return (m.asInt ?? 0) == 1;
  }

  /// Postcode, city and country of the installation address, for weather and forecasts.
  /// Name, street, phone and e-mail are deliberately not read.
  Future<({String postcode, String city, String country})>
  facilityLocation() async {
    final m = await transport.sendOne(
      RscpMessage.none(RscpTag.INFO_REQ_GET_FACILITY),
    );
    _check(m, RscpTag.INFO_GET_FACILITY);
    String s(RscpTag t) => (m.valueOf<String>(t) ?? '').trim();
    return (
      postcode: s(RscpTag.INFO_POSTCODE),
      city: s(RscpTag.INFO_CITY),
      country: s(RscpTag.INFO_COUNTRY),
    );
  }

  /// [t] as local wall-clock time, encoded like seconds since the UTC epoch, as the database
  /// expects its start time.
  static int wallClockSeconds(DateTime t) {
    final l = t.toLocal();
    return DateTime.utc(
          l.year,
          l.month,
          l.day,
          l.hour,
          l.minute,
          l.second,
        ).millisecondsSinceEpoch ~/
        1000;
  }

  /// Summed values for [span] starting at [start] (local time). Use 1 day, 1 month or 1 year.
  Future<DbSummary> dbSummary(DateTime start, Duration span) async =>
      (await dbHistory(start, span, span)).sum;

  /// Database values from [start] over [span], split into buckets of [interval]
  /// (e.g. 15 minutes for a day, one day for a month). One request, however many buckets.
  /// Bucket values are average power (W) over the interval; the sum container is in Wh.
  ///
  /// The unit reads the start as wall-clock time in its own time zone, written like a UTC epoch
  /// (verified on an S10E, firmware S10_2026_027: with the true epoch every bucket was one hour
  /// late in CET). So [start] is taken as local wall-clock time here; app and unit are expected
  /// to share the time zone.
  Future<DbHistory> dbHistory(
    DateTime start,
    Duration interval,
    Duration span,
  ) async {
    final startS = wallClockSeconds(start);
    final m = await transport.sendOne(
      RscpMessage.container(RscpTag.DB_REQ_HISTORY_DATA_DAY, [
        RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_START, startS),
        RscpMessage.uint64(
          RscpTag.DB_REQ_HISTORY_TIME_INTERVAL,
          interval.inSeconds,
        ),
        RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_SPAN, span.inSeconds),
      ]),
    );
    _check(m, RscpTag.DB_HISTORY_DATA_DAY);
    final sumC =
        m.find(RscpTag.DB_SUM_CONTAINER) ??
        (m.children.isNotEmpty ? m.children.first : m);
    double d(RscpMessage c, RscpTag t) => c.find(t)?.asDouble ?? 0;
    final sum = DbSummary(
      start: start,
      span: span,
      solarWh: d(sumC, RscpTag.DB_DC_POWER),
      houseWh: d(sumC, RscpTag.DB_CONSUMPTION),
      gridPurchaseWh: d(sumC, RscpTag.DB_GRID_POWER_OUT),
      gridFeedInWh: d(sumC, RscpTag.DB_GRID_POWER_IN),
      batteryInWh: d(sumC, RscpTag.DB_BAT_POWER_IN),
      batteryOutWh: d(sumC, RscpTag.DB_BAT_POWER_OUT),
      autarkyPct: d(sumC, RscpTag.DB_AUTARKY),
      consumedProductionPct: d(sumC, RscpTag.DB_CONSUMED_PRODUCTION),
      socPct: d(sumC, RscpTag.DB_BAT_CHARGE_LEVEL),
    );
    final buckets = [
      for (final c in m.children)
        if (c.tag == RscpTag.DB_VALUE_CONTAINER.value)
          DbBucket(
            index: d(c, RscpTag.DB_GRAPH_INDEX),
            solar: d(c, RscpTag.DB_DC_POWER),
            house: d(c, RscpTag.DB_CONSUMPTION),
            gridPurchase: d(c, RscpTag.DB_GRID_POWER_OUT),
            gridFeedIn: d(c, RscpTag.DB_GRID_POWER_IN),
            batteryIn: d(c, RscpTag.DB_BAT_POWER_IN),
            batteryOut: d(c, RscpTag.DB_BAT_POWER_OUT),
            autarkyPct: d(c, RscpTag.DB_AUTARKY),
            consumedProductionPct: d(c, RscpTag.DB_CONSUMED_PRODUCTION),
            socPct: d(c, RscpTag.DB_BAT_CHARGE_LEVEL),
          ),
    ];
    return DbHistory(
      start: start,
      interval: interval,
      span: span,
      sum: sum,
      buckets: buckets,
    );
  }

  /// Queries wallbox slot [index] (0-based).
  Future<WallboxInfo> wallbox([int index = 0]) async {
    final m = await transport.sendOne(
      RscpMessage.container(RscpTag.WB_REQ_DATA, [
        RscpMessage.uchar8(RscpTag.WB_INDEX, index),
        RscpMessage.none(RscpTag.WB_REQ_DEVICE_STATE),
        RscpMessage.none(RscpTag.WB_REQ_APP_SOFTWARE),
      ]),
    );
    if (m.isError || !m.isContainer) {
      return WallboxInfo(index: index, present: false);
    }
    final ds = m.find(RscpTag.WB_DEVICE_STATE);
    bool? flag(RscpTag t) =>
        (ds != null && ds.isContainer) ? ds.valueOf<bool>(t) : null;
    final connected = flag(RscpTag.WB_DEVICE_CONNECTED);
    final sw = m.find(RscpTag.WB_APP_SOFTWARE);
    final appSoftware = (sw != null && !sw.isError) ? sw.asInt : null;
    return WallboxInfo(
      index: index,
      present: connected == true || (appSoftware != null && appSoftware != 0),
      connected: connected,
      working: flag(RscpTag.WB_DEVICE_WORKING),
      inService: flag(RscpTag.WB_DEVICE_IN_SERVICE),
      appSoftware: appSoftware,
    );
  }

  /// Probes slots 0.. until the first absent one (max [maxCount], S10 supports up to 8).
  /// Returns only present wallboxes; an empty list means "hide the wallbox everywhere".
  Future<List<WallboxInfo>> detectWallboxes({int maxCount = 8}) async {
    final found = <WallboxInfo>[];
    for (var i = 0; i < maxCount; i++) {
      final w = await wallbox(i);
      if (!w.present) break;
      found.add(w);
    }
    return found;
  }

  /// Reads the DC inputs of all PV inverters (index 0 up to [maxInverters] - 1, stopping at the
  /// first one that does not answer) and marks which inputs are in use. Nothing about the
  /// device is assumed: tracker count, inverter count and limits all come from the unit.
  Future<List<PvTracker>> pvTrackers({int maxInverters = 4}) async {
    final out = <PvTracker>[];
    for (var p = 0; p < maxInverters; p++) {
      final list = await _pvTrackersOf(p);
      if (list == null) break;
      out.addAll(list);
    }
    return out;
  }

  Future<List<PvTracker>?> _pvTrackersOf(int pviIndex) async {
    final base = await transport.sendOne(
      RscpMessage.container(RscpTag.PVI_REQ_DATA, [
        RscpMessage.uint16(RscpTag.PVI_INDEX, pviIndex),
        RscpMessage.none(RscpTag.PVI_REQ_DC_MAX_STRING_COUNT),
        RscpMessage.none(RscpTag.PVI_REQ_USED_STRING_COUNT),
      ]),
    );
    if (base.isError || !base.isContainer) return null;
    int countOf(RscpTag t) {
      final m = base.find(t);
      return (m == null || m.isError) ? 0 : (m.asInt ?? 0);
    }

    final maxN = countOf(RscpTag.PVI_DC_MAX_STRING_COUNT);
    final usedN = countOf(RscpTag.PVI_USED_STRING_COUNT);
    final n = maxN > usedN ? maxN : usedN;
    if (n == 0) return null;
    final out = <PvTracker>[];
    for (var i = 0; i < n; i++) {
      final r = await transport.sendOne(
        RscpMessage.container(RscpTag.PVI_REQ_DATA, [
          RscpMessage.uint16(RscpTag.PVI_INDEX, pviIndex),
          RscpMessage.uint16(RscpTag.PVI_REQ_DC_POWER, i),
          RscpMessage.uint16(RscpTag.PVI_REQ_DC_VOLTAGE, i),
          RscpMessage.uint16(RscpTag.PVI_REQ_DC_CURRENT, i),
          RscpMessage.uint16(RscpTag.PVI_REQ_DC_MAX_POWER, i),
          RscpMessage.uint16(RscpTag.PVI_REQ_DC_STRING_ENERGY_ALL, i),
        ]),
      );
      double? v(RscpTag t) {
        final c = r.isContainer ? r.find(t) : null;
        if (c == null || c.isError) return null;
        return c.isContainer ? c.find(RscpTag.PVI_VALUE)?.asDouble : c.asDouble;
      }

      final p = v(RscpTag.PVI_DC_POWER), u = v(RscpTag.PVI_DC_VOLTAGE);
      final e = v(RscpTag.PVI_DC_STRING_ENERGY_ALL);
      out.add(
        PvTracker(
          pviIndex: pviIndex,
          index: i,
          powerW: p,
          voltageV: u,
          currentA: v(RscpTag.PVI_DC_CURRENT),
          reportedMaxPowerW: v(RscpTag.PVI_DC_MAX_POWER),
          energyAllWh: e,
          active: (e ?? 0) > 0 || (p ?? 0) > 0 || (u ?? 0) >= 20,
        ),
      );
    }
    return out;
  }
}
