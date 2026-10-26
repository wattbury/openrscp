import 'dart:convert';
import 'dart:typed_data';

import 'crc32.dart';
import 'errors.g.dart';
import 'message.dart';

/// Result of decoding one frame: its payload (a sequence of TLVs) and how many bytes it used.
class RscpFrame {
  final Uint8List payload;
  final int control;
  final int length;
  final bool crcChecked;
  const RscpFrame(this.payload, this.control, this.length, this.crcChecked);

  /// Decodes the payload into its TLV messages.
  List<RscpMessage> get messages => RscpCodec.decodeAll(payload);
}

/// Encoder/decoder for RSCP TLVs and frames.
///
/// TLV: tag uint32 LE | type uint8 | length uint16 LE | data.
/// Frame (standard, 18-byte header): magic E3 DC | ctrl (2 bytes, big-endian) | seconds uint32 LE | 0 uint32 |
/// nanoseconds uint32 LE | length uint16 LE | payload | crc32 LE (if ctrl & 0x10).
/// Frame (compact, ctrl & 0x02, used by the portal relay since 2026): magic | ctrl | length uint32 LE | payload | crc32.
class RscpCodec {
  static const int magic = 0xE3DC;
  static const int ctrlCrc = 0x10;
  static const int ctrlCompact = 0x02;

  // ---------- TLV ----------

  static Uint8List encode(RscpMessage m) {
    final b = BytesBuilder(copy: false);
    _encodeInto(b, m);
    return b.toBytes();
  }

  static Uint8List encodeAll(Iterable<RscpMessage> ms) {
    final b = BytesBuilder(copy: false);
    for (final m in ms) {
      _encodeInto(b, m);
    }
    return b.toBytes();
  }

  static void _encodeInto(BytesBuilder b, RscpMessage m) {
    final Uint8List data;
    switch (m.type) {
      case RscpType.none:
        data = Uint8List(0);
      case RscpType.bool_:
        data = Uint8List.fromList([(m.value as bool) ? 1 : 0]);
      case RscpType.char8:
      case RscpType.uchar8:
        data = Uint8List.fromList([(m.value as int) & 0xFF]);
      case RscpType.int16:
      case RscpType.uint16:
        data = Uint8List(2)
          ..buffer.asByteData().setUint16(
            0,
            (m.value as int) & 0xFFFF,
            Endian.little,
          );
      case RscpType.int32:
        data = Uint8List(4)
          ..buffer.asByteData().setInt32(0, m.value as int, Endian.little);
      case RscpType.uint32:
        data = Uint8List(4)
          ..buffer.asByteData().setUint32(
            0,
            (m.value as int) & 0xFFFFFFFF,
            Endian.little,
          );
      case RscpType.int64:
      case RscpType.uint64:
        data = Uint8List(8);
        _setInt64(data.buffer.asByteData(), 0, m.value as int);
      case RscpType.float32:
        data = Uint8List(4)
          ..buffer.asByteData().setFloat32(
            0,
            (m.value as num).toDouble(),
            Endian.little,
          );
      case RscpType.double64:
        data = Uint8List(8)
          ..buffer.asByteData().setFloat64(
            0,
            (m.value as num).toDouble(),
            Endian.little,
          );
      case RscpType.timestamp:
        final t = m.value as RscpTimestamp;
        data = Uint8List(12);
        final bd = data.buffer.asByteData();
        _setInt64(bd, 0, t.seconds);
        bd.setInt32(8, t.nanos, Endian.little);
      case RscpType.cstring:
        data = Uint8List.fromList(utf8.encode(m.value as String));
      case RscpType.bitfield:
      case RscpType.bytearray:
        data = m.value as Uint8List;
      case RscpType.error:
        final code = m.value is RscpErrorCode
            ? (m.value as RscpErrorCode).value
            : (m.value as int);
        data = Uint8List(4)
          ..buffer.asByteData().setUint32(0, code & 0xFFFFFFFF, Endian.little);
      case RscpType.container:
        data = encodeAll(m.children);
    }
    if (data.length > 0xFFFF) {
      throw RscpFormatException('TLV too long: ${data.length}');
    }
    final header = Uint8List(7);
    final bd = header.buffer.asByteData();
    bd.setUint32(0, m.tag & 0xFFFFFFFF, Endian.little);
    bd.setUint8(4, m.type.value);
    bd.setUint16(5, data.length, Endian.little);
    b.add(header);
    b.add(data);
  }

