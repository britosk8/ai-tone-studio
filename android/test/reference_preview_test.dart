import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/screens/reference_preview_screen.dart';

class PreviewApi extends ApiService {
  final requests = <Map<String, dynamic>>[];
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> downloadReferencePreview(
      String pairId, String role, double start, double duration,
      {int? channel, double listenGainDb = 0}) async {
    requests.add({
      'start': start,
      'duration': duration,
      'channel': channel,
      'gain': listenGainDb
    });
    if (gate != null) await gate!.future;
    return {'bytes': List<int>.filled(100, 0), 'gain_db': listenGainDb};
  }
}

void main() {
  const native = MethodChannel('ai_tone/preview');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final calls = <String>[];
  setUp(() async {
    calls.clear();
    directory = await Directory.systemTemp.createTemp('tone-preview-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'play') {
        expect(await File((call.arguments as Map)['path']).exists(), isTrue);
        return {'duration_ms': 6000};
      }
      if (call.method == 'status') {
        return {'playing': true, 'position_ms': 1000, 'duration_ms': 6000};
      }
      return null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
    await directory.delete(recursive: true);
  });
  Widget preview(PreviewApi api) => Provider<ApiService>.value(
      value: api,
      child: const MaterialApp(
          home: ReferencePreviewScreen(
              pairId: 'song',
              role: 'rhythm',
              fixedChannel: 1,
              info: {
            'cache_start_seconds': 100,
            'available_duration': 60,
            'start_seconds': 110,
            'duration_seconds': 12,
            'channels': 2
          })));
  testWidgets(
      'Ouvir usa trecho e canal escolhidos, ganho só na escuta e para ao sair',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = PreviewApi();
    await tester.pumpWidget(preview(api));
    await tester.pumpAndSettle();
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    sliders[1].onChanged!(6);
    await tester.pump();
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(120);
    await tester.pump();
    tester.widgetList<Slider>(find.byType(Slider)).last.onChanged!(12);
    await tester.pump();
    await tester.runAsync(() async {
      final dynamic action = tester
          .widget<FilledButton>(find.ancestor(
              of: find.text('Ouvir trecho'),
              matching: find.byWidgetPredicate((w) => w is FilledButton)))
          .onPressed!;
      await action();
    });
    await tester.pump();
    expect(api.requests.single,
        {'start': 120.0, 'duration': 6.0, 'channel': 1, 'gain': 12.0});
    expect(calls, contains('play'));
    expect(find.text('Parar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(calls.last, 'stop');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Sair durante download nunca inicia reprodução atrasada',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = PreviewApi()..gate = Completer<void>();
    await tester.pumpWidget(preview(api));
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.ancestor(
            of: find.text('Ouvir trecho'),
            matching: find.byWidgetPredicate((w) => w is FilledButton)))
        .onPressed!();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      api.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    expect(calls.where((v) => v == 'play'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
