import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'v1_flow_test.dart' show fixture;
import 'package:ai_tone_studio/services/api_service.dart';
import 'package:ai_tone_studio/widgets/tone_states_panel.dart';

class StateApi extends ApiService {
  int analyses = 0, pairFetches = 0;
  bool weakFirst = false;
  String? generatedRole, generatedCharacter;
  @override
  Future<Map<String, dynamic>> generateToneState(String pairId, String stateId,
      String role, String device, String character, String? researchId,
      {String? researchRevision}) async {
    generatedRole = role;
    generatedCharacter = character;
    return {'pair_id': 'pair-001', 'role': role, 'reused': true};
  }

  @override
  Future<PresetPair> getPresets(String id) async {
    pairFetches++;
    return PresetPair.fromJson(fixture());
  }

  String? artist, song, version;
  @override
  Future<Map<String, dynamic>> toneStates(String pairId) async => {
        'maps': [
          {
            'states': [
              {
                'id': 'clean-left',
                'reference_quality': {
                  'eligible': !weakFirst,
                  'message':
                      weakFirst ? 'Guitarra muito fraca neste trecho.' : null
                },
                'label': 'Limpo provável — L',
                'character': 'clean',
                'representative': {'start_seconds': 195, 'duration_seconds': 12}
              },
              {
                'id': 'dirty-left',
                'label': 'Distorcido provável — L',
                'character': 'distorted',
                'representative': {'start_seconds': 120, 'duration_seconds': 12}
              }
            ]
          }
        ],
        'research': {
          'version': 'unknown',
          'sources': [
            {
              'title': 'Entrevista primária',
              'url': 'https://www.premierguitar.com/example',
              'context': 'artist_live',
              'note': 'Não comprova a gravação.',
              'available': true
            }
          ]
        }
      };
  @override
  Future<Map<String, dynamic>> analyzeToneStates(String pairId, String version,
      {bool refresh = false, String? artist, String? songTitle}) async {
    analyses++;
    this.version = version;
    this.artist = artist;
    song = songTitle;
    return toneStates(pairId);
  }
}

void main() {
  testWidgets('Estados mantêm base e solo independentes e contexto das fontes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = StateApi();
    await tester.pumpWidget(Provider<ApiService>.value(
      value: api,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ToneStatesPanel(
              pairId: 'everlong',
              rhythmDevice: 'MK300',
              leadDevice: 'MK300',
              artist: 'Foo Fighters',
              songTitle: 'Everlong',
              onGenerated: (_, __) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.text('2 estados propostos — gerar base ou solo'), findsOneWidget);
    await tester.tap(find.text('Timbres ao longo da música'));
    await tester.pumpAndSettle();
    expect(find.text('Limpo provável — L'), findsOneWidget);
    expect(find.text('Distorcido provável — L'), findsOneWidget);
    expect(find.text('Gerar base deste timbre'), findsNWidgets(2));
    expect(find.text('Gerar solo deste timbre'), findsNWidgets(2));
    await tester.tap(find.text('Atualizar análise dos timbres'));
    await tester.pumpAndSettle();
    expect(api.artist, 'Foo Fighters');
    expect(api.song, 'Everlong');
    expect(api.analyses, 1);
    await tester.ensureVisible(
        find.text('Fontes pesquisadas e contexto do equipamento'));
    await tester.tap(find.text('Fontes pesquisadas e contexto do equipamento'));
    await tester.pumpAndSettle();
    expect(find.textContaining('artist_live'), findsOneWidget);
    expect(find.textContaining('Não comprova a gravação.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gerar solo reutiliza variante local e preserva edição',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final api = StateApi();
    final store = PresetStore();
    final raw = fixture();
    (raw['rhythm_preset'] as Map)['name'] = 'Editado localmente';
    await store.save(PresetPair.fromJson(raw));
    String? navigatedRole, navigatedId;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<PresetStore>.value(value: store),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ToneStatesPanel(
        pairId: 'everlong',
        rhythmDevice: 'MK300',
        leadDevice: 'MK300',
        onGenerated: (id, role) async {
          navigatedId = id;
          navigatedRole = role;
        },
      )))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timbres ao longo da música'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar solo deste timbre').first);
    await tester.pumpAndSettle();
    expect(api.generatedRole, 'lead');
    expect(api.generatedCharacter, 'clean');
    expect(navigatedRole, 'lead');
    expect(navigatedId, 'pair-001');
    expect(api.pairFetches, 0);
    expect(store.pairs.single.rhythm.name, 'Editado localmente');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Trecho fraco fica visível com aviso e não pode gerar base nem solo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = StateApi()..weakFirst = true;
    await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: ToneStatesPanel(
                        pairId: 'infest',
                        rhythmDevice: 'MK20',
                        leadDevice: 'MK300',
                        onGenerated: (_, __) async {}))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timbres ao longo da música'));
    await tester.pumpAndSettle();
    expect(find.text('Guitarra muito fraca neste trecho.'), findsOneWidget);
    final base = tester
        .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Gerar base deste timbre'))
        .toList();
    final solo = tester
        .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Gerar solo deste timbre'))
        .toList();
    expect(base.first.onPressed, isNull);
    expect(solo.first.onPressed, isNull);
    expect(base.last.onPressed, isNotNull);
    expect(solo.last.onPressed, isNotNull);
    expect(api.generatedRole, isNull);
  });
}
