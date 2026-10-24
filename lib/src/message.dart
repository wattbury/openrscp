import 'dart:typed_data';

import 'tags.g.dart';

/// RSCP data types (one byte in the TLV header).
enum RscpType {
  none(0x00),
  bool_(0x01),
  char8(0x02),
  uchar8(0x03),
  int16(0x04),
  uint16(0x05),
  int32(0x06),
  uint32(0x07),
  int64(0x08),
  uint64(0x09),
  float32(0x0A),
  double64(0x0B),
  bitfield(0x0C),
  cstring(0x0D),
  container(0x0E),
  timestamp(0x0F),
  bytearray(0x10),
  error(0xFF);

  final int value;
  const RscpType(this.value);

  static RscpType fromValue(int v) => RscpType.values.firstWhere(
    (t) => t.value == v,
    orElse: () =>
        throw RscpFormatException('unknown RSCP type 0x${v.toRadixString(16)}'),
  );
}

/// A timestamp value: seconds since epoch plus nanoseconds.
class RscpTimestamp {
  final int seconds;
  final int nanos;
  const RscpTimestamp(this.seconds, [this.nanos = 0]);

  factory RscpTimestamp.fromDateTime(DateTime t) {
    final us = t.toUtc().microsecondsSinceEpoch;
    return RscpTimestamp(us ~/ 1000000, (us % 1000000) * 1000);
  }

  DateTime toDateTime() => DateTime.fromMicrosecondsSinceEpoch(
    seconds * 1000000 + nanos ~/ 1000,
    isUtc: true,
  );

  @override
  String toString() => toDateTime().toIso8601String();
}

/// Thrown when bytes cannot be decoded as RSCP.
class RscpFormatException implements Exception {
  final String message;
  RscpFormatException(this.message);
  @override
  String toString() => 'RscpFormatException: $message';
}

/// One tag/type/value triple. Containers hold a list of child messages.
class RscpMessage {
  /// Numeric tag (always available, also for tags unknown to [RscpTag]).
  final int tag;
  final RscpType type;

  /// null, bool, int, double, String, Uint8List, RscpTimestamp, RscpErrorCode or a list of child messages.
  final Object? value;

  const RscpMessage(this.tag, this.type, [this.value]);

  RscpMessage.none(RscpTag t) : this(t.value, RscpType.none);
  RscpMessage.bool(RscpTag t, bool v) : this(t.value, RscpType.bool_, v);
  RscpMessage.uchar8(RscpTag t, int v) : this(t.value, RscpType.uchar8, v);
  RscpMessage.char8(RscpTag t, int v) : this(t.value, RscpType.char8, v);
  RscpMessage.int16(RscpTag t, int v) : this(t.value, RscpType.int16, v);
  RscpMessage.uint16(RscpTag t, int v) : this(t.value, RscpType.uint16, v);
  RscpMessage.int32(RscpTag t, int v) : this(t.value, RscpType.int32, v);
  RscpMessage.uint32(RscpTag t, int v) : this(t.value, RscpType.uint32, v);
  RscpMessage.int64(RscpTag t, int v) : this(t.value, RscpType.int64, v);
  RscpMessage.uint64(RscpTag t, int v) : this(t.value, RscpType.uint64, v);
  RscpMessage.float32(RscpTag t, double v) : this(t.value, RscpType.float32, v);
  RscpMessage.double64(RscpTag t, double v)
    : this(t.value, RscpType.double64, v);
  RscpMessage.cstring(RscpTag t, String v) : this(t.value, RscpType.cstring, v);
  RscpMessage.bytes(RscpTag t, Uint8List v)
    : this(t.value, RscpType.bytearray, v);
  RscpMessage.timestamp(RscpTag t, RscpTimestamp v)
    : this(t.value, RscpType.timestamp, v);
  RscpMessage.container(RscpTag t, List<RscpMessage> children)
    : this(t.value, RscpType.container, children);

  /// The tag as enum, or null if this table does not know it.
  RscpTag? get tagEnum => RscpTag.fromValue(tag);

  String get tagName =>
      tagEnum?.name ?? '0x${tag.toRadixString(16).padLeft(8, '0')}';

  bool get isError => type == RscpType.error;
  bool get isContainer => type == RscpType.container;

  List<RscpMessage> get children =>
      isContainer ? (value as List<RscpMessage>) : const [];

  /// First direct child with [t], or null.
  RscpMessage? find(RscpTag t) {
    for (final c in children) {
      if (c.tag == t.value) return c;
    }
    return null;
  }

  /// Value of the first direct child with [t], cast to [T]; null if absent or of another type.
  T? valueOf<T>(RscpTag t) {
    final v = find(t)?.value;
    return v is T ? v : null;
  }

  /// Numeric value as double (works for all integer and float types).
  double? get asDouble {
    final v = value;
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  int? get asInt {
    final v = value;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  @override
  String toString() {
    if (isContainer) return '$tagName {${children.join(', ')}}';
    final v = value;
    final shown = v is Uint8List ? 'bytes(${v.length})' : '$v';
    return '$tagName ${type.name} $shown';
  }
}
