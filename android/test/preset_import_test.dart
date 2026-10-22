import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/preset_import.dart';
import 'package:ai_tone_studio/services/preset_store.dart';
import 'package:ai_tone_studio/services/device/preset_transfer.dart';
import 'package:ai_tone_studio/services/device/mk300_protocol.dart';
import 'device_transfer_test.dart' as hardware;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String source() =>
      File('test/fixtures/infest_mk300_piloto_r1.json').readAsStringSync();
  Map<String, dynamic> raw() => jsonDecode(source()) as Map<String, dynamic>;
  test('Importa os dois presets independentes de Infest com novas identidades',
      () async {
    final a = await PresetImport.decode(source());
    final b = await PresetImport.decode(source());
    expect(a.id, isNot(b.id));
    expect(a.rhythm.id, isNot(b.rhythm.id));
    expect(a.lead.id, isNot(b.lead.id));
    expect(a.rhythm.name, 'Infest Base R1');
    expect(a.lead.name, 'Infest Solo R1');
    expect(
        a.rhythm.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        75);
    expect(
        a.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        60);
  });
  test('Importação persiste sem sobrescrever uma versão editada anteriormente',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = PresetStore();
    final original = await PresetImport.decode(source());
    final edited =
        original.withPreset(original.lead.copyWith(name: 'Minha edição'));
    await store.save(edited);
    await store.save(await PresetImport.decode(source()));
    final loaded = PresetStore();
    await loaded.load();
    expect(loaded.pairs.length, 2);
    expect(loaded.pairs.firstWhere((p) => p.id == edited.id).lead.name,
        'Minha edição');
    final roundtrip =
        await PresetImport.decode(jsonEncode(loaded.pairs.first.exportJson()));
    expect(roundtrip.rhythm.effectChain.map((b) => b.toJson()).toList(),
        loaded.pairs.first.rhythm.effectChain.map((b) => b.toJson()).toList());
  });
  test('Limites fornecidos pelo arquivo não autorizam valores fora do catálogo',
      () async {
    final data = raw();
    final amp = (data['rhythm_preset']['effect_chain'] as List)
        .firstWhere((b) => b['effect_type'] == 'amp');
    amp['parameter_specs']['Gain']['max'] = 30000;
    amp['parameters']['Gain'] = 500;
    await expectLater(
        PresetImport.decode(jsonEncode(data)), throwsFormatException);
    amp['parameters']['Gain'] = 33;
    final imported = await PresetImport.decode(jsonEncode(data));
    expect(
        imported.rhythm.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameterSpecs['Gain']!
            .max,
        100);
  });
  test(
      'JSON inválido, catálogo antigo, modelo incorreto e bloco duplicado são rejeitados',
      () async {
    await expectLater(PresetImport.decode('{}'), throwsFormatException);
    for (final kind in ['catalog', 'device', 'model', 'duplicate']) {
      final data = raw();
      final preset = data['lead_preset'];
      if (kind == 'catalog') preset['catalog_version'] = '0.3.0';
      if (kind == 'device') preset['device'] = 'MK20';
      if (kind == 'model') {
        preset['effect_chain'][0]['model_name'] = 'Modelo inventado';
      }
      if (kind == 'duplicate') {
        preset['effect_chain'].add(preset['effect_chain'][0]);
      }
      await expectLater(
          PresetImport.decode(jsonEncode(data)), throwsFormatException);
    }
    await expectLater(PresetImport.decode(' ' * (PresetImport.maxBytes + 1)),
        throwsFormatException);
  });
  test('Presets importados geram imagens MK300 válidas sem enviar ao pedal',
      () async {
    final imported = await PresetImport.decode(source());
    final transport = hardware.FakeTransport(hardware.fixtureImage());
    final session = Mk300TransferSession(transport, await hardware.catalog(),
        deviceLabel: 'Teste offline');
    for (final preset in [imported.rhythm, imported.lead]) {
      final image =
          session.buildImage(preset, preset.name, hardware.fixtureImage());
      Mk300Protocol.validateImage(image, session.counts);
      expect(image.length, 448);
      expect(Mk300Protocol.name(image), preset.name);
      expect(image[54 + 4], 1); // 2J900_OD, conferido no catálogo.
      expect(image[43 + 3], 0); // Drive adicional desligado.
      expect(image[43 + 9], 0); // Reverb desligado.
    }
    expect(transport.writes, isEmpty);
    await session.close();
  });
}