  /// Decodes one TLV at [offset]. If the bytes start with the frame magic, the frame is unwrapped first.
  static (RscpMessage, int) decodeOne(Uint8List data, [int offset = 0]) {
    if (data.length - offset >= 2 &&
        data[offset] == 0xE3 &&
        data[offset + 1] == 0xDC) {
      final f = decodeFrame(data, offset);
      final (m, _) = decodeOne(f.payload);
      return (m, f.length);
    }
    if (data.length - offset < 7) {
      throw RscpFormatException('TLV header truncated');
    }
    final bd = ByteData.sublistView(data, offset);
    final tag = bd.getUint32(0, Endian.little);
    final type = RscpType.fromValue(bd.getUint8(4));
    final len = bd.getUint16(5, Endian.little);
    final start = offset + 7, end = start + len;
    if (end > data.length) {
      throw RscpFormatException(
        'TLV body truncated (tag 0x${tag.toRadixString(16)}, len $len)',
      );
    }
    final body = ByteData.sublistView(data, start, end);
    Object? value;
    switch (type) {
      case RscpType.none:
        value = null;
      case RscpType.bool_:
        value = body.getUint8(0) != 0;
      case RscpType.char8:
        value = body.getInt8(0);
      case RscpType.uchar8:
        value = body.getUint8(0);
      case RscpType.int16:
        value = body.getInt16(0, Endian.little);
      case RscpType.uint16:
        value = body.getUint16(0, Endian.little);
      case RscpType.int32:
        value = body.getInt32(0, Endian.little);
      case RscpType.uint32:
        value = body.getUint32(0, Endian.little);
      case RscpType.int64:
        value = _getInt64(body, 0, signed: true);
      case RscpType.uint64:
        value = _getInt64(body, 0, signed: false);
      case RscpType.float32:
        value = body.getFloat32(0, Endian.little);
      case RscpType.double64:
        value = body.getFloat64(0, Endian.little);
      case RscpType.timestamp:
        // int64 seconds + int32 nanoseconds. Some senders put the seconds into the second dword; take whichever is non-zero.
        final lo = body.getUint32(0, Endian.little),
            hi = body.getUint32(4, Endian.little);
        final secs = hi == 0 ? lo : (lo == 0 ? hi : hi * _twoPow32 + lo);
        value = RscpTimestamp(secs, body.getInt32(8, Endian.little));
      case RscpType.cstring:
        value = utf8.decode(
          Uint8List.sublistView(data, start, end),
          allowMalformed: true,
        );
      case RscpType.bitfield:
      case RscpType.bytearray:
        value = Uint8List.fromList(Uint8List.sublistView(data, start, end));
      case RscpType.error:
        value = RscpErrorCode.fromValue(
          len >= 4 ? body.getUint32(0, Endian.little) : 0xFFFFFFFF,
        );
      case RscpType.container:
        final children = <RscpMessage>[];
        var p = start;
        while (p < end) {
          final (c, used) = decodeOne(data, p);
          children.add(c);
          p += used;
        }
        value = children;
    }
    return (RscpMessage(tag, type, value), 7 + len);
  }

  /// Decodes a sequence of TLVs (e.g. a frame payload).
  static List<RscpMessage> decodeAll(Uint8List data) {
    final out = <RscpMessage>[];
    var p = 0;
    while (p < data.length) {
      final (m, used) = decodeOne(data, p);
      out.add(m);
      p += used;
    }
    return out;
  }

