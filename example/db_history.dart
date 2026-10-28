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

  // Today, still running: once as the whole day and once only up to the last finished quarter
  // hour, to see how the unit answers spans that end now and whether the newest buckets lag.
  final today = DateTime(now.year, now.month, now.day);
  final finished = now.difference(today).inMinutes ~/ 15;
  const q = Duration(minutes: 15);
  for (final (name, span) in [
    ('whole day', const Duration(days: 1)),
    ('up to now', q * finished),
  ]) {
    if (span == Duration.zero) continue;
    final h = await c.dbHistory(today, q, span);
    final pv = h.buckets.fold<double>(0, (a, b) => a + b.solar);
    print(
      '--- today ($name, span ${span.inMinutes} min): ${h.buckets.length} buckets',
    );
    print(
      'sum container: solar ${f(h.sum.solarWh)}  sum of buckets: solar ${f(pv)}',
    );
    print(
      'solar ratio buckets/sum = ${h.sum.solarWh == 0 ? 'n/a' : (pv / h.sum.solarWh).toStringAsFixed(3)}',
    );
    final from = (finished - 6).clamp(0, h.buckets.length);
    for (var i = from; i < h.buckets.length && i < finished + 2; i++) {
      final b = h.buckets[i];
      final t = today.add(q * i);
      print(
        '  #$i ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        '  index ${f(b.index)}  solar ${f(b.solar)}  house ${f(b.house)}',
      );
    }
  }
  final live = await c.live();
  print('live now: solar ${f(live.solarW.toDouble())} W');

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
