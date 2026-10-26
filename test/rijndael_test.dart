import 'dart:convert';
import 'dart:typed_data';

import 'package:openrscp/src/rijndael.dart';
import 'package:test/test.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);
String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List range(int from, int to) =>
    Uint8List.fromList([for (var i = from; i < to; i++) i]);

// Reference values from py3rijndael 0.3.3 (the library python-e3dc uses).
void main() {
  test('single block, key and plaintext 00..1f', () {
    final r = Rijndael256(range(0, 32));
    final b = range(0, 32);
    r.encryptBlock(b);
    expect(
      toHex(b),
      '623d2bd4ca3796dc3d02ecf2f37fb637fd3da58509cebb67ab9265b04db51e7d',
    );
    r.decryptBlock(b);
    expect(b, range(0, 32));
  });

  test('RSCP key padding with 0xFF', () {
    final key = Uint8List(32)
      ..fillRange(0, 32, 0xff)
      ..setRange(0, 6, utf8.encode('geheim'));
    final b = Uint8List(32);
    Rijndael256(key).encryptBlock(b);
    expect(
      toHex(b),
      '67804b4311eaa03044ac5617f6498f80abce3a9afe172cd2f50a735f61275c26',
    );
  });

  const c1 =
      '8d41bef7d41b54699380bca879aca9d03660556e89698e07c5696dc03e1c49c2'
      'a5e8e33172da49e0d3ab56d3e1a03a2abba8ef80ad2df48c90da314f8ccff25e';
  const c2 =
      '914e2557c5b107936f126fd1ce0ee5cff68d67cdf35929b3dab751b09f9c94a6'
      '85b453b19a8915aab660317a60ccb89e1936172fa72ef4f267ae51944e817bec'
      '421b5b4803d799f617c6c3678eb7ad6715e58f76668f80fbb75f191c400c2a5a';

  test('CBC chains across messages and zero-pads', () {
    final enc = RscpCipher(utf8.encode('geheim'));
    expect(toHex(enc.encrypt(range(0, 50))), c1);
    expect(toHex(enc.encrypt(range(100, 170))), c2);
  });

  test('decrypt accepts arbitrary chunking', () {
    final dec = RscpCipher(utf8.encode('geheim'));
    final stream = hex(c1 + c2);
    final out = BytesBuilder();
    for (var o = 0; o < stream.length; o += 13) {
      out.add(
        dec.decrypt(
          stream.sublist(o, o + 13 > stream.length ? stream.length : o + 13),
        ),
      );
    }
    final plain = out.takeBytes();
    expect(plain.length, 64 + 96);
    expect(plain.sublist(0, 50), range(0, 50));
    expect(plain.sublist(50, 64), Uint8List(14));
    expect(plain.sublist(64, 134), range(100, 170));
  });
}
