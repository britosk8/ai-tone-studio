import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/preset_archive.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/screens/archived_presets_screen.dart';
import 'package:ai_tone_studio/screens/home_screen.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'library_transfer_ui_test.dart' show LocalApi;

PresetPair pair(String id) {
  final raw = jsonDecode(
          File('test/fixtures/generated_mk300_pair.json').readAsStringSync())
      as Map<String, dynamic>;
  raw['id'] = id;
  return PresetPair.fromJson(raw);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
      {PresetStore.pilotCleanupKey: true}));
  test(
      'archive exactly once, keep full records, restore one, keep new analyses',
      () async {
    final store = PresetStore();
    await store.save(pair('old-1'));
    await store.save(pair('old-2'));
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList('preset_pairs');
    expect(await PresetArchive.archiveOnce(store), 2);
    expect(store.pairs, isEmpty);
    expect(prefs.getStringList(PresetArchive.snapshotKey), before);
    expect(prefs.getStringList(PresetArchive.recordsKey), before);
    expect((await PresetArchive.load()).length, 2);
    await store.save(pair('new'));
    expect(await PresetArchive.archiveOnce(store), 0);
    expect(store.pairs.single.id, 'new');
    await PresetArchive.restore(store, 'old-1');
    expect(store.pairs.map((p) => p.id), containsAll(['new', 'old-1']));
    expect((await PresetArchive.load()).single.id, 'old-2');
    final reopened = PresetStore();
    await reopened.load();
    expect(reopened.pairs.map((p) => p.id), containsAll(['new', 'old-1']));
  });
  test(
      'interrupted archive only removes snapshotted entries and never new work',
      () async {
    final store = PresetStore();
    await store.save(pair('old'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        PresetArchive.snapshotKey, prefs.getStringList('preset_pairs')!);
    await store.save(pair('new'));
    expect(await PresetArchive.archiveOnce(store), 1);
    expect(store.pairs.single.id, 'new');
    expect((await PresetArchive.load()).single.id, 'old');
  });
  test(
      'interrupted archive and restore never overwrite newer edits with the same ID',
      () async {
    final store = PresetStore();
    await store.save(pair('same'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        PresetArchive.snapshotKey, prefs.getStringList('preset_pairs')!);
    final updated = pair('same')
        .withPreset(pair('same').rhythm.copyWith(name: 'My newer edit'));
    await store.save(updated);
    expect(await PresetArchive.archiveOnce(store), 0);
    expect(store.pairs.single.rhythm.name, 'My newer edit');
    await PresetArchive.restore(store, 'same');
    expect(store.pairs.single.rhythm.name, 'My newer edit');
    expect(await PresetArchive.load(), isEmpty);
  });
  testWidgets(
      'archive shows preserved presets and restores only the chosen entry',
      (tester) async {
    final store = PresetStore();
    await store.save(pair('keep'));
    await store.save(pair('restore'));
    await PresetArchive.archiveOnce(store);
    await tester.pumpWidget(ChangeNotifierProvider<PresetStore>.value(
        value: store, child: const MaterialApp(home: ArchivedPresetsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Restaurar na biblioteca'), findsNWidgets(2));
    await tester.tap(find.text('Restaurar na biblioteca').first);
    await tester.pumpAndSettle();
    expect(store.pairs.length, 1);
    expect((await PresetArchive.load()).length, 1);
    expect(find.text('Preset restaurado na biblioteca.'), findsOneWidget);
  });
  testWidgets(
      'Biblioteca limpa cabe em celular pequeno e não mostra pilotos antigos',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = PresetStore();
    await store.load();
    store.libraryNotice =
        '2 análises de teste foram arquivadas. Você pode restaurá-las em Ajustes → Presets arquivados.';
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ApiService>.value(value: LocalApi()),
      ChangeNotifierProvider<PresetStore>.value(value: store)
    ], child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Ver arquivados'), findsOneWidget);
    expect(find.byTooltip('Testar MK20 por USB'), findsNothing);
    expect(find.byTooltip('Piloto Infest — MK300'), findsNothing);
    expect(find.byTooltip('Ajustes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
