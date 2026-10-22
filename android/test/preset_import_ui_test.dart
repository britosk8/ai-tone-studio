import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/screens/home_screen.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'library_transfer_ui_test.dart' as fixtures;

class OfflineApi extends ApiService {
  @override
  Future<Map<String, dynamic>> checkHealth() async =>
      throw StateError('Backend offline');
}

void main() {
  for (final outcome in ['accept', 'cancel', 'invalid']) {
    testWidgets(
        'Importação local $outcome funciona sem backend e preserva biblioteca',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PresetStore();
      await store.save(fixtures.pair('Anterior'));
      final temp = Directory.systemTemp.createTempSync('tone-import-');
      final bad = File('${temp.path}/bad.json')..writeAsStringSync('{}');
      FilePickerIO.registerWith();
      const picker = MethodChannel(
          'miguelruivo.flutter.plugins.filepicker', JSONMethodCodec());
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(picker, (call) async {
        expect(call.method, 'custom');
        expect(call.arguments['allowedExtensions'], ['json']);
        final path = outcome == 'invalid'
            ? bad.path
            : File('test/fixtures/infest_mk300_piloto_r1.json').absolute.path;
        return [
          {
            'path': path,
            'name': 'presets.json',
            'size': File(path).lengthSync()
          }
        ];
      });
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            Provider<ApiService>.value(value: OfflineApi())
          ],
          child: MaterialApp(
              home: const HomeScreen(),
              onGenerateRoute: (settings) {
                if (settings.name != '/presets') return null;
                expect((settings.arguments as Map)['pair_id'],
                    store.pairs.first.id);
                return MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Text('Presets importados')));
              })));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.file_open_outlined))
            .onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      if (outcome == 'invalid') {
        expect(find.textContaining('Erro ao importar:'), findsOneWidget);
        expect(store.pairs.length, 1);
      } else {
        expect(find.text('Importar presets MK300?'), findsOneWidget);
        expect(
            store.pairs.length, 1); // Nada persiste antes da escolha explícita.
        await tester.tap(find.text(
            outcome == 'accept' ? 'Importar como nova análise' : 'Cancelar'));
        await tester.pumpAndSettle();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(store.pairs.length, outcome == 'accept' ? 2 : 1);
        expect(store.pairs.any((p) => p.id == 'Anterior'), true);
        expect(find.text('Presets importados'),
            outcome == 'accept' ? findsOneWidget : findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      messenger.setMockMethodCallHandler(picker, null);
      temp.deleteSync(recursive: true);
    });
  }
}
