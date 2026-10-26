// Reads the smart-function settings without changing anything: power settings, system limits and
// lock periods. Compare the lock periods with the unit's display to check the weekday numbering.
// Local:  E3DC_HOST=... E3DC_USER=... E3DC_PASS=... E3DC_KEY=... dart run example/smart_read.dart
// Portal: E3DC_USER=... E3DC_PASS=... E3DC_SN=S10-... dart run example/smart_read.dart
import 'dart:convert';
import 'dart:io';

import 'package:openrscp/openrscp.dart';

const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

Future<void> main() async {
  final env = Platform.environment;
  final user = env['E3DC_USER'], pass = env['E3DC_PASS'];
  if (user == null || pass == null) {
    stderr.writeln(
      'Set E3DC_USER and E3DC_PASS plus E3DC_HOST/E3DC_KEY or E3DC_SN.',
    );
    exit(2);
  }
  final RscpTransport t = env['E3DC_HOST'] != null && env['E3DC_KEY'] != null
      ? LocalTransport(
          host: env['E3DC_HOST']!,
          username: user,
          password: pass,
          rscpPassword: env['E3DC_KEY']!,
        )
      : PortalTransport(
          username: user,
          password: pass,
          serial: env['E3DC_SN'] ?? '',
        );
  await t.connect();
  final c = E3dcClient(t);
  print('power settings: ${jsonEncode((await c.powerSettings()).toJson())}');
  print('system specs:   ${jsonEncode(await c.sysSpecs())}');
  print('lock periods (day number as reported, label assuming 0 = Monday):');
  for (final p in await c.idlePeriods()) {
    final label = p.day >= 0 && p.day < 7 ? days[p.day] : '?';
    print(
      '  ${p.type == IdleType.charge ? 'Ladesperre   ' : 'Entladesperre'} '
      'day ${p.day} ($label) ${p.active ? 'aktiv  ' : 'inaktiv'} '
      '${p.startHour.toString().padLeft(2, '0')}:${p.startMinute.toString().padLeft(2, '0')}'
      '–${p.endHour.toString().padLeft(2, '0')}:${p.endMinute.toString().padLeft(2, '0')}',
    );
  }
  await t.close();
}
