// Reads everything the unit knows about its own configuration: system specs, PV strings,
// battery overview and the facility address (only postcode, city and country are printed).
// Usage: E3DC_USER=... E3DC_PASS=... E3DC_SN=S10-... dart run example/system_probe.dart
import 'dart:io';

import 'package:openrscp/openrscp.dart';

Future<void> main() async {
  final env = Platform.environment;
  final user = env['E3DC_USER'], pass = env['E3DC_PASS'], sn = env['E3DC_SN'];
  if (user == null || pass == null || sn == null) {
    stderr.writeln('Set E3DC_USER, E3DC_PASS and E3DC_SN.');
    exit(2);
  }
  final t = PortalTransport(username: user, password: pass, serial: sn);
  await t.connect();
  print('verbunden, Berechtigung ${t.authLevel.name}\n');

  Future<RscpMessage> ask(RscpMessage m) async {
    try {
      return await t.sendOne(m);
    } catch (e) {
      return RscpMessage(m.tag, RscpType.error, RscpErrorCode.UNKNOWN);
    }
  }

  String show(RscpMessage? m) {
    if (m == null) return '— (keine Antwort)';
    if (m.isError) return '— (${m.value})';
    final v = m.value;
    if (v is double) return v.toStringAsFixed(2);
    return '$v';
  }

  // ---------- EMS ----------
  print('== EMS');
  final peak = await ask(
    RscpMessage.none(RscpTag.EMS_REQ_INSTALLED_PEAK_POWER),
  );
  print('installierte Spitzenleistung: ${show(peak)} W');
  final specs = await ask(RscpMessage.none(RscpTag.EMS_REQ_GET_SYS_SPECS));
  if (specs.isContainer) {
    for (final s in specs.children.where(
      (c) => c.tagEnum == RscpTag.EMS_SYS_SPEC,
    )) {
      final name = s.valueOf<String>(RscpTag.EMS_SYS_SPEC_NAME) ?? '?';
      final value =
          s.find(RscpTag.EMS_SYS_SPEC_VALUE_INT)?.value ??
          s.find(RscpTag.EMS_SYS_SPEC_VALUE_STRING)?.value;
      print('  spec $name = $value');
    }
  } else {
    print('  Systemspezifikation: ${show(specs)}');
  }

  // ---------- PV-Wechselrichter ----------
  print('\n== PV-Wechselrichter (Index 0)');
  final pvi = await ask(
    RscpMessage.container(RscpTag.PVI_REQ_DATA, [
      RscpMessage.uint16(RscpTag.PVI_INDEX, 0),
      RscpMessage.none(RscpTag.PVI_REQ_USED_STRING_COUNT),
      RscpMessage.none(RscpTag.PVI_REQ_DC_MAX_STRING_COUNT),
      RscpMessage.none(RscpTag.PVI_REQ_AC_MAX_PHASE_COUNT),
      RscpMessage.none(RscpTag.PVI_REQ_AC_MAX_APPARENTPOWER),
      RscpMessage.none(RscpTag.PVI_REQ_TYPE),
    ]),
  );
  RscpMessage? pviChild(RscpMessage m, RscpTag t) =>
      m.isContainer ? m.find(t) : null;
  double? valueIn(RscpMessage? c) => (c != null && c.isContainer)
      ? c.find(RscpTag.PVI_VALUE)?.asDouble
      : c?.asDouble;
  final used = pviChild(pvi, RscpTag.PVI_USED_STRING_COUNT);
  print('genutzte Strings: ${show(used)}');
  print(
    'max. Strings: ${show(pviChild(pvi, RscpTag.PVI_DC_MAX_STRING_COUNT))}',
  );
  print('Phasen: ${show(pviChild(pvi, RscpTag.PVI_AC_MAX_PHASE_COUNT))}');
  print(
    'max. Scheinleistung AC: ${valueIn(pviChild(pvi, RscpTag.PVI_AC_MAX_APPARENTPOWER))?.toStringAsFixed(0) ?? '—'} VA',
  );
  print('Typ: ${show(pviChild(pvi, RscpTag.PVI_TYPE))}');

  // Alle DC-Eingänge abfragen, nicht nur die als genutzt gemeldeten: PVI_USED_STRING_COUNT
  // stimmt nicht immer mit der Belegung überein. Ein Eingang mit Spannung oder Ertrag ist belegt.
  final maxS = pviChild(pvi, RscpTag.PVI_DC_MAX_STRING_COUNT);
  final usedN = (used != null && !used.isError) ? (used.asInt ?? 0) : 0;
  final maxN = (maxS != null && !maxS.isError) ? (maxS.asInt ?? 2) : 2;
  final count = maxN > usedN ? maxN : usedN;
  print(
    'abgefragt werden $count DC-Eingänge (RSCP nennt sie Strings, in der App heißen sie Tracker)',
  );
  final energies = <double>[];
  for (var s = 0; s < count; s++) {
    final r = await ask(
      RscpMessage.container(RscpTag.PVI_REQ_DATA, [
        RscpMessage.uint16(RscpTag.PVI_INDEX, 0),
        RscpMessage.uint16(RscpTag.PVI_REQ_DC_POWER, s),
        RscpMessage.uint16(RscpTag.PVI_REQ_DC_VOLTAGE, s),
        RscpMessage.uint16(RscpTag.PVI_REQ_DC_CURRENT, s),
        RscpMessage.uint16(RscpTag.PVI_REQ_DC_MAX_POWER, s),
        RscpMessage.uint16(RscpTag.PVI_REQ_DC_STRING_ENERGY_ALL, s),
      ]),
    );
    String f(RscpTag t, int d, String unit) {
      final v = valueIn(pviChild(r, t));
      return v == null ? '—' : '${v.toStringAsFixed(d)} $unit';
    }

    final e = valueIn(pviChild(r, RscpTag.PVI_DC_STRING_ENERGY_ALL));
    if (e != null) energies.add(e);
    print(
      '  String ${s + 1}: ${f(RscpTag.PVI_DC_POWER, 0, 'W')} · ${f(RscpTag.PVI_DC_VOLTAGE, 1, 'V')} · '
      '${f(RscpTag.PVI_DC_CURRENT, 2, 'A')} · Eingangsgrenze ${f(RscpTag.PVI_DC_MAX_POWER, 0, 'W')} · '
      'Ertrag gesamt ${e == null ? '—' : '${(e / 1000).toStringAsFixed(1)} kWh'}',
    );
  }
  if (energies.length == count &&
      energies.fold<double>(0, (a, b) => a + b) > 0) {
    final sum = energies.fold<double>(0, (a, b) => a + b);
    print(
      '  Anteile nach Lebenszeit-Ertrag: ${energies.map((e) => '${(e / sum * 100).toStringAsFixed(1)} %').join(' / ')}',
    );
  }

  // ---------- Batterie ----------
  print('\n== Batterie');
  final bat = await ask(
    RscpMessage.container(RscpTag.BAT_REQ_DATA, [
      RscpMessage.uint16(RscpTag.BAT_INDEX, 0),
      RscpMessage.none(RscpTag.BAT_REQ_DCB_COUNT),
      RscpMessage.none(RscpTag.BAT_REQ_DESIGN_CAPACITY),
      RscpMessage.none(RscpTag.BAT_REQ_USABLE_CAPACITY),
    ]),
  );
  print(
    'Module: ${show(bat.isContainer ? bat.find(RscpTag.BAT_DCB_COUNT) : bat)}',
  );
  print(
    'Nennkapazität: ${show(bat.isContainer ? bat.find(RscpTag.BAT_DESIGN_CAPACITY) : null)} Ah',
  );
  print(
    'nutzbare Kapazität: ${show(bat.isContainer ? bat.find(RscpTag.BAT_USABLE_CAPACITY) : null)} Ah',
  );

  // ---------- Standort ----------
  print('\n== Anlagenadresse (nur PLZ, Ort, Land im Klartext)');
  final fac = await ask(RscpMessage.none(RscpTag.INFO_REQ_GET_FACILITY));
  if (fac.isContainer) {
    for (final tag in [
      RscpTag.INFO_POSTCODE,
      RscpTag.INFO_CITY,
      RscpTag.INFO_COUNTRY,
    ]) {
      print('  ${tag.name}: ${show(fac.find(tag))}');
    }
    for (final tag in [
      RscpTag.INFO_NAME,
      RscpTag.INFO_STREET,
      RscpTag.INFO_STREET_NO,
      RscpTag.INFO_FON,
      RscpTag.INFO_E_MAIL,
    ]) {
      final v = fac.find(tag)?.value;
      print(
        '  ${tag.name}: ${v is String && v.trim().isNotEmpty ? 'vorhanden' : 'leer'}',
      );
    }
  } else {
    print('  ${show(fac)}');
  }

  await t.close();
  print('\nFertig. Die Ausgabe enthält keine Zugangsdaten.');
}
