// Connects through the E3/DC portal relay and prints live values, system info, power settings and today's summary.
// Usage: E3DC_USER=... E3DC_PASS=... E3DC_SN=S10-... dart run example/portal_live.dart [seconds]
import 'dart:convert';
import 'dart:io';

import 'package:openrscp/openrscp.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final user = env['E3DC_USER'], pass = env['E3DC_PASS'], sn = env['E3DC_SN'];
  if (user == null || pass == null || sn == null) {
    stderr.writeln('Set E3DC_USER, E3DC_PASS and E3DC_SN.');
    exit(2);
  }
  final seconds = args.isNotEmpty ? int.parse(args.first) : 5;
  final t = PortalTransport(
    username: user,
    password: pass,
    serial: sn,
    log: (s) => stderr.writeln('[portal] $s'),
  );
  final sw = Stopwatch()..start();
  await t.connect();
  print(
    'connected in ${sw.elapsedMilliseconds} ms, auth level ${t.authLevel.name}',
  );
  final c = E3dcClient(t);
  print('system:   ${jsonEncode((await c.systemInfo()).toJson())}');
  print('settings: ${jsonEncode((await c.powerSettings()).toJson())}');
  final today = DateTime.now();
  print(
    'today:    ${jsonEncode((await c.dbSummary(DateTime(today.year, today.month, today.day), const Duration(days: 1))).toJson())}',
  );
  for (var i = 0; i < seconds; i++) {
    sw.reset();
    final live = await c.live();
    print('live ${sw.elapsedMilliseconds} ms: ${jsonEncode(live.toJson())}');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await t.close();
}
