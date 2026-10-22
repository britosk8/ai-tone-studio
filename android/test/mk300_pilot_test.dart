import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/mk300_pilot.dart';
import 'package:ai_tone_studio/services/preset_import.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/device/preset_transfer.dart';
import 'package:ai_tone_studio/screens/mk300_pilot_screen.dart';
import 'device_transfer_test.dart' as hardware;

Future<PresetPair> source() => PresetImport.decode(
    File('test/fixtures/infest_mk300_piloto_r1.json').readAsStringSync());

EffectBlock block(PresetPair p, String type) =>
    p.rhythm.effectChain.singleWhere((b) => b.effectType == type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Candidatos diferem somente em AMP ou CAB e não modificam a origem',
      () async {
    final original = await source();
    final snapshot = original.exportJson().toString();
    final candidates = await Mk300Pilot.generate(original);
    expect(candidates.length, 3);
    final a = candidates[0], b = candidates[1], c = candidates[2];
    expect(block(a, 'amp').modelId, '97');
    expect(block(b, 'amp').modelId, '99');
    expect(block(c, 'cabinet').modelId, '11');
    expect(block(a, 'cabinet').toJson(), block(b, 'cabinet').toJson());
    expect(block(a, 'amp').toJson(), block(c, 'amp').toJson());
    expect(block(a, 'amp').parameters, block(b, 'amp').parameters);
    expect(block(a, 'drive').parameters, block(b, 'drive').parameters);
    expect(block(a, 'drive').parameters['Gain'], 10);
    expect(block(a, 'drive').parameters['Level'], 80);
    expect(block(a, 'cabinet').parameters['Low Cut'],
        block(original, 'cabinet').parameters['Low Cut']);
    expect(block(a, 'cabinet').parameters['High Cut'],
        block(original, 'cabinet').parameters['High Cut']);
    expect(original.exportJson().toString(), snapshot);
    expect(candidates.map((p) => p.id).toSet().length, 3);
    expect(candidates.every((p) => p.id != original.id), true);
    for (final p in candidates) {
      expect(p.rhythm.sourceFileName, original.rhythm.sourceFileName);
      expect(p.lead.effectChain.map((b) => b.toJson()).toList(),
          original.lead.effectChain.map((b) => b.toJson()).toList());
      expect(p.lead.id, isNot(original.lead.id));
      expect(p.rhythm.analysisConfidence, 'low');
      expect(p.analysis.gainCharacter, 'unknown');
    }
  });

  test(
      'Todas as imagens escrevem knobs completos e desativam efeitos anteriores',
      () async {
    final transport = hardware.FakeTransport(hardware.fixtureImage());
    final session = Mk300TransferSession(transport, await hardware.catalog(),
        deviceLabel: 'offline');
    final candidates = await Mk300Pilot.generate(await source());
    for (final p in candidates) {
      final target = hardware.fixtureImage();
      target.fillRange(43, 54, 1); // Slot com todos os blocos ativos.
      final image = session.buildImage(p.rhythm, p.rhythm.name, target);
      final data = ByteData.sublistView(image);
      expect(data.getUint16(24, Endian.little), 60);
      expect(data.getInt16(28, Endian.little), 0);
      for (var id = 0; id < 11; id++) {
        expect(image[43 + id], [2, 3, 4, 5].contains(id) ? 1 : 0);
      }
      expect(data.getInt16(66 + 24 * 3, Endian.little), 10);
      expect(data.getInt16(66 + 24 * 3 + 2, Endian.little), 80);
      expect(data.getInt16(66 + 24 * 4, Endian.little), 56);
      expect(image.sublist(32, 36), [2, 3, 4, 5]);
      expect(image.sublist(310), target.sublist(310));
    }
    expect(transport.writes, isEmpty); // Gerar/preparar não transmite.
    await session.close();
  });

  test(
      'Geração, persistência e exportação mantêm proveniência e versões antigas',
      () async {
    final store = PresetStore();
    final original = await source();
    await store.save(original);
    final candidates = await Mk300Pilot.generate(original);
    await store.saveNewBatch(candidates);
    final reloaded = PresetStore();
    await reloaded.load();
    expect(reloaded.pairs.length, 4);
    expect(reloaded.pairs.singleWhere((p) => p.id == original.id).rhythm.name,
        'Infest Base R1');
    final candidate = reloaded.pairs.first;
    expect(candidate.rhythm.generationMetadata['source_pair_id'], original.id);
    expect(candidate.rhythm.copyWith(name: 'Novo nome').generationMetadata,
        candidate.rhythm.generationMetadata);
    expect(candidate.rhythm.presetVolume, 60);
    await expectLater(store.saveNewBatch(candidates), throwsStateError);
    expect(store.pairs.length, 4);
  });

  test('Cortes ausentes ou fora do catálogo não autorizam candidatos',
      () async {
    final original = await source();
    for (final values in [
      <String, double>{},
      {'Low Cut': 80.0, 'High Cut': 7500.0}
    ]) {
      final broken = original.withPreset(original.rhythm.copyWith(effectChain: [
        for (final b in original.rhythm.effectChain)
          b.effectType == 'cabinet' ? b.copyWith(parameters: values) : b
      ]));
      await expectLater(Mk300Pilot.generate(broken), throwsA(anything));
    }
  });

  testWidgets('Gera no app, salva os três e abre envio da base selecionada',
      (tester) async {
    final store = PresetStore();
    await tester.runAsync(() async => store.save(await source()));
    Map? route;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
          home: const Mk300PilotScreen(),
          onGenerateRoute: (settings) {
            route = settings.arguments as Map;
            return MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Text('Envio selecionado')));
          }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar candidatos na biblioteca'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(store.pairs.length, 4);
    expect(find.text('Infest R2 A'), findsOneWidget);
    final send = find.text('Enviar base para a MK300').first;
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(route?['pair_id'], store.pairs.first.id);
    expect(route?['role'], 'rhythm');
    expect(find.text('Envio selecionado'), findsOneWidget);
  });
}
