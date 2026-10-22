import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/mk300_pilot.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/screens/mk300_pilot_screen.dart';
import 'mk300_pilot_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Atualização limpa rodadas antigas uma vez, com backup e origem intacta',
      () async {
    final old = PresetStore();
    final original = await fixtures.source();
    await old.save(original);
    await old.saveNewBatch(await Mk300Pilot.generate(original));
    await old.saveNewBatch(await Mk300Pilot.generate(original));
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList('preset_pairs');
    await prefs.remove(PresetStore.pilotCleanupKey); // Simula V1.3.0 instalada.
    final upgraded = PresetStore();
    await upgraded.load();
    expect(upgraded.pairs.map((p) => p.id), [original.id]);
    expect(prefs.getStringList(PresetStore.pilotBackupKey), before);
    expect(prefs.getBool(PresetStore.pilotCleanupKey), true);
    await upgraded.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    final reopened = PresetStore();
    await reopened.load();
    expect(reopened.pairs.length, 4); // Limpeza não se repete.
  });

  test('Cliques repetidos e concorrentes reutilizam IDs e preservam edições',
      () async {
    final store = PresetStore();
    final original = await fixtures.source();
    await store.save(original);
    final first =
        await store.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    final edited =
        first[0].withPreset(first[0].rhythm.copyWith(name: 'Minha edição'));
    await store.save(edited);
    final incoming = await Mk300Pilot.generate(original);
    final results = await Future.wait([
      store.saveOrReusePilotBatch(incoming),
      store.saveOrReusePilotBatch(await Mk300Pilot.generate(original)),
    ]);
    expect(store.pairs.length, 4);
    for (final result in results) {
      expect(result.map((p) => p.id), first.map((p) => p.id));
      expect(result.first.rhythm.name, 'Minha edição');
    }
    expect(store.pairs.where(Mk300Pilot.supports).length, 1);
    await expectLater(Mk300Pilot.generate(first.first), throwsStateError);
  });

  test(
      'Exclusão parcial gera somente o faltante; limpeza explícita libera nova rodada',
      () async {
    final store = PresetStore();
    final original = await fixtures.source();
    await store.save(original);
    final first =
        await store.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    await store.remove(first[1].id);
    final completed =
        await store.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    expect(completed[0].id, first[0].id);
    expect(completed[1].id, isNot(first[1].id));
    expect(completed[2].id, first[2].id);
    expect(store.pairs.length, 4);
    expect(await store.clearPilotCandidates(), 3);
    expect(store.pairs.single.id, original.id);
    expect(await store.clearPilotCandidates(), 0);
    final fresh =
        await store.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    expect(
        fresh
            .map((p) => p.id)
            .toSet()
            .intersection(first.map((p) => p.id).toSet()),
        isEmpty);
  });

  testWidgets(
      'Reabrir mostra candidatos salvos e bloqueia gerar novamente; permite limpar',
      (tester) async {
    final store = PresetStore();
    await tester.runAsync(() async {
      final original = await fixtures.source();
      await store.save(original);
      await store.saveOrReusePilotBatch(await Mk300Pilot.generate(original));
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: Mk300PilotScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Infest R2 A'), findsOneWidget);
    final disabled = tester.widget<FilledButton>(find
        .ancestor(
            of: find.text('Candidatos já existentes'),
            matching:
                find.byWidgetPredicate((widget) => widget is FilledButton))
        .first);
    expect(disabled.onPressed, isNull);
    final cleanup = find.text('Limpar candidatos e recomeçar (3)');
    await tester.ensureVisible(cleanup);
    await tester.tap(cleanup);
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(store.pairs.length, 1);
    expect(find.text('Infest R2 A'), findsNothing);
    expect(find.text('Gerar candidatos na biblioteca'), findsOneWidget);
  });
}
