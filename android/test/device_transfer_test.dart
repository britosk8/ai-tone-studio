import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/services/device/preset_transfer.dart';

class FakeTransport implements DeviceTransport {
  final controller = StreamController<Uint8List>.broadcast();
  Uint8List image;
  Uint8List? staged;
  final writes = <PedalFrame>[];
  bool corruptReadback = false;
  FakeTransport(this.image);
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    final frame = Mk300Protocol.parse(bytes);
    if (frame.cls == 13) {
      final body = Uint8List.fromList(image);
      if (corruptReadback && writes.isNotEmpty) body[100] ^= 1;
      controller.add(
          Mk300Protocol.build(13, 0x41, frame.field, 448, frame.space, body));
    } else {
      writes.add(frame);
      if (frame.space == 0) staged = frame.payload;
      if (frame.space == 15 && staged != null) {
        image = Uint8List.fromList(staged!);
      }
      controller.add(Uint8List.fromList(Mk300Protocol.ack));
    }
  }

  @override
  Future<void> close() => controller.close();
}

Uint8List fixtureImage() {
  final hex = File('../backend/tests/fixtures/mk300-jm-od.hex')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), '');
  return Uint8List.fromList(List.generate(hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
}

Future<Map<int, Map<String, dynamic>>> catalog() async {
  final data =
      jsonDecode(await File('assets/mk300_catalog.json').readAsString()) as Map;
  return {
    for (final b in data['blocks'] as List)
      b['id'] as int: Map<String, dynamic>.from(b as Map)
  };
}

PresetData preset() => const PresetData(
        id: 'test',
        name: 'Áudio completo',
        device: 'MK300',
        role: 'lead',
        analysisConfidence: 'low',
        artist: '',
        songTitle: 'Áudio completo',
        catalogVersion: '0.4.0',
        effectChain: [
          EffectBlock(
              slot: '0',
              effectType: 'amp',
              enabled: true,
              modelId: '0',
              modelName: '1J120_CL',
              parameters: {'Gain': 55},
              parameterSpecs: {'Gain': ParameterSpec(min: 0, max: 100)},
              generatedConfidence: 'low',
              generationRationale: '')
        ]);

void main() {
  test('Vetores capturados do editor e empacotamento de todos os bytes', () {
    expect(Mk300Protocol.build(9, 0x51, 0x1a, 2, 1, [133, 0]), [
      0xf0,
      0,
      0x32,
      9,
      0x51,
      0,
      0,
      0,
      2,
      0x1a,
      0,
      0,
      0,
      0x21,
      0,
      0,
      0,
      5,
      1,
      0x28,
      2,
      0xf7
    ]);
    expect(Mk300Protocol.read(0, 448), [
      0xf0,
      0,
      0x32,
      13,
      0x41,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      0,
      1,
      0x38,
      0,
      0,
      0x2a,
      0,
      0xf7
    ]);
    expect(
        Mk300Protocol.unpack7(
            Mk300Protocol.pack7(List.generate(256, (i) => i))),
        List.generate(256, (i) => i));
    final image = fixtureImage();
    expect(Mk300Protocol.bankWrite(159, image).length, 532);
    expect(Mk300Protocol.bankWrite(159, image).take(18).toList(),
        [240, 0, 50, 9, 65, 28, 0, 0, 2, 64, 44, 4, 0, 0, 56, 0, 0, 74]);
  });
  test('Checksum ruim e ACK parcial são rejeitados', () {
    final bytes = Mk300Protocol.read(0, 448);
    bytes[18] ^= 1;
    expect(() => Mk300Protocol.parse(bytes), throwsFormatException);
    expect(Mk300Protocol.isAck([240, 0, 50, 1]), false);
  });
  test('USB e BLE reconstituem respostas fragmentadas e múltiplas', () {
    final response = Mk300Protocol.build(13, 0x41, 0, 448, 1, fixtureImage());
    final usb = PedalFramer();
    expect(usb.add(response.sublist(0, 30)), isEmpty);
    expect(usb.add([...response.sublist(30), ...Mk300Protocol.ack]).length, 2);
    final raw = Mk300Protocol.unpack7(response.sublist(1, response.length - 1));
    final ble = PedalFramer(rawBle: true);
    expect(ble.add(raw.sublist(0, 25)), isEmpty);
    final result = ble.add(raw.sublist(25));
    expect(result.single, response);
    expect(Mk300Protocol.parse(result.single).payload, fixtureImage());
  });
  test(
      'Só grava após backup e confirmação; preserva campos desconhecidos e lê retorno',
      () async {
    final dir = await Directory.systemTemp.createTemp('tone-transfer-test');
    final original = fixtureImage();
    final transport = FakeTransport(Uint8List.fromList(original));
    final session = Mk300TransferSession(transport, await catalog(),
        deviceLabel: 'fake', pause: (_) async {});
    try {
      await session.probe();
      final prepared = await session.prepare(preset(), 'SOLO TESTE', 159, dir);
      expect(transport.writes, isEmpty);
      expect(File(prepared.backupPath).existsSync(), true);
      expect(prepared.image.sublist(0x14a), original.sublist(0x14a));
      await expectLater(
          session.send(prepared, confirmed: false), throwsStateError);
      expect(transport.writes, isEmpty);
      await session.send(prepared, confirmed: true);
      expect(transport.writes.map((f) => f.space).toList(), [0, 15]);
      expect(transport.writes.first.field, 159 * 448);
      expect(Mk300Protocol.name(transport.image), 'SOLO TESTE');
      await expectLater(
          session.send(prepared, confirmed: true), throwsStateError);
    } finally {
      await session.close();
      await dir.delete(recursive: true);
    }
  });
  test('Alteração do slot e backup corrompido impedem escrita', () async {
    final dir = await Directory.systemTemp.createTemp('tone-transfer-test');
    final transport = FakeTransport(fixtureImage());
    final session = Mk300TransferSession(transport, await catalog(),
        deviceLabel: 'fake', pause: (_) async {});
    try {
      await session.probe();
      final prepared = await session.prepare(preset(), 'TESTE', 1, dir);
      transport.image[90] ^= 1;
      await expectLater(
          session.send(prepared, confirmed: true), throwsStateError);
      expect(transport.writes, isEmpty);
      transport.image = fixtureImage();
      await File(prepared.backupPath).writeAsString(
          jsonEncode({'image_base64': base64Encode(Uint8List(448))}));
      await expectLater(
          session.send(prepared, confirmed: true), throwsStateError);
      expect(transport.writes, isEmpty);
    } finally {
      await session.close();
      await dir.delete(recursive: true);
    }
  });
  test('Não relata sucesso se leitura não corresponde à imagem enviada',
      () async {
    final dir = await Directory.systemTemp.createTemp('tone-transfer-test');
    final transport = FakeTransport(fixtureImage());
    final session = Mk300TransferSession(transport, await catalog(),
        deviceLabel: 'fake', pause: (_) async {});
    try {
      await session.probe();
      final prepared = await session.prepare(preset(), 'TESTE', 1, dir);
      transport.corruptReadback = true;
      await expectLater(
          session.send(prepared, confirmed: true), throwsStateError);
      expect(transport.writes.length, 2);
      expect(File(prepared.backupPath).existsSync(), true);
    } finally {
      await session.close();
      await dir.delete(recursive: true);
    }
  });
  test('MK20, catálogo antigo e nomes fora do limite não são gravados',
      () async {
    final transport = FakeTransport(fixtureImage());
    final session =
        Mk300TransferSession(transport, await catalog(), deviceLabel: 'fake');
    final old =
        PresetData.fromJson(preset().toJson()..['catalog_version'] = '0.3.0');
    expect(() => session.buildImage(old, 'TESTE', fixtureImage()),
        throwsStateError);
    expect(
        () => Mk300TransferSession.validateName('áudio'), throwsArgumentError);
    expect(
        () => Mk300TransferSession.validateName('A' * 20), throwsArgumentError);
    final other = PresetData.fromJson(preset().toJson()..['device'] = 'MK20');
    expect(() => session.buildImage(other, 'TESTE', fixtureImage()),
        throwsStateError);
    await session.close();
  });
  test(
      'Presets reais do compilador são convertidos preservando a cadeia e cada parâmetro',
      () async {
    final pair = PresetPair.fromJson(jsonDecode(
        await File('test/fixtures/generated_mk300_pair.json')
            .readAsString()) as Map<String, dynamic>);
    final transport = FakeTransport(fixtureImage());
    final source = await catalog();
    final session =
        Mk300TransferSession(transport, source, deviceLabel: 'fake');
    const ids = {
      'noise_gate': 2,
      'compressor': 1,
      'drive': 3,
      'amp': 4,
      'cabinet': 5,
      'modulation': 7,
      'delay': 8,
      'reverb': 9
    };
    for (final preset in [pair.rhythm, pair.lead]) {
      final image = session.buildImage(preset, 'TESTE', fixtureImage());
      final data = ByteData.sublistView(image);
      expect(image.sublist(32, 32 + preset.effectChain.length),
          preset.effectChain.map((b) => ids[b.effectType]).toList());
      for (final block in preset.effectChain) {
        final blockId = ids[block.effectType]!;
        expect(image[54 + blockId], int.parse(block.modelId));
        final models = source[blockId]!['models'] as List;
        final knobs = List<String>.from(
            models[int.parse(block.modelId)]['knobs'] as List);
        for (final entry in block.parameters.entries) {
          expect(
              data.getInt16(66 + 24 * blockId + 2 * knobs.indexOf(entry.key),
                  Endian.little),
              entry.value.toInt());
        }
      }
    }
    await session.close();
  });
}
