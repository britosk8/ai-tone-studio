import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/pedal_reference.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/tone_recording.dart';
import 'package:ai_tone_studio/screens/tone_comparison_screen.dart';
import 'pedal_reference_test.dart' as references;
import 'library_transfer_ui_test.dart' as fixtures;

class MissingProfileApi extends ApiService {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> compareTone(
      {required File recording,
      required PresetData preset,
      required String pairId,
      required String inputKind,
      File? reference,
      double referenceStart = 0,
      String referenceKind = 'mix'}) async {
    calls++;
    throw ApiException('Selecione o áudio original',
        statusCode: 400, errorCode: 'reference_required');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Referência antiga sincroniza com binário e preset gerado completos',
      () async {
    final pair = fixtures.pair('local-only');
    final repository = PedalReferenceRepository();
    await repository.save(pair.id, 'rhythm', references.snapshot());
    var calls = 0;
    await http.runWithClient(() async {
      final api = ApiService()..setBaseUrl('http://localhost:8000');
      expect(await api.syncSavedPedalReferences([pair]), 0);
    },
        () => MockClient((request) async {
              calls++;
              expect(request.method, 'PUT');
              expect(request.url.path,
                  '/api/v1/presets/local-only/pedal-reference/rhythm');
              final body = jsonDecode(request.body) as Map;
              expect(body['reference']['image_base64'],
                  references.snapshot().toJson()['image_base64']);
              expect(body['generated_preset'], pair.rhythm.toJson());
              return http.Response('{}', 200);
            }));
    expect(calls, 1);
  });

  test(
      'Backend offline preserva referência local para tentar sincronizar depois',
      () async {
    final pair = fixtures.pair('local-only');
    await PedalReferenceRepository()
        .save(pair.id, 'rhythm', references.snapshot());
    await http.runWithClient(() async {
      expect(await ApiService().syncSavedPedalReferences([pair]), 1);
    }, () => MockClient((_) async => throw const SocketException('offline')));
    expect((await PedalReferenceRepository().load(pair.id, 'rhythm'))!.slot, 1);
  });

  test('Erro estruturado de referência mantém código e mensagem legível',
      () async {
    final file = File(
        '${Directory.systemTemp.path}/tone-v133-${DateTime.now().microsecondsSinceEpoch}.wav')
      ..writeAsBytesSync([0, 1]);
    try {
      await http.runWithClient(() async {
        await expectLater(
            ApiService().compareTone(
                recording: file,
                preset: fixtures.pair('local').rhythm,
                pairId: 'local',
                inputKind: 'file'),
            throwsA(isA<ApiException>()
                .having((e) => e.errorCode, 'code', 'reference_required')
                .having((e) => e.message, 'message',
                    'Selecione o áudio original')));
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'detail': {
                  'code': 'reference_required',
                  'message': 'Selecione o áudio original'
                }
              }),
              400,
              headers: {'content-type': 'application/json; charset=utf-8'})));
    } finally {
      file.deleteSync();
    }
  });

  testWidgets('Sem perfil abre seleção do original e preserva gravação/preset',
      (tester) async {
    final store = PresetStore();
    final pair = fixtures.pair('local');
    await store.save(pair);
    final folder =
        Directory.systemTemp.createTempSync('tone-reference-required-');
    final capture = File('${folder.path}/capture.wav')
      ..writeAsBytesSync([0, 1]);
    final original = File('${folder.path}/original.m4a')
      ..writeAsBytesSync([0, 1]);
    final messenger = tester.binding.defaultBinaryMessenger;
    FilePickerIO.registerWith();
    const picker = MethodChannel(
        'miguelruivo.flutter.plugins.filepicker', JSONMethodCodec());
    var selections = 0;
    messenger.setMockMethodCallHandler(picker, (call) async {
      final selected = selections++ == 0 ? capture : original;
      return [
        {
          'path': selected.path,
          'name': selected.uri.pathSegments.last,
          'size': selected.lengthSync()
        }
      ];
    });
    messenger.setMockMethodCallHandler(ToneRecording.channel,
        (call) async => call.method == 'inputs' ? [] : null);
    final api = MissingProfileApi();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: store),
      Provider<ApiService>.value(value: api)
    ], child: const MaterialApp(home: ToneComparisonScreen(pairId: 'local'))));
    await tester.pumpAndSettle();
    Future<void> reveal(String text) =>
        tester.scrollUntilVisible(find.text(text), 250,
            scrollable: find
                .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable))
                .first);
    await reveal('Importar gravação de guitarra');
    await tester.tap(find.text('Importar gravação de guitarra'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await reveal('Analisar e sugerir ajustes');
    await tester.tap(find.text('Analisar e sugerir ajustes'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(selections, 2);
    expect(find.text('original.m4a'), findsOneWidget);
    expect(capture.existsSync(), true);
    expect(store.pairs.single.rhythm.toJson(), pair.rhythm.toJson());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(picker, null);
    messenger.setMockMethodCallHandler(ToneRecording.channel, null);
    folder.deleteSync(recursive: true);
  });
}
