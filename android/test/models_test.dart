import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/models/preset_pair.dart';

void main() {
  group('PresetPair models', () {
    test('EffectBlock desserializa corretamente', () {
      final json = {
        'slot': '3',
        'effect_type': 'amp',
        'enabled': true,
        'model_id': '42',
        'model_name': 'JVM410H',
        'parameters': {'Gain': 70.0, 'Bass': 55.0, 'Mid': 60.0, 'Treble': 50.0},
        'generated_confidence': 'medium',
        'generation_rationale': 'High gain character detected',
      };
      final block = EffectBlock.fromJson(json);
      expect(block.slot, '3');
      expect(block.effectType, 'amp');
      expect(block.modelId, '42');
      expect(block.parameters['Gain'], 70.0);
      expect(block.generatedConfidence, 'medium');
    });

    test('EffectBlock copyWith mantém campos não alterados', () {
      const block = EffectBlock(
        slot: '4',
        effectType: 'drive',
        enabled: true,
        modelId: '5',
        modelName: 'RAT',
        parameters: {'Level': 80.0, 'Filter': 40.0},
        generatedConfidence: 'low',
        generationRationale: '',
      );

      final toggled = block.copyWith(enabled: false);
      expect(toggled.enabled, false);
      expect(toggled.modelName, 'RAT');
      expect(toggled.parameters['Level'], 80.0);
    });

    test('PresetData desserializa com lista de blocos', () {
      final json = {
        'id': 'abc123',
        'name': 'Metal Base',
        'device': 'MK20',
        'role': 'rhythm',
        'effect_chain': [
          {
            'slot': '2',
            'effect_type': 'noise_gate',
            'enabled': true,
            'model_id': '0',
            'model_name': 'GATE',
            'parameters': {'Threshold': 40.0},
            'generated_confidence': 'low',
            'generation_rationale': '',
          },
        ],
        'analysis_confidence': 'low',
        'artist': 'Metallica',
        'song_title': 'Enter Sandman',
      };

      final preset = PresetData.fromJson(json);
      expect(preset.artist, 'Metallica');
      expect(preset.effectChain.length, 1);
      expect(preset.effectChain[0].effectType, 'noise_gate');
    });

    test('AudioAnalysis desserializa BPM opcional', () {
      final json = {
        'gain_character': 'high_gain',
        'confidence': 'low',
        'distortion_level': 0.8,
        'estimated_bpm': 120.0,
        'spectral_profile': {
          'low': 0.6,
          'low_mid': 0.5,
          'mid': 0.4,
          'high_mid': 0.7,
          'high': 0.3,
          'brightness': 0.6,
        },
        'effect_presence': {
          'reverb_probability': true,
          'delay_probability': false,
        },
      };
      final analysis = AudioAnalysis.fromJson(json);
      expect(analysis.gainCharacter, 'high_gain');
      expect(analysis.estimatedBpm, 120.0);
      expect(analysis.hasReverb, true);
      expect(analysis.hasDelay, false);
      expect(analysis.spectral.high, 0.3);
    });

    test('AnalysisJob reconhece status done', () {
      final job = AnalysisJob.fromJson({
        'job_id': 'job-001',
        'status': 'done',
        'progress_percent': 100,
        'pair_id': 'pair-xyz',
      });
      expect(job.isDone, true);
      expect(job.isFailed, false);
      expect(job.pairId, 'pair-xyz');
    });

    test('AnalysisJob reconhece status failed', () {
      final job = AnalysisJob.fromJson({
        'job_id': 'job-002',
        'status': 'failed',
        'progress_percent': 0,
        'error_message': 'Formato não suportado',
      });
      expect(job.isFailed, true);
      expect(job.isDone, false);
      expect(job.errorMessage, 'Formato não suportado');
    });
  });
}
