import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/screens/preset_list_screen.dart';
import 'package:ai_tone_studio/screens/preset_editor_screen.dart';

Map<String, dynamic> fixture() => {
      'id': 'pair-001',
      'rhythm_preset': {
        'id': 'pair-001',
        'name': 'Base',
        'device': 'MK20',
        'role': 'rhythm',
        'effect_chain': [
          {
            'slot': 0,
            'effect_type': 'amp',
            'model_id': '0',
            'model_name': 'Amp',
            'enabled': true,
            'parameters': {'Gain': 40},
            'parameter_specs': {
              'Gain': {'min': -80, 'max': 100, 'step': 1}
            },
          }
        ],
      },
      'lead_preset': {
        'id': 'lead-001',
        'device': 'MK300',
        'role': 'lead',
        'effect_chain': []
      },
      'analysis': <String, dynamic>{},
    };

void main() {
  test('Configuração do backend é recuperada ao reabrir', () async {
    SharedPreferences.setMockInitialValues(
        {'backend_url': 'http://10.0.2.2:8000/'});
    final api = ApiService();
    await api.loadSettings();
    expect(api.baseUrl, 'http://10.0.2.2:8000');
  });

  test('Presets antigos sem ID migram e preservam o conteúdo', () async {
    final pair = PresetPair.fromJson(fixture());
    SharedPreferences.setMockInitialValues({
      'preset_pairs': [
        jsonEncode({
          'id': '',
          'rhythm': pair.rhythm.toJson(),
          'lead': pair.lead.toJson(),
          'analysis': <String, dynamic>{},
        })
      ]
    });
    final store = PresetStore();
    await Future.wait([store.load(), store.load()]);
    expect(store.pairs.single.id, 'pair-001');
    final reopened = PresetStore();
    await reopened.load();
    expect(
        reopened.pairs.single.rhythm.effectChain.single.parameters['Gain'], 40);
  });

  test('Contrato antigo da API tem fallback para ID e mensagem de erro', () {
    final raw = fixture()..remove('id');
    expect(PresetPair.fromJson(raw).id, 'pair-001');
    final job = AnalysisJob.fromJson(
        {'status': 'failed', 'error': 'Áudio inválido', 'progress': 'Falhou'});
    expect(job.errorMessage, 'Áudio inválido');
    expect(job.progressMessage, 'Falhou');
  });

  testWidgets('Editar e salvar atualiza biblioteca, guia e JSON offline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    await store.save(PresetPair.fromJson(fixture()));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: const PresetListScreen(pairId: 'pair-001'),
        onGenerateRoute: (settings) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
              builder: (_) => PresetEditorScreen(
                  preset: args['preset'] as PresetData,
                  pairId: args['pair_id'] as String));
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar').first);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, -80);
    expect(slider.max, 100);
    slider.onChanged!(65);
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(store.pairs.single.rhythm.effectChain.single.parameters['Gain'], 65);
    final reopened = PresetStore();
    await reopened.load();
    final saved = reopened.pairs.single;
    expect(saved.toReadableGuide(), contains('Gain: 65.0'));
    expect(
        (saved.exportJson()['rhythm_preset'] as Map)['effect_chain'][0]
            ['parameters']['Gain'],
        65);
    expect(saved.rhythm.effectChain.single.parameterSpecs['Gain']!.min, -80);
  });
}
