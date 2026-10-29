import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/services/device/mk20_transfer.dart';

Uint8List originalImage() {
  final image = Uint8List(412);
  image.setRange(0, 8, 'ORIGINAL'.codeUnits);
  image.setRange(20, 24, [255, 144, 30, 0]);
  image.setRange(30, 40, List.generate(10, (i) => i));
  for (var i = 300; i < 412; i++) {
    image[i] = i % 256;
  }
  return image;
}

Map<String, dynamic> catalog() => Map<String, dynamic>.from(
    jsonDecode(File('assets/mk20_catalog.json').readAsStringSync()));
Map<String, dynamic> presetJson() => {
      'id': 'mk20-qa',
      'name': 'MK20 QA',
      'device': 'MK20',
      'catalog_version': '0.4.0',
      'role': 'rhythm',
      'preset_volume': 60,
      'analysis_confidence': 'low',
      'effect_chain': [
        {
          'effect_type': 'noise_gate',
          'model_id': '0',
          'model_name': 'AI Gate',
          'parameters': {'Gate': 40, 'Bias': 50}
        },
        {
          'effect_type': 'drive',
          'model_id': '21',
          'model_name': '22TS-9',
          'parameters': {
            'Gain': 10,
            'Level': 80,
            'Bass': 42,
            'Middle': 58,
            'Treble': 52,
            'Reso': 0,
            'Pres': 50,
            'Bright': 60
          }
        },
        {
          'effect_type': 'amp',
          'model_id': '69',
          'model_name': '70OD2_meas',
          'parameters': {
            'Gain': 56,
            'Level': 60,
            'Bass': 58,
            'Middle': 49,
            'Treble': 60,
            'Reso': 35,
            'Pres': 58,
            'Bright': 45
          }
        },
        {
          'effect_type': 'cabinet',
          'model_id': '53',
          'model_name': '54MbSOSS4t412',
          'parameters': {'Level': 80, 'Low Cut': 80, 'High Cut': 7500}
        },
        {
          'effect_type': 'eq',
          'model_id': '0',
          'model_name': 'Guitar EQ 6',
          'parameters': {
            '100Hz': 2,
            '200Hz': 0,
            '400Hz': -1.5,
            '800Hz': 1,
            '1.6kHz': 2.5,
            '3.2kHz': .5
          }
        }
      ]
    };

class Pedal implements DeviceTransport {
  final controller = StreamController<Uint8List>.broadcast();
  Uint8List image = originalImage();
  Uint8List? staged;
  final writes = <PedalFrame>[];
  bool ack = true, corrupt = false;
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> send(Uint8List command) async {
    final f = Mk300Protocol.parse(command);
    if (f.cls == 13) {
      final body = Uint8List.fromList(image);
      if (corrupt && writes.isNotEmpty) {
        body[120] ^= 1;
      }
      controller
          .add(Mk300Protocol.build(13, 0xD21, f.field, 412, f.space, body));
    } else {
      writes.add(f);
      if (f.space == 0) {
        staged = Uint8List.fromList(f.payload);
      }
      if (f.space == 15 && staged != null) {
        image = Uint8List.fromList(staged!);
      }
      if (ack) {
        controller.add(Uint8List.fromList(Mk300Protocol.ack));
      }
    }
  }

  @override
  Future<void> close() => controller.close();
}

Mk20TransferSession session(Pedal pedal) =>
    Mk20TransferSession(pedal, catalog(),
        deviceLabel: 'USB QA',
        pause: (_) async {},
        timeout: const Duration(milliseconds: 15));
