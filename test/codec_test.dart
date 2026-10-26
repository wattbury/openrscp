import 'dart:typed_data';

import 'package:openrscp/openrscp.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  group('crc32', () {
    test('reference value', () {
      expect(Crc32.compute('123456789'.codeUnits), 0xCBF43926);
    });
  });

  group('tlv', () {
    test('64-bit values beyond 32 bits and negative, also on the web', () {
      for (final v in [
        -1,
        -22839511,
        0x10000000005,
        -0x10000000005,
        9007199254740991,
      ]) {
        final back = RscpCodec.decodeAll(
          RscpCodec.encodeAll([
            RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, v),
          ]),
        );
        expect(back.single.value, v);
      }
      final big = RscpCodec.decodeAll(
        RscpCodec.encodeAll([
          RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_START, 0x1234567890AB),
        ]),
      );
      expect(big.single.value, 0x1234567890AB);
    });

    test('round trip of all scalar types', () {
      final msgs = [
        RscpMessage.none(RscpTag.EMS_REQ_POWER_PV),
        RscpMessage.bool(RscpTag.INFO_DHCP_STATUS, true),
        RscpMessage.char8(RscpTag.BAT_INDEX, -5),
        RscpMessage.uchar8(RscpTag.SERVER_AUTH_LEVEL, 60),
        RscpMessage.int16(RscpTag.EMS_POWER_PV, -1234),
        RscpMessage.uint16(RscpTag.EMS_POWER_PV, 65000),
        RscpMessage.int32(RscpTag.EMS_POWER_GRID, -398),
        RscpMessage.uint32(RscpTag.EMS_POWER_PV, 0xFFFFFFF0),
        RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, 22839511),
        RscpMessage.uint64(RscpTag.DB_REQ_HISTORY_TIME_START, 1761328800),
        RscpMessage.float32(RscpTag.EMS_AUTARKY, 96.5),
        RscpMessage.double64(RscpTag.EMS_AUTARKY, 1.0 / 3),
        RscpMessage.cstring(RscpTag.INFO_SW_RELEASE, 'S10_2026_027 ü'),
        RscpMessage.bytes(
          RscpTag.SERVER_RSCP_DATA,
          Uint8List.fromList([1, 2, 3]),
        ),
        RscpMessage.timestamp(
          RscpTag.INFO_TIME,
          const RscpTimestamp(1761328800, 500),
        ),
        RscpMessage(
          RscpTag.EMS_POWER_PV.value,
          RscpType.error,
          RscpErrorCode.RSCP_ERR_NOT_AVAILABLE,
        ),
      ];
      final bytes = RscpCodec.encodeAll(msgs);
      final back = RscpCodec.decodeAll(bytes);
      expect(back.length, msgs.length);
      for (var i = 0; i < msgs.length; i++) {
        expect(back[i].tag, msgs[i].tag);
        expect(back[i].type, msgs[i].type);
      }
      expect(back[1].value, true);
      expect(back[2].value, -5);
      expect(back[6].value, -398);
      expect(back[7].value, 0xFFFFFFF0);
      expect(back[8].value, 22839511);
      expect(back[9].value, 1761328800);
      expect(back[10].value, closeTo(96.5, 1e-5));
      expect(back[11].value, closeTo(1.0 / 3, 1e-12));
      expect(back[12].value, 'S10_2026_027 ü');
      expect(back[13].value, [1, 2, 3]);
      expect((back[14].value as RscpTimestamp).seconds, 1761328800);
      expect((back[14].value as RscpTimestamp).nanos, 500);
      expect(back[15].value, RscpErrorCode.RSCP_ERR_NOT_AVAILABLE);
    });

    test('nested container round trip and lookup', () {
      final m = RscpMessage.container(RscpTag.SERVER_REQ_RSCP_CMD, [
        RscpMessage.int64(RscpTag.SERVER_CONNECTION_ID, 7),
        RscpMessage.container(RscpTag.INFO_INFO, [
          RscpMessage.cstring(RscpTag.INFO_SERIAL_NUMBER, 'X'),
        ]),
      ]);
      final (back, used) = RscpCodec.decodeOne(RscpCodec.encode(m));
      expect(used, RscpCodec.encode(m).length);
      expect(back.valueOf<int>(RscpTag.SERVER_CONNECTION_ID), 7);
      expect(
        back
            .find(RscpTag.INFO_INFO)!
            .valueOf<String>(RscpTag.INFO_SERIAL_NUMBER),
        'X',
      );
      expect(back.toString(), contains('SERVER_REQ_RSCP_CMD'));
    });

    test('unknown tag decodes with numeric name', () {
      final bytes = RscpCodec.encode(
        const RscpMessage(0x7F123456, RscpType.int32, 1),
      );
      final (m, _) = RscpCodec.decodeOne(bytes);
      expect(m.tagEnum, isNull);
      expect(m.tagName, '0x7f123456');
      expect(m.value, 1);
    });
  });

  group('frames', () {
    test('client frame from a real session: CRC valid, payload decodes', () {
      final f = RscpCodec.decodeFrame(clientInfoResponseFrame);
      expect(f.control, 0x11);
      expect(f.crcChecked, isTrue);
      expect(f.length, clientInfoResponseFrame.length);
      final ms = f.messages;
      expect(ms.map((m) => m.tagEnum).toList(), [
        RscpTag.INFO_IP_ADDRESS,
        RscpTag.INFO_SUBNET_MASK,
        RscpTag.INFO_GATEWAY,
        RscpTag.INFO_DNS,
        RscpTag.INFO_DHCP_STATUS,
        RscpTag.INFO_TIME,
        RscpTag.INFO_TIME_ZONE,
        RscpTag.INFO_UTC_TIME,
        RscpTag.INFO_A35_SERIAL_NUMBER,
        RscpTag.INFO_INFO,
      ]);
      expect(ms[6].value, 'GMT+2');
      expect(
        ms[9].valueOf<String>(RscpTag.INFO_SERIAL_NUMBER),
        startsWith('WEB_'),
      );
    });

    test('server frame without CRC decodes to INFO requests', () {
      final f = RscpCodec.decodeFrame(serverInfoRequestFrame);
      expect(f.control, 0x01);
      expect(f.crcChecked, isFalse);
      final ms = f.messages;
      expect(ms.length, 10);
      expect(ms.first.tagEnum, RscpTag.INFO_REQ_IP_ADDRESS);
      expect(ms.every((m) => m.type == RscpType.none), isTrue);
    });

    test('server serial frame', () {
      final ms = RscpCodec.decodeFrame(serverSerialFrame).messages;
      expect(ms.single.tagEnum, RscpTag.INFO_SERIAL_NUMBER);
      expect(ms.single.value, 'WEB_07c3fb3d7c8ceba0b395cf66d15171c8715370');
    });

    test('own frame round trip with CRC', () {
      final payload = RscpCodec.encode(
        RscpMessage.int32(RscpTag.EMS_POWER_PV, 3420),
      );
      final frame = RscpCodec.frame(
        payload,
        time: DateTime.utc(2026, 10, 24, 9, 41, 7),
      );
      expect(frame.sublist(0, 4), [0xE3, 0xDC, 0x00, 0x11]);
      final f = RscpCodec.decodeFrame(frame);
      expect(f.payload, payload);
      expect(f.crcChecked, isTrue);
      // corrupt a byte -> CRC error
      final bad = Uint8List.fromList(frame)..[20] ^= 0xFF;
      expect(
        () => RscpCodec.decodeFrame(bad),
        throwsA(isA<RscpFormatException>()),
      );
    });

    test('compact header (ctrl 0x02 | 0x10)', () {
      final payload = RscpCodec.encode(RscpMessage.none(RscpTag.SERVER_PING));
      final header = Uint8List(8);
      header[0] = 0xE3;
      header[1] = 0xDC;
      header[2] = 0x00;
      header[3] = 0x12;
      header.buffer.asByteData().setUint32(4, payload.length, Endian.little);
      final body = Uint8List.fromList(header + payload);
      final crc = Uint8List(4)
        ..buffer.asByteData().setUint32(0, Crc32.compute(body), Endian.little);
      final frame = Uint8List.fromList(body + crc);
      final f = RscpCodec.decodeFrame(frame);
      expect(f.control, 0x12);
      expect(f.messages.single.tagEnum, RscpTag.SERVER_PING);
      expect(f.length, frame.length);
    });

    test('decodeOne unwraps a frame transparently', () {
      final (m, used) = RscpCodec.decodeOne(serverSerialFrame);
      expect(m.tagEnum, RscpTag.INFO_SERIAL_NUMBER);
      expect(used, serverSerialFrame.length);
    });
  });

  group('tags', () {
    test('lookup and namespace helpers', () {
      expect(RscpTag.fromValue(0x01000001), RscpTag.EMS_REQ_POWER_PV);
      expect(RscpTag.EMS_POWER_PV.isResponse, isTrue);
      expect(RscpTag.EMS_REQ_POWER_PV.isResponse, isFalse);
      expect(RscpTag.DB_REQ_HISTORY_DATA_DAY.namespace, 0x06);
      expect(RscpTag.SERVER_REQ_NEW_VIRTUAL_CONNECTION.value, 0xF800A005);
    });
  });
}
