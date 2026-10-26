import 'message.dart';
import 'transport.dart';

/// Web stand-in for the local transport: browsers cannot open raw TCP sockets, so a direct
/// connection to the unit is impossible there. Same constructor as the native class; [connect] fails.
class LocalTransport extends RscpTransport {
  static const int defaultPort = 5033;

  final String host;
  final int port;
  final String username, password;
  final Duration timeout;
  final void Function(String)? log;

  LocalTransport({
    required this.host,
    required this.username,
    required this.password,
    required String rscpPassword,
    this.port = defaultPort,
    this.timeout = const Duration(seconds: 5),
    this.log,
  });

  RscpAuthLevel get authLevel => RscpAuthLevel.none;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() async => throw RscpTransportException(
    'local RSCP is not available in the browser',
  );

  @override
  Future<void> close() async {}

  @override
  Future<List<RscpMessage>> send(List<RscpMessage> requests) =>
      Future.error(RscpTransportException('not connected'));
}
