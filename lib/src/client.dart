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
      powerLimitsUsed: m.valueOf<bool>(RscpTag.EMS_POWER_LIMITS_USED) ?? false,
      powerSaveEnabled: m.valueOf<bool>(RscpTag.EMS_POWERSAVE_ENABLED) ?? false,
      weatherRegulatedChargeEnabled:
          m.valueOf<bool>(RscpTag.EMS_WEATHER_REGULATED_CHARGE_ENABLED) ??
          false,
      maxChargePowerW: m.find(RscpTag.EMS_MAX_CHARGE_POWER)?.asInt ?? 0,
      maxDischargePowerW: m.find(RscpTag.EMS_MAX_DISCHARGE_POWER)?.asInt ?? 0,
      dischargeStartPowerW:
          m.find(RscpTag.EMS_DISCHARGE_START_POWER)?.asInt ?? 0,
    );
  }

  /// Summed values for [span] starting at [start] (local time). Use 1 day, 1 month or 1 year.
  Future<DbSummary> dbSummary(DateTime start, Duration span) async {
    final startS = start.toUtc().millisecondsSinceEpoch ~/ 1000;
    final m = await transport.sendOne(
      RscpMessage.container(RscpTag.DB_REQ_HISTORY_DATA_DAY, [
        RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_START, startS),
        RscpMessage.uint64(
          RscpTag.DB_REQ_HISTORY_TIME_INTERVAL,
          span.inSeconds,
        ),
        RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_SPAN, span.inSeconds),
      ]),
    );
    _check(m, RscpTag.DB_HISTORY_DATA_DAY);
    final sum =
        m.find(RscpTag.DB_SUM_CONTAINER) ??
        (m.children.isNotEmpty ? m.children.first : m);
    double d(RscpTag t) => sum.find(t)?.asDouble ?? 0;
    return DbSummary(
      start: start,
      span: span,
      solarWh: d(RscpTag.DB_DC_POWER),
      houseWh: d(RscpTag.DB_CONSUMPTION),
      gridPurchaseWh: d(RscpTag.DB_GRID_POWER_OUT),
      gridFeedInWh: d(RscpTag.DB_GRID_POWER_IN),
      batteryInWh: d(RscpTag.DB_BAT_POWER_IN),
      batteryOutWh: d(RscpTag.DB_BAT_POWER_OUT),
      autarkyPct: d(RscpTag.DB_AUTARKY),
      consumedProductionPct: d(RscpTag.DB_CONSUMED_PRODUCTION),
      socPct: d(RscpTag.DB_BAT_CHARGE_LEVEL),
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
}
