import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/tone_recording.dart';
import 'package:ai_tone_studio/services/capture_level.dart';
import 'package:ai_tone_studio/screens/tone_comparison_screen.dart';
import 'package:ai_tone_studio/screens/upload_screen.dart';
import 'package:ai_tone_studio/screens/tone_result_screen.dart';
import 'package:ai_tone_studio/screens/analysis_screen.dart';
import 'library_transfer_ui_test.dart' as fixtures;

class SavedApi extends ApiService {
  final roles = <String>[];
  Map<String, dynamic> info(String role) => {
        'role': role,
        'title': 'Saved song',
        'start_seconds': role == 'lead' ? 160.0 : 50.0,
        'duration_seconds': 20.0,
        'needs_region': false
      };
  @override
  Future<Map<String, dynamic>> referenceInfo(String pairId, String role) async {
    roles.add(role);
    return info(role);
  }

  @override
  Future<List<Map<String, dynamic>>> referenceLibrary() async => [
        {
          'pair_id': 'Saved',
          'title': 'Saved song',
          'roles': {'rhythm': info('rhythm'), 'lead': info('lead')}
        }
      ];
}

class ReusedApi extends SavedApi {
  @override
  Future<AnalysisJob> getJobStatus(String jobId) async => const AnalysisJob(
      jobId: 'saved-job',
      status: 'completed',
      progressPercent: 100,
      pairId: 'Keep edits');
  @override
  Future<PresetPair> getPresets(String pairId) async =>
      throw StateError('Não sobrescrever preset local existente');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Reduz volume conhecido preservando ganho, identidade e referência', () {
    final original = fixtures.pair('Level').lead;
    final before =
        PresetData.fromJson({...original.toJson(), 'preset_volume': 40});
    final after = reduceCaptureLevel(before);
    expect(after.presetVolume, 30);
    expect(after.id, before.id);
    expect(after.effectChain.map((b) => b.toJson()).toList(),
        before.effectChain.map((b) => b.toJson()).toList());
    expect(before.presetVolume, 40);
    expect(() => reduceCaptureLevel(original), throwsStateError);
    expect(
        () => reduceCaptureLevel(
            PresetData.fromJson({...before.toJson(), 'device': 'MK20'})),
        throwsStateError);
  });
  testWidgets('Solo abre sua referência salva sem seletor de arquivo',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    var pair = fixtures.pair('Saved');
    for (final preset in [pair.rhythm, pair.lead]) {
      pair = pair.withPreset(PresetData.fromJson({
        ...preset.toJson(),
        'generation_metadata': {'generator': 'guitar-v2-heuristic'}
      }));
    }
    await store.save(pair);
    final api = SavedApi();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ToneRecording.channel,
        (MethodCall call) async => call.method == 'inputs' ? [] : null);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider.value(value: store)
        ],
        child: const MaterialApp(
            home: ToneComparisonScreen(pairId: 'Saved', initialRole: 'lead'))));
    await tester.pumpAndSettle();
    expect(api.roles, ['lead']);
    await tester.scrollUntilVisible(find.text('Referência da guitarra'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Trecho: 160.0 s — duração 20.0 s'), findsOneWidget);
    expect(find.text('Selecionar áudio original'), findsNothing);
    expect(find.text('Selecionar outra referência (análises antigas)'),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(ToneRecording.channel, null);
  });
  testWidgets('Música salva preenche trechos independentes sem pedir arquivo',
      (tester) async {
    await tester.pumpWidget(Provider<ApiService>.value(
        value: SavedApi(), child: const MaterialApp(home: UploadScreen())));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Usar música já separada'));
    await tester.pumpAndSettle();
    final textFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(textFields.any((field) => field.controller!.text == '50.0'), isTrue);
    expect(
        textFields.any((field) => field.controller!.text == '160.0'), isTrue);
    expect(find.text('Arquivo de Áudio'), findsNothing);
  });
  testWidgets('Saturação permite reduzir apenas o volume e segue para envio',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    var pair = fixtures.pair('Level');
    pair = pair.withPreset(
        PresetData.fromJson({...pair.lead.toJson(), 'preset_volume': 40}));
    await store.save(pair);
    final oldBase = pair.rhythm.toJson();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            home: ToneResultScreen(
                pairId: pair.id,
                role: 'lead',
                preset: pair.lead,
                report: const {
                  'quality': 'clipped',
                  'recording': {'clipped_fraction': .034},
                  'suggestions': []
                }),
            onGenerateRoute: (settings) {
              expect(settings.name, '/transfer');
              expect(settings.arguments, {'pair_id': pair.id, 'role': 'lead'});
              return MaterialPageRoute(
                  builder: (_) =>
                      const Scaffold(body: Text('Enviar volume reduzido')));
            })));
    await tester.pumpAndSettle();
    final button = find.text('Reduzir volume 40 → 30 e seguir para envio');
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(store.pairs.single.lead.presetVolume, 30);
    expect(store.pairs.single.rhythm.toJson(), oldBase);
    expect(store.pairs.single.lead.effectChain.map((b) => b.toJson()).toList(),
        pair.lead.effectChain.map((b) => b.toJson()).toList());
    expect(find.text('Enviar volume reduzido'), findsOneWidget);
  });
  testWidgets('Reutilizar geração concluída preserva ajustes locais',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    var pair = fixtures.pair('Keep edits');
    pair = pair.withPreset(pair.lead.copyWith(name: 'Meu solo editado'));
    await store.save(pair);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: ReusedApi()),
          ChangeNotifierProvider.value(value: store)
        ],
        child: MaterialApp(
            home: const AnalysisScreen(jobId: 'saved-job'),
            onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Text('Preset preservado'))))));
    await tester.pumpAndSettle();
    expect(store.pairs.single.lead.name, 'Meu solo editado');
    expect(store.pairs.length, 1);
    expect(find.text('Preset preservado'), findsOneWidget);
  });
}
