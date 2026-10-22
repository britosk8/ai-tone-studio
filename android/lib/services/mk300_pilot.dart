import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/preset_pair.dart';
import 'preset_import.dart';

/// Busca controlada do piloto Infest. Não é um modelo de matching treinado.
class Mk300Pilot {
  static const generatorId = 'mk300-infest-reference-candidates-v1';
  static bool isCandidate(PresetPair pair) =>
      pair.rhythm.generationMetadata['generator'] == generatorId;

  static String? candidateKey(PresetPair pair) {
    if (!isCandidate(pair)) return null;
    final meta = pair.rhythm.generationMetadata;
    final source = meta['source_pair_id'];
    final candidate = meta['candidate'];
    if (source is! String ||
        source.isEmpty ||
        !['A', 'B', 'C'].contains(candidate)) return null;
    return jsonEncode([generatorId, source, candidate]);
  }

  static List<PresetPair> existingFor(List<PresetPair> pairs, String sourceId) {
    final found = <String, PresetPair>{};
    for (final pair in pairs) {
      final meta = pair.rhythm.generationMetadata;
      if (candidateKey(pair) != null && meta['source_pair_id'] == sourceId) {
        found.putIfAbsent(meta['candidate'] as String, () => pair);
      }
    }
    return [
      for (final label in ['A', 'B', 'C'])
        if (found[label] != null) found[label]!
    ];
  }

  static bool supports(PresetPair pair) =>
      !isCandidate(pair) &&
      pair.rhythm.device == 'MK300' &&
      pair.lead.device == 'MK300' &&
      pair.rhythm.catalogVersion == '0.4.0' &&
      pair.lead.catalogVersion == '0.4.0' &&
      pair.rhythm.songTitle.toLowerCase().contains('infest');

  static Future<List<PresetPair>> generate(PresetPair source) async {
    if (!supports(source)) {
      throw StateError(
          'Selecione uma análise de Infest com ambos os presets MK300 atualizados.');
    }
    final catalog = jsonDecode(
            await rootBundle.loadString('assets/mk300_import_catalog.json'))
        as Map<String, dynamic>;
    final cabinets = source.rhythm.effectChain
        .where((b) => b.effectType == 'cabinet')
        .toList();
    if (cabinets.length != 1 ||
        !cabinets.single.parameters.containsKey('Low Cut') ||
        !cabinets.single.parameters.containsKey('High Cut')) {
      throw StateError(
          'Preset de origem sem os dois cortes do gabinete. Reanalise a referência no app.');
    }
    final cuts = cabinets.single.parameters;
    Map<String, dynamic> block(int slot, String type, String name,
        Map<String, num> values, String reason) {
      final models = (catalog['blocks'] as Map)[type] as List;
      final model = models
          .cast<Map<String, dynamic>>()
          .singleWhere((m) => m['name'] == name);
      final canonical = model['parameters'] as Map<String, dynamic>;
      // Cada knob será escrito explicitamente, sem herdar valores do slot alvo.
      if (values.keys.toSet().difference(canonical.keys.toSet()).isNotEmpty ||
          canonical.keys.toSet().difference(values.keys.toSet()).isNotEmpty) {
        throw StateError('Controles incompletos para $name');
      }
      return {
        'slot': '$slot',
        'effect_type': type,
        'enabled': true,
        'model_id': model['id'],
        'model_name': name,
        'parameters': values,
        'generated_confidence': 'low',
        'generation_rationale': reason,
      };
    }

    const ampValues = <String, num>{
      'Gain': 56,
      'Level': 60,
      'Bass': 58,
      'Middle': 50,
      'Treble': 60,
      'Reso': 35,
      'Pres': 58,
      'Bright': 45,
    };
    const driveValues = <String, num>{
      'Gain': 10,
      'Level': 80,
      'Bass': 42,
      'Middle': 58,
      'Treble': 52,
      'Reso': 0,
      'Pres': 50,
      'Bright': 60,
    };
    const choices = [
      ['A', '98MES_CH2_AMP', '11MESA_412_57'],
      ['B', '100MES_CH3_AM', '11MESA_412_57'],
      ['C', '98MES_CH2_AMP', '12MESA_412_EC'],
    ];
    final result = <PresetPair>[];
    for (final choice in choices) {
      final base = source.rhythm.toJson();
      base['name'] = 'Infest R2 ${choice[0]}';
      base['song_title'] = 'Infest — piloto MK300 ${choice[0]}';
      base['analysis_confidence'] = 'low';
      base['bpm'] = null;
      base['preset_volume'] = 60;
      base['center_pan'] = true;
      base['generation_metadata'] = {
        'generator': generatorId,
        'source_pair_id': source.id,
        'source_preset_id': source.rhythm.id,
        'reference': 'user-approved-Konig-MK20',
        'candidate': choice[0],
        'guitar': 'Konig Stratocaster SSS',
        'auditory_status': 'pending',
        'sonic_equivalence_verified': false,
        'cab_cuts_policy': 'same_raw_values_from_source_no_hz_conversion',
        'cab_cuts_raw': {
          'Low Cut': cuts['Low Cut'],
          'High Cut': cuts['High Cut']
        },
        'eq_policy': 'off_until_fractional_hardware_scale_verified',
        'lead_policy': 'copy_of_source_not_regenerated',
      };
      base['effect_chain'] = [
        block(0, 'noise_gate', 'AI Gate', {'Gate': 40, 'Bias': 50},
            'Ponto inicial da referência MK20; resposta na Konig/MK300 ainda em teste.'),
        block(1, 'drive', '22TS-9', driveValues,
            'Boost com Gain 10 e Level 80 da referência aprovada. Não demonstra equivalência entre aparelhos.'),
        block(2, 'amp', choice[1], ampValues,
            'Candidato por nome do catálogo. Mesmos controles nos três candidatos, sem resposta acústica calibrada.'),
        block(
            3,
            'cabinet',
            choice[2],
            {
              'Level': 80,
              'Low Cut': cuts['Low Cut']!,
              'High Cut': cuts['High Cut']!,
            },
            'Candidato por nome. Cortes raw preservados do preset ${source.rhythm.id}; não correspondem a 80 Hz/7,5 kHz confirmados.'),
      ];
      // O validador canônico também cria IDs novos para o par e ambos os presets.
      final candidate = await PresetImport.decode(jsonEncode({
        'format': 'ai-tone-studio',
        'version': 1,
        'rhythm_preset': base,
        'lead_preset': source.lead.toJson(),
        'analysis': {'gain_character': 'unknown', 'confidence': 'low'},
      }));
      result.add(candidate);
    }
    return result;
  }
}
