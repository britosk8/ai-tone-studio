import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/widgets/calibration_test_card.dart';
import 'package:ai_tone_studio/screens/tone_result_screen.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'library_transfer_ui_test.dart' as fixture;

class EvaluationApi extends ApiService {
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> saveRecordingEvaluation(
      String id, Map<String, dynamic> evaluation) async {
    expect(id, 'capture-1');
    saved = Map.from(evaluation);
    return {'eligible_for_review': true};
  }
}

void main() {
  testWidgets(
      'Registra contexto declarado e avaliação sem alterar preset nem reenviar áudio',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final api = EvaluationApi();
    await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CalibrationTestCard(
                        recordingId: 'capture-1', role: 'rhythm'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar teste para calibração'));
    await tester.pumpAndSettle();
    Future<void> select(String label, String value) async {
      final form = find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == label);
      tester
          .widget<DropdownButton<String>>(find.descendant(
              of: form, matching: find.byType(DropdownButton<String>)))
          .onChanged!(value);
      await tester.pump();
    }

    await select('Captador / posição', 'bridge');
    await select('Conexão usada na gravação', 'pedal_usb');
    await select('Sinal gravado', 'processed');
    await select('Como ficou em relação à referência?', 'close');
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    await tester.tap(find.text('Guardar avaliação deste teste'));
    await tester.pumpAndSettle();
    expect(api.saved!['guitar'], 'konig_strat_sss');
    expect(api.saved!['pickup'], 'bridge');
    expect(api.saved!['preset_applied'], isTrue);
    expect(find.textContaining('Teste registrado com áudio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Referência aprovada permite avaliar sem oferecer ajustes ou envio',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = fixture.pair('test').rhythm;
    final preset = PresetData.fromJson({
      ...original.toJson(),
      'generation_metadata': {'calibration_baseline': true}
    });
    await tester.pumpWidget(Provider<ApiService>.value(
        value: EvaluationApi(),
        child: MaterialApp(
            home: ToneResultScreen(
                pairId: 'test',
                role: 'rhythm',
                preset: preset,
                report: const {
              'quality': 'usable',
              'recording_id': 'capture-1',
              'suggestions': [
                {'parameter': 'Bass', 'before': 50, 'after': 60}
              ]
            }))));
    await tester.pumpAndSettle();
    expect(find.text('Teste da referência aprovada'), findsOneWidget);
    expect(find.text('Registrar teste para calibração'), findsOneWidget);
    expect(find.text('Atualizar preset e seguir para envio'), findsNothing);
    expect(find.text('Enviar preset atual sem alterações'), findsNothing);
  });
}
