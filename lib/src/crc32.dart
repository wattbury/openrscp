import 'dart:typed_data';

/// CRC-32 (IEEE 802.3, same as zlib.crc32) as used by RSCP frames.
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }

  /// Computes the CRC-32 of [data] (optionally of the range [start], [end)).
  static int compute(List<int> data, [int start = 0, int? end]) {
    end ??= data.length;
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc = _table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
