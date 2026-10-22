import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/screens/transfer_screen.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'library_transfer_ui_test.dart' as fixtures;

void main() {
  for (final fail in [false, true]) {
    testWidgets(
        fail
            ? 'Erro de envio mostra motivo e mantém a tela de envio'
            : 'Envio confirmado mostra nome e volta para início',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PresetStore();
      await store.save(fixtures.pair('Atual'));
      final dir = Directory.systemTemp.createTempSync('tone-send-feedback-');
      var live = fixtures.image();
      Uint8List? staged;
      final messenger = tester.binding.defaultBinaryMessenger;
      const event = MethodChannel('ai_tone/device_events');
      const path = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(path, (call) async => dir.path);
      messenger.setMockMethodCallHandler(event, (call) async => null);
      messenger.setMockMethodCallHandler(NativeDeviceTransport.channel,
          (call) async {
        if (call.method == 'listUsb') {
          return [
            {'id': '1', 'name': 'MK300', 'kind': 'usb'}
          ];
        }
        if (call.method == 'connect') return {'kind': 'usb', 'name': 'MK300'};
        if (call.method == 'send') {
          final frame = Mk300Protocol.parse(
              List<int>.from((call.arguments as Map)['bytes'] as List));
          final Uint8List reply;
          if (frame.cls == 13) {
            reply = Mk300Protocol.build(
                13, 0x41, frame.field, 448, frame.space, live);
          } else {
            if (fail) {
              throw PlatformException(
                  code: 'usb_error', message: 'Falha USB simulada');
            }
            if (frame.space == 0) staged = frame.payload;
            if (frame.space == 15 && staged != null) live = staged!;
            reply = Uint8List.fromList(Mk300Protocol.ack);
          }
          await messenger.handlePlatformMessage(
              'ai_tone/device_events',
              const StandardMethodCodec()
                  .encodeSuccessEnvelope({'type': 'data', 'bytes': reply}),
              (_) {});
        }
        return null;
      });
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            Provider<ApiService>.value(value: fixtures.LocalApi())
          ],
          child: MaterialApp(
            home: const Scaffold(body: Text('Tela inicial')),
            routes: {'/transfer': (_) => const TransferScreen(pairId: 'Atual')},
          )));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/transfer');
      await tester.pumpAndSettle();
      Future<void> reveal(String text, double delta) =>
          tester.scrollUntilVisible(find.text(text), delta,
              scrollable: find
                  .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable))
                  .first);
      await reveal('Buscar pedaleiras', 250);
      await tester.tap(find.text('Buscar pedaleiras'));
      await tester.pumpAndSettle();
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile))
          .onChanged!(true);
      await tester.pump();
      await tester.runAsync(() async {
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Conectar e conferir leitura'))
            .onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await reveal('Ler destino e salvar backup', 250);
      await tester.runAsync(() async {
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Ler destino e salvar backup'))
            .onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await reveal('Revisar e enviar preset', 250);
      await tester.tap(find.text('Revisar e enviar preset'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirmar envio'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration(milliseconds: fail ? 300 : 3500));
      });
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      if (fail) {
        expect(find.text('Enviar para pedaleira'), findsOneWidget);
        expect(find.textContaining('Falha USB simulada'), findsWidgets);
        expect(find.text('Tela inicial'), findsNothing);
      } else {
        expect(find.text('Tela inicial'), findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .join(' | '));
        expect(
            find.text('Preset Atual-Base enviado com sucesso'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      messenger.setMockMethodCallHandler(path, null);
      messenger.setMockMethodCallHandler(event, null);
      messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
      dir.deleteSync(recursive: true);
    });
  }
}
