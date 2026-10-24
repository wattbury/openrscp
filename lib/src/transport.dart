import 'message.dart';

/// A way to exchange RSCP messages with a home power station.
abstract class RscpTransport {
  /// Establishes the connection (and authentication). Completes when requests can be sent.
  Future<void> connect();

  /// Sends one or more request TLVs in a single frame and returns the response TLVs.
  Future<List<RscpMessage>> send(List<RscpMessage> requests);

  /// Convenience for a single request/response pair.
  Future<RscpMessage> sendOne(RscpMessage request) async {
    final r = await send([request]);
    if (r.isEmpty) {
      throw RscpTransportException('empty response for ${request.tagName}');
    }
    return r.first;
  }

  bool get isConnected;

  Future<void> close();
}

class RscpTransportException implements Exception {
  final String message;
  RscpTransportException(this.message);
  @override
  String toString() => 'RscpTransportException: $message';
}

class RscpAuthException extends RscpTransportException {
  RscpAuthException(super.message);
}

/// RSCP user levels as reported by the device or the portal.
enum RscpAuthLevel {
  none(0),
  user(10),
  installer(20),
  service(30),
  admin(40),
  e3dc(50),
  e3dcRoot(60);

  final int value;
  const RscpAuthLevel(this.value);
  static RscpAuthLevel fromValue(int v) => RscpAuthLevel.values.lastWhere(
    (l) => l.value <= v,
    orElse: () => RscpAuthLevel.none,
  );
}
