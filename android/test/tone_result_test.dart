import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/screens/tone_result_screen.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'library_transfer_ui_test.dart' as fixtures;

void main() {
  Future<PresetStore> setup(
      WidgetTester tester, Map<String, dynamic> report) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    final pair = fixtures.pair('Comparação');
    await store.save(pair);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            home: ToneResultScreen(
                pairId: pair.id,
                role: 'lead',
                preset: pair.lead,
                report: report),
            onGenerateRoute: (settings) {
              if (settings.name != '/transfer') return null;
              expect(settings.arguments, {'pair_id': pair.id, 'role': 'lead'});
              return MaterialPageRoute(
                  builder: (_) =>
                      const Scaffold(body: Text('Enviar preset selecionado')));
            })));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> reveal(WidgetTester tester, String label) =>
      tester.scrollUntilVisible(find.text(label), 150,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
  Map<String, dynamic> report() {
    final amp = fixtures
        .pair('Comparação')
        .lead
        .effectChain
        .firstWhere((b) => b.effectType == 'amp');
    return {
      'quality': 'ok',
      'summary': 'Graves acima da referência.',
      'differences_db': {'bass': 4.1, 'middle': -1, 'treble': 0.5},
      'limitations': [],
      'suggestions': [
        {
          'slot': amp.slot,
          'model_id': amp.modelId,
          'effect_type': amp.effectType,
          'parameter': 'Bass',
          'before': amp.parameters['Bass'],
          'after': amp.parameters['Bass']! - 3,
          'reason': 'Reduzir os graves.'
        }
      ]
    };
  }

  testWidgets('Atualiza preset existente e segue para envio do mesmo solo',
      (tester) async {
    final store = await setup(tester, report());
    final pair = store.pairs.single;
    final before = pair.lead.effectChain
        .firstWhere((b) => b.effectType == 'amp')
        .parameters['Bass']!;
    await reveal(tester, 'Atualizar preset e seguir para envio');
    await tester.tap(find.text('Atualizar preset e seguir para envio'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar preset selecionado'), findsOneWidget);
    expect(store.pairs.length, 1);
    expect(store.pairs.single.lead.id, pair.lead.id);
    expect(store.pairs.single.rhythm.toJson(), pair.rhythm.toJson());
    final loaded = PresetStore();
    await loaded.load();
    expect(
        loaded.pairs.single.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        before - 3);
  });
  testWidgets('Clipping explica como repetir e bloqueia qualquer ajuste/envio',
      (tester) async {
    final data = report()
      ..['quality'] =
          'clipped'; // Mesmo se a resposta trouxer sugestões indevidas.
    data['recording'] = {'clipped_fraction': .03};
    final store = await setup(tester, data);
    final before = store.pairs.single.lead.toJson();
    expect(find.text('Gravação saturada — grave novamente'), findsOneWidget);
    expect(find.text('Atualizar preset e seguir para envio'), findsNothing);
    expect(find.text('Enviar preset atual sem alterações'), findsNothing);
    await reveal(tester, 'Voltar e gravar novamente');
    expect(store.pairs.single.lead.toJson(), before);
  });
  testWidgets('Sem alterações diferencia EQ compatível de timbre idêntico',
      (tester) async {
    final data = report()..['suggestions'] = [];
    data['differences_db'] = {'bass': 1, 'middle': -1, 'treble': .5};
    await setup(tester, data);
    expect(find.text('EQ sem ajustes recomendados'), findsOneWidget);
    expect(find.textContaining('Isso não confirma'), findsOneWidget);
    expect(find.text('Atualizar preset e seguir para envio'), findsNothing);
    await reveal(tester, 'Enviar preset atual sem alterações');
    expect(find.text('Enviar preset atual sem alterações'), findsOneWidget);
  });
  testWidgets(
      'Preset modificado desde análise não é sobrescrito e não segue para envio',
      (tester) async {
    final data = report();
    final store = await setup(tester, data);
    final pair = store.pairs.single;
    final amp = pair.lead.effectChain.firstWhere((b) => b.effectType == 'amp');
    final chain = pair.lead.effectChain
        .map((b) => b == amp
            ? b.copyWith(parameters: {
                ...b.parameters,
                'Bass': b.parameters['Bass']! + 1
              })
            : b)
        .toList();
    await store.save(pair.withPreset(pair.lead.copyWith(effectChain: chain)));
    await reveal(tester, 'Atualizar preset e seguir para envio');
    await tester.tap(find.text('Atualizar preset e seguir para envio'));
    await tester.pumpAndSettle();
    await reveal(tester,
        'Erro: Bad state: Sugestão inválida ou parâmetro já alterado: Bass');
    expect(find.text('Enviar preset selecionado'), findsNothing);
    expect(
        store.pairs.single.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        amp.parameters['Bass']! + 1);
  });
  testWidgets('Desmarcar mudança evita atualização vazia', (tester) async {
    await setup(tester, report());
    await Scrollable.ensureVisible(tester.element(find.byType(Checkbox)),
        alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await reveal(tester, 'Atualizar preset e seguir para envio');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Atualizar preset e seguir para envio'))
            .onPressed,
        isNull);
  });
}
