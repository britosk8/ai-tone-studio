import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/screens/transfer_screen.dart';
import 'v1_flow_test.dart' show fixture;
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'package:ai_tone_studio/screens/mk20_diagnostics_screen.dart';
import 'mk20_diagnostics_test.dart' show mk20Image;

class DiagnosticApi extends ApiService {
  bool offline = false;
  final reports = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> saveMk20Diagnostic(
      Map<String, dynamic> report) async {
    if (offline) throw StateError('Offline');
    reports.add(report);
    return {'id': 'receipt-mk20'};
  }
}

void main() {
  testWidgets(
      'Teste USB salva cópia local, sincroniza e permite retentar offline',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final folder = Directory.systemTemp.createTempSync('mk20-ui-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final api = DiagnosticApi()..offline = true;
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const events = MethodChannel('ai_tone/device_events');
    messenger.setMockMethodCallHandler(paths, (_) async => folder.path);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    var writes = 0;
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel,
        (call) async {
      if (call.method == 'listUsb') {
        return [
          {'id': '20', 'name': 'MK20'}
        ];
      }
      if (call.method == 'connect') return {};
      if (call.method == 'send') {
        final request = Mk300Protocol.parse(
            List<int>.from((call.arguments as Map)['bytes'] as List));
        if (request.cls != 13) {
          writes++;
        }
        expect(request.length, 412);
        final response = Mk300Protocol.build(
            13, 0x41, request.field, 412, request.space, mk20Image());
        await messenger.handlePlatformMessage(
            'ai_tone/device_events',
            const StandardMethodCodec()
                .encodeSuccessEnvelope({'type': 'data', 'bytes': response}),
            (_) {});
      }
      return null;
    });
    await tester.pumpWidget(Provider<ApiService>.value(
        value: api, child: const MaterialApp(home: Mk20DiagnosticsScreen())));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Ler MK20 e salvar diagnóstico'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Buscar MK20 por USB/OTG'));
    await tester.pumpAndSettle();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(find.widgetWithText(
              FilledButton, 'Ler MK20 e salvar diagnóstico'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Cópia salva neste celular.'), findsOneWidget);
    expect(File('${folder.path}/mk20_diagnostics/latest.json').existsSync(),
        isTrue);
    expect(writes, 0);
    expect(api.reports, isEmpty);
    api.offline = false;
    await tester.tap(find.text('Enviar diagnóstico ao backend'));
    await tester.pumpAndSettle();
    expect(api.reports.single['slot'], 150);
    expect(api.reports.single['write_enabled'], isFalse);
    expect(find.textContaining('receipt-mk20'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
  });

  testWidgets(
      'Conectar preset MK20 abre diagnóstico sem usar protocolo de escrita MK300',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final raw = fixture();
    (raw['lead_preset'] as Map)['device'] = 'MK20';
    final store = PresetStore();
    await store.save(PresetPair.fromJson(raw));
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: DiagnosticApi()),
          ChangeNotifierProvider<PresetStore>.value(value: store),
        ],
        child: MaterialApp(
          home: const TransferScreen(pairId: 'pair-001'),
          onGenerateRoute: (settings) {
            expect(settings.name, '/mk20-diagnostics');
            return MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Coleta MK20')));
          },
        )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Abrir teste de leitura MK20'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Abrir teste de leitura MK20'));
    await tester.pumpAndSettle();
    expect(find.text('Coleta MK20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
