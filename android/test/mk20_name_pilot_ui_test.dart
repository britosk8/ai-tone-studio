import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_tone_studio/screens/mk20_name_pilot_screen.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'mk20_diagnostics_test.dart' show mk20Image;

class NameApi extends ApiService {
  final reports = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> saveMk20NamePilot(
      Map<String, dynamic> report) async {
    reports.add(report);
    return {
      'id': 'pilot-receipt',
      'status': report['operation'] == 'restore'
          ? 'restore_confirmed'
          : 'rename_confirmed'
    };
  }
}

void main() {
  testWidgets(
      'Nome só muda após backup e confirmação; restauração confere original',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = Directory.systemTemp.createTempSync('mk20-pilot-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final api = NameApi();
    final original = mk20Image();
    var image = Uint8List.fromList(original);
    Uint8List? staged;
    var writes = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const events = MethodChannel('ai_tone/device_events');
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
        final command = Mk300Protocol.parse(
            List<int>.from((call.arguments as Map)['bytes'] as List));
        final Uint8List response;
        if (command.cls == 13) {
          response = Mk300Protocol.build(
              13, 0xD21, command.field, 412, command.space, image);
        } else {
          writes++;
          if (command.space == 0) {
            expect(command.field, 61388);
            expect(command.payload.sublist(20), original.sublist(20));
            staged = command.payload;
          } else {
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
    await tester.pumpWidget(Provider<ApiService>.value(
        value: api, child: const MaterialApp(home: Mk20NamePilotScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar MK20 por USB/OTG'));
    await tester.pumpAndSettle();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(find.widgetWithText(
              FilledButton, 'Ler slot 150 e preparar backup'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('Backup integral salvo'), findsOneWidget);
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(find.widgetWithText(
              FilledButton, 'Revisar e testar gravação do nome'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(find.widgetWithText(
              FilledButton, 'Revisar e testar gravação do nome'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar teste no slot 150'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 3800));
    });
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(api.reports.single['status'], 'confirmed');
    expect(find.textContaining('Nome do slot 150 gravado'), findsOneWidget);
    await tester.runAsync(() async {
      tester
          .widget<OutlinedButton>(find.widgetWithText(
              OutlinedButton, 'Restaurar original do slot 150'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar restauração'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 3800));
    });
    await tester.pumpAndSettle();
    expect(writes, 4);
    expect(image, original);
    expect(api.reports.last['operation'], 'restore');
    expect(find.textContaining('restaurado e conferido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
  });
}
