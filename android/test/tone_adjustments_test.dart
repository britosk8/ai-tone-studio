import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';
import 'package:ai_tone_studio/services/tone_adjustments.dart';
import 'package:ai_tone_studio/services/preset_store.dart';

void main() {
  PresetPair pair() => PresetPair.fromJson(jsonDecode(
          File('test/fixtures/generated_mk300_pair.json').readAsStringSync())
      as Map<String, dynamic>);
  Map<String, dynamic> suggestion(PresetData preset) {
    final amp = preset.effectChain.firstWhere((b) => b.effectType == 'amp');
    return {
      'slot': amp.slot,
      'model_id': amp.modelId,
      'effect_type': 'amp',
      'parameter': 'Bass',
      'before': amp.parameters['Bass']!,
      'after': amp.parameters['Bass']! - 3
    };
  }

  test(
      'Ajuste espectral altera só o parâmetro escolhido e persiste para exportação/envio',
      () async {
    SharedPreferences.setMockInitialValues({});
    final original = pair();
    final updated =
        applyToneAdjustments(original.lead, [suggestion(original.lead)]);
    final oldAmp =
        original.lead.effectChain.firstWhere((b) => b.effectType == 'amp');
    final newAmp = updated.effectChain.firstWhere((b) => b.effectType == 'amp');
    expect(newAmp.parameters['Bass'], oldAmp.parameters['Bass']! - 3);
    expect(newAmp.parameters['Gain'], oldAmp.parameters['Gain']);
    expect(updated.catalogVersion, original.lead.catalogVersion);
    final store = PresetStore();
    await store.save(original.withPreset(updated));
    final reopened = PresetStore();
    await reopened.load();
    expect(
        reopened.pairs.single.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        newAmp.parameters['Bass']);
    expect(
        original.lead.effectChain
            .firstWhere((b) => b.effectType == 'amp')
            .parameters['Bass'],
        oldAmp.parameters['Bass']);
  });
  test('Preset alterado ou sugestão fora de escala é rejeitada', () {
    final preset = pair().lead;
    final stale = suggestion(preset)..['before'] = -1;
    expect(() => applyToneAdjustments(preset, [stale]), throwsStateError);
    final invalid = suggestion(preset)..['after'] = 999;
    expect(() => applyToneAdjustments(preset, [invalid]), throwsStateError);
    final wrong = suggestion(preset)..['model_id'] = '999';
    expect(() => applyToneAdjustments(preset, [wrong]), throwsStateError);
  });
}
