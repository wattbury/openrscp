// Connects to the unit in the local network and prints system info and live values.
// Usage: E3DC_HOST=192.168.x.y E3DC_USER=... E3DC_PASS=... E3DC_KEY=<RSCP password> \
//        dart run example/local_live.dart [seconds] [port]
import 'dart:convert';
import 'dart:io';

import 'package:openrscp/openrscp.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final host = env['E3DC_HOST'], user = env['E3DC_USER'];
  final pass = env['E3DC_PASS'], key = env['E3DC_KEY'];
  if (host == null || user == null || pass == null || key == null) {
    stderr.writeln('Set E3DC_HOST, E3DC_USER, E3DC_PASS and E3DC_KEY.');
    exit(2);
  }
  final seconds = args.isNotEmpty ? int.parse(args[0]) : 5;
  final port = args.length > 1
      ? int.parse(args[1])
      : LocalTransport.defaultPort;
  final t = LocalTransport(
    host: host,
    port: port,
    username: user,
    password: pass,
    rscpPassword: key,
    log: (s) => stderr.writeln('[local] $s'),
  );
  final sw = Stopwatch()..start();
  await t.connect();
  print(
    'connected in ${sw.elapsedMilliseconds} ms, auth level ${t.authLevel.name}',
  );
  final c = E3dcClient(t);
  print('system:   ${jsonEncode((await c.systemInfo()).toJson())}');
  for (var i = 0; i < seconds; i++) {
    sw.reset();
    final live = await c.live();
    print('live ${sw.elapsedMilliseconds} ms: ${jsonEncode(live.toJson())}');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await t.close();
}
