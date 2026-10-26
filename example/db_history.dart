// Finds out what the unit's database time series contain: energy per interval (Wh) or average
// power (W), how DB_GRAPH_INDEX counts, and how many buckets come back. Read-only.
// Local:  E3DC_HOST=... E3DC_USER=... E3DC_PASS=... E3DC_KEY=... dart run example/db_history.dart
// Portal: E3DC_USER=... E3DC_PASS=... E3DC_SN=S10-... dart run example/db_history.dart
import 'dart:io';

import 'package:openrscp/openrscp.dart';

String f(double v) => v.toStringAsFixed(1);

Future<void> main() async {
  final env = Platform.environment;
  final user = env['E3DC_USER'], pass = env['E3DC_PASS'];
  if (user == null || pass == null) {
    stderr.writeln(
      'Set E3DC_USER and E3DC_PASS plus E3DC_HOST/E3DC_KEY or E3DC_SN.',
    );
    exit(2);
  }
  final RscpTransport t;
  if (env['E3DC_HOST'] != null && env['E3DC_KEY'] != null) {
    t = LocalTransport(
      host: env['E3DC_HOST']!,
      username: user,
      password: pass,
      rscpPassword: env['E3DC_KEY']!,
    );
  } else if (env['E3DC_SN'] != null) {
    t = PortalTransport(
      username: user,
      password: pass,
      serial: env['E3DC_SN']!,
    );
  } else {
    stderr.writeln('Set E3DC_HOST and E3DC_KEY (local) or E3DC_SN (portal).');
    exit(2);
  }
  await t.connect();
  final c = E3dcClient(t);
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);

  // A full past day, so nothing is still being written.
  for (final interval in [
    const Duration(minutes: 15),
    const Duration(hours: 1),
  ]) {
    final h = await c.dbHistory(yesterday, interval, const Duration(days: 1));
    final pv = h.buckets.fold<double>(0, (a, b) => a + b.solar);
    final home = h.buckets.fold<double>(0, (a, b) => a + b.house);
    final hours = interval.inSeconds / 3600;
    print(
      '--- yesterday, interval ${interval.inMinutes} min: ${h.buckets.length} buckets',
    );
    print(
      'sum container: solar ${f(h.sum.solarWh)}  house ${f(h.sum.houseWh)}',
    );
    print('sum of buckets: solar ${f(pv)}  house ${f(home)}');
    print(
      'sum of buckets x interval in h: solar ${f(pv * hours)}  house ${f(home * hours)}',
    );
    final ratio = h.sum.solarWh == 0 ? double.nan : pv / h.sum.solarWh;
    print(
      'solar ratio buckets/sum = ${ratio.toStringAsFixed(3)} '
      '(~1 means Wh per bucket, ~${(1 / hours).toStringAsFixed(0)} means average W)',
    );
    print('first indices: ${h.buckets.take(6).map((b) => b.index).toList()}');
    final sunny = h.buckets.where((b) => b.solar > 0).toList();
    if (sunny.isNotEmpty) {
      print('first sunny bucket: ${sunny.first.toJson()}');
      print('last sunny bucket:  ${sunny.last.toJson()}');
    }
  }

  // A month in daily buckets, to see whether month views can be one request.
  final monthStart = DateTime(now.year, now.month - 1, 1);
  final days = DateTime(now.year, now.month, 1).difference(monthStart).inDays;
  final m = await c.dbHistory(
    monthStart,
    const Duration(days: 1),
    Duration(days: days),
  );
  final mpv = m.buckets.fold<double>(0, (a, b) => a + b.solar);
  print('--- last month in days: ${m.buckets.length} buckets for $days days');
  print('sum container solar ${f(m.sum.solarWh)}, sum of buckets ${f(mpv)}');
  print('first indices: ${m.buckets.take(4).map((b) => b.index).toList()}');
  await t.close();
}
