/// RSCP protocol for E3/DC home power stations: TLV codec, frames, local transport (Rijndael-256), portal tunnel transport and a small client.
library;

export 'src/client.dart';
export 'src/codec.dart';
export 'src/crc32.dart';
export 'src/errors.g.dart';
// Browsers cannot open TCP sockets; on the web LocalTransport is a stub that refuses to connect.
export 'src/local_transport.dart'
    if (dart.library.js_interop) 'src/local_transport_web.dart';
export 'src/message.dart';
export 'src/portal_transport.dart';
export 'src/rijndael.dart';
export 'src/tags.g.dart';
export 'src/transport.dart';