void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mk20-full-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('MK20: índices Infest, EQ ×2, corte alto ÷100 e cauda preservada',
      () async {
    final pedal = Pedal(), s = session(Pedal());
    final original = originalImage(),
        image = s.buildImage(PresetData.fromJson(presetJson()), 'QA', original);
    final bytes = ByteData.sublistView(image);
    expect(image.sublist(50, 56), [0, 0, 21, 69, 53, 0]);
    expect(bytes.getInt16(60 + 24 * 3, Endian.little), 56);
    expect(bytes.getInt16(60 + 24 * 4 + 4, Endian.little), 75);
    expect(
        List.generate(
            6, (k) => bytes.getInt16(60 + 24 * 5 + k * 2, Endian.little)),
        [4, 0, -3, 2, 5, 1]);
    expect(image.sublist(300), original.sublist(300));
    expect(image.sublist(40, 50), [0, 1, 1, 1, 1, 1, 0, 0, 0, 0]);
    expect(image.sublist(30, 40), [1, 2, 3, 4, 5, 0, 6, 7, 8, 9]);
    await s.close();
    await pedal.close();
  });
  test(
      'backup, gravação completa, recuperação após reinício e restauração exata',
      () async {
    final pedal = Pedal(), s = session(Pedal());
    await s.close();
    final live = session(pedal);
    await live.probe();
    final t = await live.prepare(
        PresetData.fromJson(presetJson()), 'QA INFEST', 149, directory);
    expect(pedal.writes, isEmpty);
    await live.send(t, confirmed: true);
    expect(pedal.image, t.image);
    expect(pedal.writes.length, 2);
    expect(pedal.writes[0].command, 0xD21);
    expect(pedal.writes[0].field, 149 * 412);
    expect(pedal.writes[1].space, 15);
    expect(live.lastReport!['operation'], 'send');
    // New identity after process restart, using the archived original and target.
    final recoveredSession = session(pedal);
    await recoveredSession.probe();
    final recovered = (await recoveredSession.recover(directory))!;
    expect(recovered.attempted, isTrue);
    await recoveredSession.restore(recovered, confirmed: true);
    expect(pedal.image, originalImage());
    expect(pedal.writes.length, 4);
    await recoveredSession.restore(recovered,
        confirmed: true); // Already original: read only.
    expect(pedal.writes.length, 4);
    await recoveredSession.close();
  });
  test('sem ACK: nunca repete escrita nem envia commit', () async {
    final pedal = Pedal(), s = session(Pedal());
    await s.close();
    final live = session(pedal);
    await live.probe();
    final t = await live.prepare(
        PresetData.fromJson(presetJson()), 'QA', 149, directory);
    pedal.ack = false;
    await expectLater(
        live.send(t, confirmed: true), throwsA(isA<TimeoutException>()));
    await expectLater(live.send(t, confirmed: true), throwsStateError);
    final restarted = session(pedal);
    await restarted.probe();
    final recovered = (await restarted.recover(directory))!;
    await expectLater(
        restarted.send(recovered, confirmed: true), throwsStateError);
    expect(pedal.writes.length, 1);
    await live.close();
  });
  test('leitura divergente impede sucesso e escrita não se repete', () async {
    final pedal = Pedal(), live = session(Pedal());
    await live.close();
    final s = session(pedal);
    await s.probe();
    final t = await s.prepare(
        PresetData.fromJson(presetJson()), 'QA', 149, directory);
    pedal.corrupt = true;
    await expectLater(s.send(t, confirmed: true), throwsStateError);
    expect(pedal.writes.length, 2);
    expect(s.lastReport!['error'], isNotNull);
    await s.close();
  });
  test('slot 76, cancelamento, backup alterado e slot modificado não gravam',
      () async {
    final pedal = Pedal(), s = session(Pedal());
    await s.close();
    final live = session(pedal);
    await live.probe();
    final preset = PresetData.fromJson(presetJson());
    await expectLater(
        live.prepare(preset, 'QA', 75, directory), throwsStateError);
    final t = await live.prepare(preset, 'QA', 149, directory);
    await expectLater(live.send(t, confirmed: false), throwsStateError);
    pedal.image[120] ^= 1;
    await expectLater(live.send(t, confirmed: true), throwsStateError);
    pedal.image[120] ^= 1;
    final backup = jsonDecode(await File(t.backupPath).readAsString());
    backup['image_base64'] = base64Encode(Uint8List(412));
    await File(t.backupPath).writeAsString(jsonEncode(backup));
    await expectLater(live.send(t, confirmed: true), throwsStateError);
    expect(pedal.writes, isEmpty);
    await live.close();
  });
  test(
      'catálogo antigo, nomes/IDs errados, limites forjados e escalas inválidas bloqueiam',
      () async {
    final live = session(Pedal());
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (p) => p['catalog_version'] = '0.3.0',
      (p) => (p['effect_chain'][2] as Map)['model_id'] = '70',
      (p) => (p['effect_chain'][2]['parameters'] as Map)['Gain'] = 101,
      (p) => (p['effect_chain'][3]['parameters'] as Map)['High Cut'] = 7501,
      (p) => (p['effect_chain'][4]['parameters'] as Map)['100Hz'] = 1.25,
      (p) => (p['effect_chain'][2] as Map)['enabled'] = false,
      (p) => (p['effect_chain'] as List).add(p['effect_chain'][2]),
    ]) {
      final p = presetJson();
      mutate(p);
      expect(
          () => live.buildImage(PresetData.fromJson(p), 'QA', originalImage()),
          throwsStateError);
    }
    expect(
        () => live.buildImage(PresetData.fromJson(presetJson()),
            'ABCDEFGHIJKLMNOPQ', originalImage()),
        throwsArgumentError);
    await live.close();
  });
}
