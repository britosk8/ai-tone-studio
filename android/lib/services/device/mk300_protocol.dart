// M-EFCS protocol adapted from jpfaria/mvave, MIT (third_party/mvave/LICENSE).
import 'dart:typed_data';

class PedalFrame {
  final int cls, command, field, length, space;
  final Uint8List payload;
  PedalFrame(this.cls, this.command, this.field, this.length, this.space,
      this.payload);
}

class Mk300Protocol {
  static const size = 448;
  static const ack = <int>[0xf0, 0, 0x32, 1, 8, 0, 0, 0, 0, 0x7f, 1, 0xf7];
  static Uint8List pack7(List<int> bytes) {
    var bits = 0, n = 0;
    final out = <int>[];
    for (final b in bytes) {
      bits |= b << n;
      n += 8;
      while (n >= 7) {
        out.add(bits & 127);
        bits >>= 7;
        n -= 7;
      }
    }
    if (n > 0) out.add(bits & 127);
    return Uint8List.fromList(out);
  }

  static Uint8List unpack7(List<int> bytes) {
    var bits = 0, n = 0;
    final out = <int>[];
    for (final b in bytes) {
      if (b < 0 || b > 127) throw const FormatException('Byte MIDI inválido');
      bits |= b << n;
      n += 7;
      while (n >= 8) {
        out.add(bits & 255);
        bits >>= 8;
        n -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  static List<int> _u32(int v) => List.generate(4, (i) => (v >> (7 * i)) & 127);
  static int _from(List<int> b) => b[0] | b[1] << 7 | b[2] << 14 | b[3] << 21;
  static int checksum(int field, int length, int space, List<int> payload) {
    var sum = payload.fold<int>(0, (a, b) => a + b);
    final sub = length << 8 | space << 4;
    for (var i = 0; i < 4; i++) {
      sum += (field >> (i * 8)) & 255;
      sum += (sub >> (i * 8)) & 255;
    }
    return (0xfb - sum) & 255;
  }

  static Uint8List build(int cls, int cmd, int field, int length, int space,
          [List<int> payload = const []]) =>
      Uint8List.fromList([
        0xf0,
        0,
        0x32,
        cls,
        ..._u32(cmd),
        2,
        ..._u32(field),
        ..._u32(length << 4 | space),
        ...pack7([...payload, checksum(field, length, space, payload)]),
        0xf7,
      ]);
  static Uint8List read(int field, int length, [int space = 1]) =>
      build(13, 0x41, field, length, space);
  static Uint8List bankWrite(int slot, List<int> image) {
    if (slot < 0 || slot >= 160 || image.length != size) {
      throw ArgumentError('Slot/imagem inválido');
    }
    return build(9, 0x41 | ((size ~/ 16) << 7), slot * size, size, 0, image);
  }

  static Uint8List commit() => build(9, 0x41, 0, 0, 15);
  static PedalFrame parse(List<int> bytes) {
    if (bytes.length < 20 ||
        bytes[0] != 240 ||
        bytes[1] != 0 ||
        bytes[2] != 50 ||
        bytes.last != 247 ||
        bytes[8] != 2) throw const FormatException('Frame M-EFCS inválido');
    if (bytes.sublist(1, bytes.length - 1).any((b) => b > 127)) {
      throw const FormatException('Frame MIDI não codificado');
    }
    final sub = _from(bytes.sublist(13, 17));
    final field = _from(bytes.sublist(9, 13)),
        length = sub >> 4,
        space = sub & 15;
    final decoded = unpack7(bytes.sublist(17, bytes.length - 1));
    if (decoded.isEmpty) throw const FormatException('Checksum ausente');
    final payload = decoded.sublist(0, decoded.length - 1);
    if (decoded.last != checksum(field, length, space, payload)) {
      throw const FormatException('Checksum inválido');
    }
    return PedalFrame(bytes[3], _from(bytes.sublist(4, 8)), field, length,
        space, Uint8List.fromList(payload));
  }

  static bool isAck(List<int> data) => same(data, ack);
  static bool same(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
  static String name(List<int> data) =>
      String.fromCharCodes(data.take(20).takeWhile((b) => b != 0));
  static void validateImage(List<int> data, Map<int, int> modelCounts) {
    if (data.length != size ||
        !same(data.sublist(20, 24), [255, 144, 30, 0]) ||
        data[447] != 69) {
      throw const FormatException('Layout do preset não corresponde à MK300');
    }
    final chain = data.sublist(32, 43);
    if (chain.toSet().length != 11 || chain.any((b) => b < 0 || b > 10)) {
      throw const FormatException('Cadeia MK300 inválida');
    }
    for (var i = 0; i < 11; i++) {
      if (data[43 + i] > 1 || data[54 + i] >= modelCounts[i]!) {
        throw const FormatException(
            'Modelo/estado incompatível com o perfil MK300');
      }
    }
  }
}

/// Reconstitui SysEx MIDI fragmentado ou mensagens cruas M-EFCS sobre GATT.
class PedalFramer {
  final bool rawBle;
  final List<int> _buffer = [];
  PedalFramer({this.rawBle = false});
  List<Uint8List> add(List<int> chunk) {
    final result = <Uint8List>[];
    if (!rawBle) {
      for (final b in chunk) {
        if (b >= 248) continue; // MIDI realtime pode intercalar SysEx.
        if (b == 240) {
          _buffer.clear();
          _buffer.add(b);
        } else if (_buffer.isNotEmpty) {
          _buffer.add(b);
          if (b == 247) {
            result.add(Uint8List.fromList(_buffer));
            _buffer.clear();
          }
        }
        if (_buffer.length > 8192) _buffer.clear();
      }
    } else {
      _buffer.addAll(chunk);
      while (_buffer.length >= 3) {
        if (_buffer[0] != 0 || _buffer[1] != 0x59) {
          _buffer.removeAt(0);
          continue;
        }
        final int length;
        if (_buffer[2] == 0 && _buffer.length >= 4 && _buffer[3] == 1) {
          length = 8;
        } else {
          if (_buffer.length < 14) break;
          final payload = _buffer[11] | _buffer[12] << 8 | _buffer[13] << 16;
          if (payload > 4096) {
            _buffer.removeAt(0);
            continue;
          }
          length = 14 + payload + 1;
        }
        if (_buffer.length < length) break;
        final raw = _buffer.sublist(0, length);
        _buffer.removeRange(0, length);
        result.add(Uint8List.fromList([240, ...Mk300Protocol.pack7(raw), 247]));
      }
      if (_buffer.length > 8192) _buffer.clear();
    }
    return result;
  }
}
