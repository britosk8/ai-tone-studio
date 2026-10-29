import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/services/device/mk20_diagnostics.dart';

Uint8List mk20Image() {
  final image = Uint8List(412);
  image.setRange(0, 7, 'MK20 QA'.codeUnits);
  image.setRange(20, 24, [255, 144, 30, 0]);
  image.setRange(30, 40, List.generate(10, (i) => i));
  image.setRange(40, 50, List.generate(10, (i) => i % 2));
  return image;
}

class ReadOnlyPedal implements DeviceTransport {
  final controller = StreamController<Uint8List>.broadcast();
  final requests = <PedalFrame>[];
  bool respond = true, corrupt = false, failSend = false;
  int replyCommand = 0x41;
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    final frame = Mk300Protocol.parse(bytes);
    if (frame.cls != 13 || frame.command != 0x41 || frame.payload.isNotEmpty) {
      throw StateError('Unexpected write command');
    }
    requests.add(frame);
    if (failSend) throw StateError('USB desconectada');
    if (respond) {
      final response = Mk300Protocol.build(
          13, replyCommand, frame.field, 412, frame.space, mk20Image());
      if (corrupt) response[20] ^= 1;
      controller.add(response);
    }
  }

  @override
  Future<void> close() => controller.close();
}

void main() {
  test(
      'MK20 lê ativo e slot 150 sem qualquer escrita e preserva imagem completa',
      () async {
    final pedal = ReadOnlyPedal();
    final report = await Mk20Diagnostics(pedal)
        .run(slot: 150, deviceName: 'USB MK20', firmware: 'Não sei');
    expect(pedal.requests.map((r) => r.field), [0, 61388]);
    expect(pedal.requests.map((r) => r.space), [1, 0]);
    expect(pedal.requests.every((r) => r.length == 412), isTrue);
    expect(report['write_enabled'], isFalse);
    for (final read in report['reads'] as List) {
      expect(read['decoded']['name'], 'MK20 QA');
      expect(base64Decode(read['decoded']['image_base64']), mk20Image());
    }
    await pedal.close();
  });
  test('Timeout, checksum inválido e USB desconectada ficam no diagnóstico',
      () async {
    for (final mode in ['silent', 'corrupt', 'disconnect']) {
      final pedal = ReadOnlyPedal()
        ..respond = mode != 'silent'
        ..corrupt = mode == 'corrupt'
        ..failSend = mode == 'disconnect';
      final report = await Mk20Diagnostics(pedal,
              timeout: const Duration(milliseconds: 10))
          .run(slot: 1, deviceName: 'USB', firmware: 'V085');
      expect(
          (report['reads'] as List)
              .every((r) => r['decoded'] == null && r['error'] != null),
          isTrue);
      expect(
          (report['trace'] as List).where((e) => e['direction'] == 'tx').length,
          2);
      await pedal.close();
    }
  });
  test('Resposta de leitura em bloco 01 02 também é aceita', () async {
    final pedal = ReadOnlyPedal()..replyCommand = 0x101;
    final report = await Mk20Diagnostics(pedal)
        .run(slot: 1, deviceName: 'USB', firmware: '?');
    expect(
        (report['reads'] as List).every((r) => r['decoded'] != null), isTrue);
    await pedal.close();
  });
  test('Não aceita 448 bytes ou slots MK300 151 a 160', () async {
    expect(() => Mk20Diagnostics.decode(Uint8List(448)), throwsFormatException);
    final pedal = ReadOnlyPedal();
    await expectLater(
        Mk20Diagnostics(pedal).run(slot: 151, deviceName: 'USB', firmware: '?'),
        throwsStateError);
    expect(pedal.requests, isEmpty);
    await pedal.close();
  });
}
