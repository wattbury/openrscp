import 'dart:typed_data';

/// Rijndael with a 256-bit block and a 256-bit key, as the local RSCP connection uses it.
///
/// This is not AES: AES fixes the block at 128 bits. With Nb = Nk = 8 there are 14 rounds and
/// ShiftRows moves rows 1, 2 and 3 by 1, 3 and 4 columns.
class Rijndael256 {
  static const int blockSize = 32;
  static const int _nb = 8, _nk = 8, _nr = 14;
  static const _shift = [0, 1, 3, 4];

  static final Uint8List _sbox = Uint8List(256), _inv = Uint8List(256);
  static bool _tablesReady = false;

  final List<Uint8List> _roundKeys;

  Rijndael256(Uint8List key) : _roundKeys = _expand(key);

  /// Multiplication in GF(2^8) with the AES polynomial.
  static int _mul(int a, int b) {
    var p = 0;
    while (b > 0) {
      if (b & 1 != 0) p ^= a;
      a = (a << 1) ^ ((a & 0x80) != 0 ? 0x11b : 0);
      b >>= 1;
    }
    return p & 0xff;
  }

  static void _initTables() {
    if (_tablesReady) return;
    for (var x = 0; x < 256; x++) {
      var inv = 0;
      if (x != 0) {
        for (var y = 1; y < 256; y++) {
          if (_mul(x, y) == 1) {
            inv = y;
            break;
          }
        }
      }
      var s = inv;
      for (var i = 1; i <= 4; i++) {
        s ^= ((inv << i) | (inv >> (8 - i))) & 0xff;
      }
      s ^= 0x63;
      _sbox[x] = s;
      _inv[s] = x;
    }
    _tablesReady = true;
  }

  static List<Uint8List> _expand(Uint8List key) {
    if (key.length != 32) throw ArgumentError('key must be 32 bytes');
    _initTables();
    final words = (_nr + 1) * _nb;
    final w = List<Uint8List>.generate(words, (_) => Uint8List(4));
    for (var i = 0; i < _nk; i++) {
      w[i].setRange(0, 4, key, 4 * i);
    }
    var rcon = 1;
    for (var i = _nk; i < words; i++) {
      final t = Uint8List.fromList(w[i - 1]);
      if (i % _nk == 0) {
        final first = t[0];
        t[0] = _sbox[t[1]] ^ rcon;
        t[1] = _sbox[t[2]];
        t[2] = _sbox[t[3]];
        t[3] = _sbox[first];
        rcon = _mul(rcon, 2);
      } else if (i % _nk == 4) {
        for (var j = 0; j < 4; j++) {
          t[j] = _sbox[t[j]];
        }
      }
      for (var j = 0; j < 4; j++) {
        w[i][j] = w[i - _nk][j] ^ t[j];
      }
    }
    // One 32-byte round key per round, laid out column by column like the state.
    return [
      for (var r = 0; r <= _nr; r++)
        Uint8List.fromList([for (var c = 0; c < _nb; c++) ...w[r * _nb + c]]),
    ];
  }

  /// State is column-major: byte (row r, column c) sits at index 4 * c + r.
  static void _addRoundKey(Uint8List s, Uint8List k) {
    for (var i = 0; i < blockSize; i++) {
      s[i] ^= k[i];
    }
  }

