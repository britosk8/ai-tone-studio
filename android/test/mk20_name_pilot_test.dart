import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/services/device/mk20_name_pilot.dart';
import 'mk20_diagnostics_test.dart' show mk20Image;

class PilotPedal implements DeviceTransport {
  final framesController = StreamController<Uint8List>.broadcast();
  Uint8List image = mk20Image();
  Uint8List? staged;
  final writes = <PedalFrame>[];
  bool loseBankAck = false, ignoreCommit = false, loseCommitAck = false;
  @override
  Stream<Uint8List> get frames => framesController.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    final frame = Mk300Protocol.parse(bytes);
    if (frame.cls == 13) {
      framesController.add(
          Mk300Protocol.build(13, 0xD21, frame.field, 412, frame.space, image));
    } else {
      writes.add(frame);
      if (frame.space == 0) {
        expect(frame.field, 61388);
        expect(frame.length, 412);
        expect(frame.command, 0xD21);
        staged = frame.payload;
        if (loseBankAck) return;
      } else {
        expect(frame.space, 15);
        if (!ignoreCommit) image = Uint8List.fromList(staged!);
        if (loseCommitAck) return;
      }
      framesController.add(Uint8List.fromList(Mk300Protocol.ack));
    }
  }

  @override
  Future<void> close() => framesController.close();
}

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('mk20-name-');
  });
  tearDown(() {
    directory.deleteSync(recursive: true);
  });
  Mk20NamePilot session(PilotPedal pedal) => Mk20NamePilot(pedal,
      pause: (_) async {}, timeout: const Duration(milliseconds: 15));

  test(
      'Backup, nome e restauração preservam todos os outros bytes; sem repetir escrita',
      () async {
    final pedal = PilotPedal();
    final original = Uint8List.fromList(pedal.image);
    final pilot = session(pedal);
    final file = await pilot.prepare(directory, deviceName: 'MK20');
    expect(pedal.writes, isEmpty);
    final stored = await Mk20NamePilot.load(file);
    expect(base64Decode(stored['original_base64']), original);
    final renamed = await pilot.perform(file, restore: false, confirmed: true);
    expect(renamed['status'], 'confirmed');
    expect(pedal.writes.length, 2);
    expect(Mk300Protocol.name(pedal.image), Mk20NamePilot.testName);
    expect(pedal.image.sublist(20), original.sublist(20));
    await expectLater(
        pilot.perform(file, restore: false, confirmed: true), throwsStateError);
    expect(pedal.writes.length, 2);
    // A fresh session simulates reconnecting/reopening the app.
    final restored =
        await session(pedal).perform(file, restore: true, confirmed: true);
    expect(restored['status'], 'confirmed');
    expect(pedal.image, original);
    expect(pedal.writes.length, 4);
    expect(File('${directory.path}/last_result.json').existsSync(), isTrue);
    await pedal.close();
  });

  test('Sem confirmação, slot alterado ou backup adulterado não gravam',
      () async {
    final pedal = PilotPedal();
    final pilot = session(pedal);
    final file = await pilot.prepare(directory, deviceName: 'MK20');
    await expectLater(pilot.perform(file, restore: false, confirmed: false),
        throwsStateError);
    pedal.image[100] ^= 1;
    final changed = await pilot.perform(file, restore: false, confirmed: true);
    expect(changed['status'], 'not_attempted');
    expect(pedal.writes, isEmpty);
    final backup =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final named = base64Decode(backup['named_base64']);
    named[120] ^= 1;
    backup['named_base64'] = base64Encode(named);
    await file.writeAsString(jsonEncode(backup));
    await expectLater(pilot.perform(file, restore: false, confirmed: true),
        throwsFormatException);
    expect(pedal.writes, isEmpty);
    await pedal.close();
  });

  test(
      'ACK perdido impede commit e nova tentativa; restauração reconhece original',
      () async {
    final pedal = PilotPedal()..loseBankAck = true;
    final pilot = session(pedal);
    final file = await pilot.prepare(directory, deviceName: 'MK20');
    final report = await pilot.perform(file, restore: false, confirmed: true);
    expect(report['status'], 'unconfirmed');
    expect(pedal.writes.length, 1);
    await expectLater(
        pilot.perform(file, restore: false, confirmed: true), throwsStateError);
    expect(
        (await pilot.perform(file, restore: true, confirmed: true))['status'],
        'already_original');
    expect(pedal.writes.length, 1);
    await pedal.close();
  });

  test('ACKs sem imagem de retorno igual não são sucesso nem repetem gravação',
      () async {
    final pedal = PilotPedal()..ignoreCommit = true;
    final pilot = session(pedal);
    final file = await pilot.prepare(directory, deviceName: 'MK20');
    final report = await pilot.perform(file, restore: false, confirmed: true);
    expect(report['status'], 'unconfirmed');
    expect(report['error'], contains('não confirmada'));
    expect(pedal.writes.length, 2);
    await pedal.close();
  });

  test(
      'Envelope coincide com cabeçalho bruto do editor e inclui bits baixos de 412',
      () {
    final bytes = Mk20NamePilot.bankWrite(Mk20NamePilot.renamed(mk20Image()));
    expect(bytes.take(17), [
      0xf0,
      0,
      0x32,
      9,
      0x21,
      0x1a,
      0,
      0,
      2,
      0x4c,
      0x5f,
      3,
      0,
      0x40,
      0x33,
      0,
      0
    ]);
    final raw = Mk300Protocol.unpack7(bytes.sublist(1, bytes.length - 1));
    expect(raw.take(14),
        [0, 0x59, 0x22, 0xa4, 1, 0, 4, 0xcc, 0xef, 0, 0, 0x9c, 1, 0]);
    expect(bytes.length, 490);
  });

  test('ACK de restauração perdido pode ser conferido sem nova escrita',
      () async {
    final pedal = PilotPedal();
    final pilot = session(pedal);
    final file = await pilot.prepare(directory, deviceName: 'MK20');
    await pilot.perform(file, restore: false, confirmed: true);
    pedal.loseCommitAck = true;
    expect(
        (await pilot.perform(file, restore: true, confirmed: true))['status'],
        'unconfirmed');
    final count = pedal.writes.length;
    expect(
        (await pilot.perform(file, restore: true, confirmed: true))['status'],
        'already_original');
    expect(pedal.writes.length, count);
    expect((await Mk20NamePilot.load(file))['restore_verified'], isTrue);
    await pedal.close();
  });
  test(
      'Restaura backup antigo com nome truncado em 16 caracteres e preserva controles',
      () async {
    final pedal = PilotPedal();
    final original = Uint8List.fromList(pedal.image);
    final file = await session(pedal).prepare(directory, deviceName: 'MK20');
    final backup =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final named = Uint8List.fromList(original)..fillRange(0, 20, 0);
    named.setRange(
        0, Mk20NamePilot.legacyName.length, Mk20NamePilot.legacyName.codeUnits);
    backup['named_base64'] = base64Encode(named);
    backup['rename_attempted'] = true;
    await file.writeAsString(jsonEncode(backup));
    pedal.image = Uint8List.fromList(named)..[16] = 0;
    final restored =
        await session(pedal).perform(file, restore: true, confirmed: true);
    expect(restored['status'], 'confirmed');
    expect(pedal.image, original);
    expect(pedal.writes.length, 2);
    await pedal.close();
  });

  test('Nome antigo truncado não libera restauração se outro byte mudou',
      () async {
    final pedal = PilotPedal();
    final file = await session(pedal).prepare(directory, deviceName: 'MK20');
    final backup =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final named = Uint8List.fromList(pedal.image)..fillRange(0, 20, 0);
    named.setRange(
        0, Mk20NamePilot.legacyName.length, Mk20NamePilot.legacyName.codeUnits);
    backup['named_base64'] = base64Encode(named);
    backup['rename_attempted'] = true;
    await file.writeAsString(jsonEncode(backup));
    pedal.image = Uint8List.fromList(named)
      ..[16] = 0
      ..[100] = 5;
    final result =
        await session(pedal).perform(file, restore: true, confirmed: true);
    expect(result['status'], 'not_attempted');
    expect(pedal.writes, isEmpty);
    await pedal.close();
  });
}
