import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/services/device/preset_transfer.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/pedal_reference.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/screens/pedal_reference_screen.dart';
import 'device_transfer_test.dart' as hardware;
import 'library_transfer_ui_test.dart' as fixtures;

class ReadOnlyTransport extends hardware.FakeTransport {
  final reads = <PedalFrame>[];
  ReadOnlyTransport(super.image);
  @override
  Future<void> send(Uint8List data) async {
    final frame = Mk300Protocol.parse(data);
    expect(frame.cls, 13);
    reads.add(frame);
    await super.send(data);
  }
}

PedalReference snapshot({int slot = 1, Uint8List? image}) => PedalReference(
    slot: slot,
    connection: 'usb:test',
    capturedAt: '2026-10-22T00:00:00Z',
    image: image ?? hardware.fixtureImage());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'Importa slots 1/160 por leitura de flash, sem seleção, escrita ou commit',
      () async {
    final transport = ReadOnlyTransport(hardware.fixtureImage());
    final session = Mk300TransferSession(transport, await hardware.catalog(),
        deviceLabel: 'teste');
    await expectLater(session.readSlot(0), throwsStateError);
    expect(transport.reads, isEmpty);
    await session.probe();
    final first = await session.readSlot(0);
    final last = await session.readSlot(159);
    expect(first, hardware.fixtureImage());
    expect(last, first);
    expect(transport.reads.last.field, 159 * 448);
    expect(transport.reads.last.space, 0);
    expect(transport.writes, isEmpty);
    await expectLater(session.readSlot(-1), throwsStateError);
    await expectLater(session.readSlot(160), throwsStateError);
    transport.image[447] = 0;
    await expectLater(session.readSlot(0), throwsFormatException);
    await session.close();
  });

  test(
      'Decodifica cadeia, estados, volume e EQ negativo sem conversões inventadas',
      () async {
    final image = hardware.fixtureImage();
    final bytes = ByteData.sublistView(image);
    image[54 + 6] = 0; // Guitar EQ 6
    image[43 + 6] = 1;
    bytes.setInt16(66 + 24 * 6, -2, Endian.little);
    bytes.setUint16(24, 60, Endian.little);
    final reference = snapshot(image: image).decode(await hardware.catalog());
    expect(reference.effectChain.length, 11);
    expect(reference.effectChain.map((b) => int.parse(b.slot)),
        List.generate(11, (i) => i));
    expect(
        reference.effectChain
            .singleWhere((b) => b.effectType == 'eq')
            .parameters['100Hz'],
        -2);
    expect(reference.presetVolume, 60);
    expect(reference.role, 'reference');
    final roundtrip = PedalReference.fromJson(snapshot(image: image).toJson());
    expect(roundtrip.image, image);
    image[447] = 0;
    await expectLater(
        Future(() async =>
            snapshot(image: image).decode(await hardware.catalog())),
        throwsFormatException);
  });

  test(
      'Reimportar substitui referência por análise/função sem alterar biblioteca',
      () async {
    final store = PresetStore();
    final original = fixtures.pair('Musica');
    await store.save(original);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList('preset_pairs');
    final repository = PedalReferenceRepository();
    await repository.save(original.id, 'rhythm', snapshot());
    await repository.save(original.id, 'rhythm', snapshot(slot: 160));
    await repository.save(original.id, 'lead', snapshot(slot: 10));
    expect((await repository.load(original.id, 'rhythm'))!.slot, 160);
    expect((await repository.load(original.id, 'lead'))!.slot, 10);
    expect(await repository.load('Outra musica', 'rhythm'), isNull);
    expect(
        prefs
            .getKeys()
            .where((k) => k.startsWith('pedal_reference_v1:'))
            .length,
        2);
    expect(prefs.getStringList('preset_pairs'), before);
    expect(store.pairs.length, 1);
  });

  test(
      'Comparação é de controles e modelos, sem modificar preset ou atribuir fidelidade',
      () async {
    final reference = snapshot().decode(await hardware.catalog());
    expect(
        comparePedalConfiguration(reference, reference).where((r) => r.changed),
        isEmpty);
    final generated = fixtures.pair('Musica').rhythm;
    final before = generated.toJson().toString();
    final differences = comparePedalConfiguration(generated, reference);
    expect(differences.where((r) => r.changed), isNotEmpty);
    expect(differences.any((r) => r.label == 'Amplificador • modelo'), true);
    expect(generated.toJson().toString(), before);
  });

  testWidgets(
      'USB importa e compara no app, persiste sem duplicar nem emitir escrita',
      (tester) async {
    final store = PresetStore();
    await store.save(fixtures.pair('Musica'));
    final messenger = tester.binding.defaultBinaryMessenger;
    const eventControl = MethodChannel('ai_tone/device_events');
    final commands = <PedalFrame>[];
    messenger.setMockMethodCallHandler(eventControl, (call) async => null);
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel,
        (call) async {
      if (call.method == 'listUsb') {
        return [
          {'id': 'usb1', 'name': 'MK300'}
        ];
      }
      if (call.method == 'connect') return {'name': 'MK300'};
      if (call.method == 'send') {
        final frame = Mk300Protocol.parse(
            List<int>.from((call.arguments as Map)['bytes'] as List));
        commands.add(frame);
        expect(frame.cls, 13);
        final response = Mk300Protocol.build(
            13, 0x41, frame.field, 448, frame.space, hardware.fixtureImage());
        await messenger.handlePlatformMessage(
            'ai_tone/device_events',
            const StandardMethodCodec()
                .encodeSuccessEnvelope({'type': 'data', 'bytes': response}),
            (_) {});
      }
      return null;
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child:
            const MaterialApp(home: PedalReferenceScreen(pairId: 'Musica'))));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar MK300 por USB'));
    await tester.pumpAndSettle();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    final slot = find.widgetWithText(TextField, 'Slot para importar (1–160)');
    await tester.enterText(slot, '160');
    for (var i = 0; i < 2; i++) {
      await tester.scrollUntilVisible(
          find.text('Importar preset do pedal'), 200,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      final button = find
          .ancestor(
              of: find.text('Importar preset do pedal'),
              matching: find.byWidgetPredicate((w) => w is FilledButton))
          .first;
      await tester.runAsync(() async {
        tester.widget<FilledButton>(button).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('importado como referência'), findsWidgets);
      expect(find.textContaining('diferenças de configuração'), findsOneWidget);
    }
    expect(
        commands.length, 6); // Duas sondagens (2 reads) + dois reads de slot.
    expect(commands.last.field, 159 * 448);
    expect(store.pairs.single.rhythm.name, 'Musica-Base');
    expect(
        (await PedalReferenceRepository().load('Musica', 'rhythm'))!.slot, 160);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
    messenger.setMockMethodCallHandler(eventControl, null);
  });
}
