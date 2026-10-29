import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'device_transport.dart';
import 'mk300_protocol.dart';

/// MK20 factory records establish this layout, not its bank-write commands.
/// This session has no write/commit/load command and cannot send a preset.
class Mk20Diagnostics {
  static const size = 412, slots = 150;
  final DeviceTransport transport;
  final Duration timeout;
  final List<Map<String, dynamic>> trace = [];
  int _traceBytes = 0;
  bool _busy = false;
  Mk20Diagnostics(this.transport, {this.timeout = const Duration(seconds: 5)});

  void record(String direction, List<int> bytes) {
    if (trace.length >= 96 ||
        bytes.length > 4096 ||
        _traceBytes + bytes.length > 32768) {
      return;
    }
    _traceBytes += bytes.length;
    trace.add({'direction': direction, 'bytes_base64': base64Encode(bytes)});
  }

  static Map<String, dynamic> decode(List<int> image) {
    if (image.length != size ||
        !Mk300Protocol.same(image.sublist(20, 24), [255, 144, 30, 0]) ||
        image.sublist(30, 40).toSet().length != 10 ||
        image.sublist(30, 40).any((b) => b > 9) ||
        image.sublist(40, 50).any((b) => b > 1)) {
      throw const FormatException(
          'Resposta não corresponde ao layout MK20 de 412 bytes.');
    }
    final data = ByteData.sublistView(Uint8List.fromList(image));
    return {
      'name': utf8.decode(image.take(20).takeWhile((b) => b != 0).toList(),
          allowMalformed: true),
      'volume_raw': data.getUint16(24, Endian.little),
      'bpm_raw': data.getUint16(26, Endian.little),
      'chain_raw': image.sublist(30, 40),
      'enabled_raw': image.sublist(40, 50),
      'model_ids_raw': image.sublist(50, 60),
      'image_base64': base64Encode(image),
    };
  }

  Future<Uint8List> _read(int field, int space) async {
    if (!((space == 1 && field == 0) ||
        (space == 0 &&
            field >= 0 &&
            field % size == 0 &&
            field < slots * size))) {
      throw ArgumentError('Consulta MK20 fora dos limites.');
    }
    final response = Completer<Uint8List>();
    final subscription = transport.frames.listen((bytes) {
      record('rx', bytes);
      try {
        final frame = Mk300Protocol.parse(bytes);
        if (!response.isCompleted &&
            frame.cls == 13 &&
            (frame.command == 0x41 || frame.command == 0x101) &&
            frame.field == field &&
            frame.space == space &&
            frame.length == size &&
            frame.payload.length == size) {
          response.complete(frame.payload);
        }
      } on FormatException {/* Preserve unrecognized replies in the trace. */}
    }, onError: (Object error) {
      if (!response.isCompleted) response.completeError(error);
    });
    final timer = Timer(timeout, () {
      if (!response.isCompleted) {
        response
            .completeError(TimeoutException('MK20 não respondeu à leitura.'));
      }
    });
    final pending = response.future;
    final command = Mk300Protocol.read(field, size, space);
    record('tx', command);
    try {
      final results = await Future.wait<Object?>(
          [transport.send(command).then<Object?>((_) => null), pending],
          eagerError: true);
      return results[1] as Uint8List;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<Map<String, dynamic>> run(
      {required int slot,
      required String deviceName,
      required String firmware}) async {
    if (_busy || slot < 1 || slot > slots) {
      throw StateError('Operação em andamento ou slot inválido.');
    }
    _busy = true;
    final reads = <Map<String, dynamic>>[];
    try {
      for (final space in [1, 0]) {
        final field = space == 1 ? 0 : (slot - 1) * size;
        final read = <String, dynamic>{'space': space, 'field': field};
        try {
          final image = await _read(field, space);
          read['decoded'] = decode(image);
        } catch (error) {
          read['error'] = '$error';
        }
        reads.add(read);
      }
      return {
        'format': 'ai-tone-mk20-diagnostic',
        'version': 1,
        'device': 'MK20',
        'transport': 'usb',
        'device_name': deviceName,
        'firmware_reported': firmware,
        'slot': slot,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
        'reads': reads,
        'trace': trace,
        'write_enabled': false,
      };
    } finally {
      _busy = false;
    }
  }
}
