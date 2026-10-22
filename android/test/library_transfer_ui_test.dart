import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/screens/home_screen.dart';
import 'package:ai_tone_studio/screens/transfer_screen.dart';
import 'package:ai_tone_studio/screens/upload_screen.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/services/device/device_transport.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';

class LocalApi extends ApiService {
  @override
  Future<Map<String, dynamic>> checkHealth() async => {'version': '1.1.1'};
}

PresetPair pair(String id, {bool old = false}) {
  final raw = jsonDecode(
          File('test/fixtures/generated_mk300_pair.json').readAsStringSync())
      as Map<String, dynamic>;
  raw['id'] = id;
  for (final role in ['rhythm_preset', 'lead_preset']) {
    final preset = raw[role] as Map<String, dynamic>;
    preset['id'] = '$id-$role';
    preset['song_title'] = id;
    preset['name'] = '$id-${role == 'rhythm_preset' ? 'Base' : 'Solo'}';
    if (old) preset['catalog_version'] = '0.3.0';
  }
  return PresetPair.fromJson(raw);
}

Widget app(PresetStore store, Widget home) => MultiProvider(providers: [
      ChangeNotifierProvider.value(value: store),
      Provider<ApiService>.value(value: LocalApi()),
    ], child: MaterialApp(home: home));
Uint8List image() {
  final hex = File('../backend/tests/fixtures/mk300-jm-od.hex')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), '');
  return Uint8List.fromList(List.generate(hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
}

void main() {
  testWidgets(
      'Leitura válida com preset antigo fica bloqueada; escolher outro da biblioteca habilita backup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    await store.save(pair('Antiga', old: true));
    await store.save(pair('Atual'));
    final messenger = tester.binding.defaultBinaryMessenger;
    const eventControl = MethodChannel('ai_tone/device_events');
    messenger.setMockMethodCallHandler(eventControl, (call) async => null);
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel,
        (call) async {
      if (call.method == 'listUsb') {
        return [
          {'id': '1', 'name': 'MK300', 'kind': 'usb'}
        ];
      }
      if (call.method == 'connect') return {'kind': 'usb', 'name': 'MK300'};
      if (call.method == 'send') {
        final command = Mk300Protocol.parse(
            List<int>.from((call.arguments as Map)['bytes'] as List));
        expect(command.cls, 13); // Este teste UI só permite leitura.
        final response = Mk300Protocol.build(
            13, 0x41, command.field, 448, command.space, image());
        await messenger.handlePlatformMessage(
            'ai_tone/device_events',
            const StandardMethodCodec()
                .encodeSuccessEnvelope({'type': 'data', 'bytes': response}),
            (_) {});
      }
      return null;
    });
    Future<void> reveal(Finder finder, double delta) async {
      await tester.scrollUntilVisible(finder, delta,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
    }

    await tester.pumpWidget(app(store, const TransferScreen(pairId: 'Antiga')));
    await tester.pumpAndSettle();
    expect(find.text('Preset antigo — envio bloqueado'), findsOneWidget);
    await reveal(find.text('Buscar pedaleiras'), 250);
    await tester.tap(find.text('Buscar pedaleiras'));
    await tester.pumpAndSettle();
    await reveal(find.byType(CheckboxListTile), 200);
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!(true);
    await tester.pump();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Conectar e conferir leitura'))
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await reveal(find.text('Ler destino e salvar backup'), 250);
    expect(find.textContaining('layout e leitura conferidos'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Ler destino e salvar backup'))
            .onPressed,
        isNull);
    final dropdown = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        w.decoration.labelText == 'Música / análise salva');
    await reveal(dropdown, -300);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atual').last);
    await tester.pumpAndSettle();
    expect(find.text('Preset antigo — envio bloqueado'), findsNothing);
    expect(find.widgetWithText(RadioListTile<String>, 'Atual-Base'),
        findsOneWidget);
    expect(find.text('Atual-Solo'), findsOneWidget);
    await reveal(find.text('Ler destino e salvar backup'), 250);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Ler destino e salvar backup'))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(NativeDeviceTransport.channel, null);
    messenger.setMockMethodCallHandler(eventControl, null);
  });
  testWidgets(
      'Excluir pela biblioteca confirma base/solo, permite cancelar e persiste exclusão',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    await store.save(pair('Manter'));
    await store.save(pair('Excluir'));
    await tester.pumpWidget(app(store, const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ações dos presets').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir análise (base e solo)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('presets de base e solo'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(store.pairs.length, 2);
    await tester.tap(find.byTooltip('Ações dos presets').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir análise (base e solo)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(store.pairs.single.id, 'Manter');
    final reopened = PresetStore();
    await reopened.load();
    expect(reopened.pairs.single.id, 'Manter');
  });
  testWidgets('Nova análise preserva escolha de dispositivos e título recebido',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: UploadScreen(
            initialSongTitle: 'Minha música',
            initialArtist: 'Artista',
            initialRhythmDevice: 'MK300',
            initialLeadDevice: 'MK300')));
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, 'Artista');
    expect(fields[1].controller!.text, 'Minha música');
    expect(
        tester
            .widgetList<DropdownButton<String>>(
                find.byType(DropdownButton<String>))
            .where((w) => w.items!.any((item) => item.value == 'MK300'))
            .every((w) => w.value == 'MK300'),
        true);
  });
}
