import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/screens/tone_comparison_screen.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/tone_recording.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'library_transfer_ui_test.dart' as fixtures;

class ComparisonApi extends ApiService {
  bool requested = false;
  @override
  Future<Map<String, dynamic>> compareTone(
      {required File recording,
      required PresetData preset,
      required String pairId,
      required String inputKind,
      File? reference,
      double referenceStart = 0,
      String referenceKind = 'mix'}) async {
    requested = true;
    if (inputKind != 'usb') throw StateError('Fonte da gravação foi alterada');
    final amp = preset.effectChain.firstWhere((b) => b.effectType == 'amp');
    return {
      'summary': 'Graves acima da referência.',
      'confidence': 'low',
      'quality': 'ok',
      'limitations': ['Comparação orientativa.'],
      'suggestions': [
        {
          'slot': amp.slot,
          'model_id': amp.modelId,
          'effect_type': 'amp',
          'parameter': 'Bass',
          'before': amp.parameters['Bass'],
          'after': amp.parameters['Bass']! - 3,
          'reason': 'Reduzir graves.'
        }
      ]
    };
  }
}

void main() {
  for (final usbAvailable in [false, true]) {
    testWidgets(
        usbAvailable
            ? 'Gravação USB chega à comparação e ajuste salvo preserva catálogo'
            : 'Sem entrada USB, gravação fica bloqueada e não usa microfone',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PresetStore();
      await store.save(fixtures.pair('Audio'));
      final api = ComparisonApi();
      final file = File(
          '${Directory.systemTemp.path}/tone-ui-${DateTime.now().microsecondsSinceEpoch}.wav');
      file.writeAsBytesSync([0, 1]);
      const permission =
          MethodChannel('flutter.baseflow.com/permissions/methods');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permission,
          (call) async => {for (final id in call.arguments as List) id: 1});
      messenger.setMockMethodCallHandler(ToneRecording.channel, (call) async {
        if (call.method == 'inputs') {
          return [
            if (usbAvailable) {'id': 20, 'kind': 'usb', 'name': 'MK300 Audio'},
            {'id': 1, 'kind': 'microphone', 'name': 'Microfone'}
          ];
        }
        if (call.method == 'start') {
          expect((call.arguments as Map)['kind'], 'usb');
          expect((call.arguments as Map)['id'], 20);
          return {'input': 'MK300 Audio'};
        }
        if (call.method == 'status') {
          return {'recording': true, 'finished': false};
        }
        if (call.method == 'stop') return file.path;
        return null;
      });
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            Provider<ApiService>.value(value: api)
          ],
          child:
              const MaterialApp(home: ToneComparisonScreen(pairId: 'Audio'))));
      await tester.pumpAndSettle();
      Future<void> reveal(String text) =>
          tester.scrollUntilVisible(find.text(text), 200,
              scrollable: find
                  .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable))
                  .first);
      await reveal('Gravar minha guitarra');
      final start = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Gravar minha guitarra'));
      if (!usbAvailable) {
        expect(start.onPressed, isNull);
        expect(find.textContaining('Entrada não encontrada'), findsOneWidget);
      } else {
        await tester.runAsync(() async {
          start.onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('Parar gravação (0 s)'), findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .join(' | '));
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Parar gravação (0 s)'))
            .onPressed!();
        await tester.pumpAndSettle();
        await reveal('Analisar e sugerir ajustes');
        await tester.tap(find.text('Analisar e sugerir ajustes'));
        await tester.pumpAndSettle();
        expect(api.requested, true);
        await reveal('Graves acima da referência.');
        expect(find.text('Graves acima da referência.'), findsOneWidget);
        final before = store.pairs.single.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass']!;
        await reveal('Salvar ajustes sugeridos no aplicativo');
        await tester.tap(find.text('Salvar ajustes sugeridos no aplicativo'));
        await tester.pumpAndSettle();
        expect(
            store.pairs.single.lead.effectChain
                .firstWhere((b) => b.effectType == 'amp')
                .parameters['Bass'],
            before - 3);
        expect(store.pairs.single.lead.catalogVersion, '0.4.0');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      messenger.setMockMethodCallHandler(permission, null);
      messenger.setMockMethodCallHandler(ToneRecording.channel, null);
      if (file.existsSync()) file.deleteSync();
    });
  }
}