  static void _shiftRows(Uint8List s, {required bool inverse}) {
    final row = Uint8List(_nb);
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < _nb; c++) {
        row[c] = s[4 * c + r];
      }
      for (var c = 0; c < _nb; c++) {
        final from = inverse
            ? (c - _shift[r] + _nb) % _nb
            : (c + _shift[r]) % _nb;
        s[4 * c + r] = row[from];
      }
    }
  }

  static void _mixColumns(Uint8List s, {required bool inverse}) {
    final m = inverse ? const [14, 11, 13, 9] : const [2, 3, 1, 1];
    for (var c = 0; c < _nb; c++) {
      final a = Uint8List.sublistView(s, 4 * c, 4 * c + 4);
      final col = Uint8List.fromList(a);
      for (var r = 0; r < 4; r++) {
        a[r] =
            _mul(col[r], m[0]) ^
            _mul(col[(r + 1) % 4], m[1]) ^
            _mul(col[(r + 2) % 4], m[2]) ^
            _mul(col[(r + 3) % 4], m[3]);
      }
    }
  }

  /// Encrypts one 32-byte block in place.
  void encryptBlock(Uint8List s) {
    _addRoundKey(s, _roundKeys[0]);
    for (var round = 1; round <= _nr; round++) {
      for (var i = 0; i < blockSize; i++) {
        s[i] = _sbox[s[i]];
      }
      _shiftRows(s, inverse: false);
      if (round != _nr) _mixColumns(s, inverse: false);
      _addRoundKey(s, _roundKeys[round]);
    }
  }

  /// Decrypts one 32-byte block in place.
  void decryptBlock(Uint8List s) {
    _addRoundKey(s, _roundKeys[_nr]);
    for (var round = _nr - 1; round >= 0; round--) {
      _shiftRows(s, inverse: true);
      for (var i = 0; i < blockSize; i++) {
        s[i] = _inv[s[i]];
      }
      _addRoundKey(s, _roundKeys[round]);
      if (round != 0) _mixColumns(s, inverse: true);
    }
  }
}

/// CBC chaining that carries over from one message to the next, as the S10 expects:
/// both directions start with an IV of 0xFF bytes, each message is zero-padded to whole blocks,
/// and the last ciphertext block becomes the IV for the next message.
class RscpCipher {
  final Rijndael256 _r;
  final Uint8List _encIv = Uint8List(Rijndael256.blockSize)
    ..fillRange(0, Rijndael256.blockSize, 0xff);
  final Uint8List _decIv = Uint8List(Rijndael256.blockSize)
    ..fillRange(0, Rijndael256.blockSize, 0xff);
  final BytesBuilder _pending = BytesBuilder();

  /// [rscpPassword] is the "RSCP password" set on the unit; it is padded with 0xFF to 32 bytes.
  RscpCipher(List<int> rscpPassword) : _r = Rijndael256(_key(rscpPassword));

  static Uint8List _key(List<int> pw) {
    if (pw.length > 32) {
      throw ArgumentError('RSCP password must be at most 32 bytes');
    }
    return Uint8List(32)
      ..fillRange(0, 32, 0xff)
      ..setRange(0, pw.length, pw);
  }

  /// Encrypts one message (an RSCP frame), zero-padded to whole blocks.
  Uint8List encrypt(Uint8List plain) {
    const bs = Rijndael256.blockSize;
    final n = (plain.length + bs - 1) ~/ bs * bs;
    final out = Uint8List(n == 0 ? bs : n)..setRange(0, plain.length, plain);
    for (var o = 0; o < out.length; o += bs) {
      final b = Uint8List.sublistView(out, o, o + bs);
      for (var i = 0; i < bs; i++) {
        b[i] ^= _encIv[i];
      }
      _r.encryptBlock(b);
      _encIv.setAll(0, b);
    }
    return out;
  }

  /// Feeds received ciphertext; returns the plaintext of all complete blocks so far.
  /// Incomplete trailing bytes are kept until more data arrives.
  Uint8List decrypt(List<int> data) {
    const bs = Rijndael256.blockSize;
    _pending.add(data);
    final all = _pending.takeBytes();
    final full = all.length ~/ bs * bs;
    if (full < all.length) _pending.add(Uint8List.sublistView(all, full));
    final out = Uint8List(full);
    final c = Uint8List(bs);
    for (var o = 0; o < full; o += bs) {
      c.setRange(0, bs, all, o);
      final b = Uint8List.fromList(c);
      _r.decryptBlock(b);
      for (var i = 0; i < bs; i++) {
        out[o + i] = b[i] ^ _decIv[i];
      }
      _decIv.setAll(0, c);
    }
    return out;
  }
}