  // ---------- Frames ----------

  /// Wraps [payload] in a standard frame with timestamp and CRC (ctrl 0x11), as clients send it.
  static Uint8List frame(Uint8List payload, {DateTime? time}) {
    final t = time ?? DateTime.now();
    final us = t.toUtc().microsecondsSinceEpoch;
    final header = Uint8List(18);
    final bd = header.buffer.asByteData();
    header[0] = 0xE3;
    header[1] = 0xDC;
    header[2] = 0x00;
    header[3] = 0x11;
    bd.setUint32(4, us ~/ 1000000, Endian.little);
    bd.setUint32(8, 0, Endian.little);
    bd.setUint32(12, (us % 1000000) * 1000, Endian.little);
    bd.setUint16(16, payload.length, Endian.little);
    final body = BytesBuilder(copy: false)
      ..add(header)
      ..add(payload);
    final bytes = body.toBytes();
    final crc = Uint8List(4)
      ..buffer.asByteData().setUint32(0, Crc32.compute(bytes), Endian.little);
    return Uint8List.fromList(bytes + crc);
  }

  /// Convenience: frame a list of TLVs.
  static Uint8List frameMessages(Iterable<RscpMessage> ms, {DateTime? time}) =>
      frame(encodeAll(ms), time: time);

  /// Decodes a frame (standard or compact header) starting at [offset]; verifies the CRC when present.
  static RscpFrame decodeFrame(Uint8List data, [int offset = 0]) {
    if (data.length - offset < 8) throw RscpFormatException('frame truncated');
    if (data[offset] != 0xE3 || data[offset + 1] != 0xDC) {
      throw RscpFormatException('bad frame magic');
    }
    final ctrl = (data[offset + 2] << 8) | data[offset + 3];
    final bd = ByteData.sublistView(data, offset);
    final int headerLen, payloadLen;
    if (ctrl & ctrlCompact != 0) {
      headerLen = 8;
      payloadLen = bd.getUint32(4, Endian.little);
    } else {
      if (data.length - offset < 18) {
        throw RscpFormatException('frame header truncated');
      }
      headerLen = 18;
      payloadLen = bd.getUint16(16, Endian.little);
    }
    final hasCrc = ctrl & ctrlCrc != 0;
    final total = headerLen + payloadLen + (hasCrc ? 4 : 0);
    if (offset + total > data.length) {
      throw RscpFormatException(
        'frame body truncated (need $total, have ${data.length - offset})',
      );
    }
    if (hasCrc) {
      final expected = bd.getUint32(headerLen + payloadLen, Endian.little);
      final actual = Crc32.compute(
        data,
        offset,
        offset + headerLen + payloadLen,
      );
      if (expected != actual) throw RscpFormatException('frame CRC mismatch');
    }
    final payload = Uint8List.fromList(
      Uint8List.sublistView(
        data,
        offset + headerLen,
        offset + headerLen + payloadLen,
      ),
    );
    return RscpFrame(payload, ctrl, total, hasCrc);
  }
}

// 64-bit values as two 32-bit halves: dart2js has no Int64 accessors on ByteData, and JS numbers are
// exact up to 2^53, which covers every 64-bit value RSCP actually carries (ids, timestamps, counters).
const _twoPow32 = 0x100000000;

int _getInt64(ByteData b, int offset, {required bool signed}) {
  final lo = b.getUint32(offset, Endian.little);
  final hi = signed
      ? b.getInt32(offset + 4, Endian.little)
      : b.getUint32(offset + 4, Endian.little);
  return hi * _twoPow32 + lo;
}

void _setInt64(ByteData b, int offset, int value) {
  final lo = value % _twoPow32;
  b.setUint32(offset, lo, Endian.little);
  b.setInt32(offset + 4, (value - lo) ~/ _twoPow32, Endian.little);
}
