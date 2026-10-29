import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/screens/transfer_screen.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'mk20_transfer_test.dart' show originalImage, presetJson;

class TransferApi extends ApiService {
  final reports = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> saveMk20Transfer(
      Map<String, dynamic> report) async {
    reports.add(report);
    final export = Platform.environment['MK20_REPORT_EXPORT'];
    if (export != null) await File(export).writeAsString(jsonEncode(report));
    return {'id': 'qa-receipt', 'status': 'send_confirmed'};
  }
}

void main() {
  testWidgets(
      'MK20 no app: lê, salva backup, cancela e envia completo com retorno à inicial',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync('mk20-full-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final api = TransferApi(), store = PresetStore();
    final raw = jsonDecode(
            File('test/fixtures/generated_mk300_pair.json').readAsStringSync())
        as Map<String, dynamic>;
    raw['rhythm_preset'] = presetJson();
    raw['id'] = 'mk20-pair';
    await store.save(PresetPair.fromJson(raw));
    var image = originalImage();
    Uint8List? staged;
    var writes = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider'),
        events = MethodChannel('ai_tone/device_events');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel,
        (call) async {
      if (call.method == 'listUsb') {
        return [
          {'id': '20', 'name': 'MK20'}
        ];
      }
      if (call.method == 'connect') return {};
      if (call.method == 'send') {
        final f = Mk300Protocol.parse(
            List<int>.from((call.arguments as Map)['bytes']));
        final Uint8List response;
        if (f.cls == 13) {
          expect(f.length, 412);
          response =
              Mk300Protocol.build(13, 0xD21, f.field, 412, f.space, image);
        } else {
          writes++;
          if (f.space == 0) {
            expect(f.command, 0xD21);
            expect(f.field, 61388);
            expect(f.payload.length, 412);
            staged = f.payload;
          } else {
            expect(f.space, 15);
            image = Uint8List.fromList(staged!);
          }
          response = Uint8List.fromList(Mk300Protocol.ack);
        }
        await messenger.handlePlatformMessage(
            'ai_tone/device_events',
            const StandardMethodCodec()
                .encodeSuccessEnvelope({'type': 'data', 'bytes': response}),
            (_) {});
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
    });
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<PresetStore>.value(value: store)
        ],
        child: MaterialApp(initialRoute: '/transfer', routes: {
          '/': (_) => const Scaffold(body: Text('INICIAL QA')),
          '/transfer': (_) =>
              const TransferScreen(pairId: 'mk20-pair', initialRole: 'rhythm')
        })));
    await tester.pumpAndSettle();
    Future<void> invoke(String label) async {
      final button = find.widgetWithText(FilledButton, label);
      await tester.scrollUntilVisible(button, 200,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.runAsync(() async {
        final dynamic callback = tester.widget<FilledButton>(button).onPressed!;
        final dynamic pending = callback();
        if (label != 'Revisar e enviar preset' && pending is Future) {
          await pending;
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      });
      await tester.pump(const Duration(milliseconds: 400));
      if (find.byType(AlertDialog).evaluate().isEmpty) {
        await tester.pumpAndSettle();
      }
    }

    final scan = find.widgetWithText(OutlinedButton, 'Buscar pedaleiras');
    await tester.scrollUntilVisible(scan, 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    await invoke('Conectar e conferir leitura');
    await invoke('Ler destino e salvar backup');
    expect(writes, 0);
    await invoke('Revisar e enviar preset');
    expect(find.textContaining('MK20 — slot 150'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await invoke('Revisar e enviar preset');
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar envio'))
          .onPressed!();
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (api.reports.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(find.text('INICIAL QA'), findsOneWidget);
    expect(find.text('Preset MK20 QA enviado com sucesso'), findsOneWidget);
    expect(api.reports.length, 1);
    expect(api.reports.single['trace'], isNotEmpty);
    expect(
        Directory('${directory.path}/pedal_backups')
            .listSync()
            .whereType<File>()
            .any((f) => f.path.endsWith('.synced')),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
