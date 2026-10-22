class ParameterSpec {
  final double min;
  final double max;
  final double step;
  final String unit;
  const ParameterSpec(
      {required this.min, required this.max, this.step = 1, this.unit = ''});
  static ParameterSpec? fromJson(Map<String, dynamic> json) {
    final min = (json['min'] as num?)?.toDouble();
    final max = (json['max'] as num?)?.toDouble();
    if (min == null ||
        max == null ||
        !min.isFinite ||
        !max.isFinite ||
        max <= min) return null;
    final step = (json['step'] as num?)?.toDouble() ?? 1;
    return ParameterSpec(
        min: min,
        max: max,
        step: step > 0 ? step : 1,
        unit: json['unit'] as String? ?? '');
  }

  Map<String, dynamic> toJson() =>
      {'min': min, 'max': max, 'step': step, 'unit': unit};
}

class EffectBlock {
  final String slot;
  final String effectType;
  final bool enabled;
  final String modelId;
  final String modelName;
  final Map<String, double> parameters;
  final Map<String, ParameterSpec> parameterSpecs;
  final String generatedConfidence;
  final String generationRationale;

  const EffectBlock({
    required this.slot,
    required this.effectType,
    required this.enabled,
    required this.modelId,
    required this.modelName,
    required this.parameters,
    this.parameterSpecs = const {},
    required this.generatedConfidence,
    required this.generationRationale,
  });

  factory EffectBlock.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'] as Map<String, dynamic>? ?? {};
    return EffectBlock(
      slot: (json['slot'] ?? '').toString(),
      effectType: json['effect_type'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      modelId: (json['model_id'] ?? '').toString(),
      modelName: json['model_name'] as String? ?? '',
      parameters: rawParams.map((k, v) => MapEntry(k, (v as num).toDouble())),
      parameterSpecs: {
        for (final entry
            in (json['parameter_specs'] as Map<String, dynamic>? ?? {}).entries)
          if (entry.value is Map<String, dynamic> &&
              ParameterSpec.fromJson(entry.value as Map<String, dynamic>) !=
                  null)
            entry.key:
                ParameterSpec.fromJson(entry.value as Map<String, dynamic>)!,
      },
      generatedConfidence: json['generated_confidence'] as String? ?? 'low',
      generationRationale: json['generation_rationale'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'effect_type': effectType,
        'enabled': enabled,
        'model_id': modelId,
        'model_name': modelName,
        'parameters': parameters,
        'parameter_specs':
            parameterSpecs.map((k, v) => MapEntry(k, v.toJson())),
        'generated_confidence': generatedConfidence,
        'generation_rationale': generationRationale,
      };

  EffectBlock copyWith({
    bool? enabled,
    Map<String, double>? parameters,
  }) {
    return EffectBlock(
      slot: slot,
      effectType: effectType,
      enabled: enabled ?? this.enabled,
      modelId: modelId,
      modelName: modelName,
      parameters: parameters ?? this.parameters,
      parameterSpecs: parameterSpecs,
      generatedConfidence: generatedConfidence,
      generationRationale: generationRationale,
    );
  }
}

class PresetData {
  final String id;
  final String name;
  final String device;
  final String role;
  final List<EffectBlock> effectChain;
  final String analysisConfidence;
  final String artist;
  final String songTitle;
  final String catalogVersion;
  final String sourceFileName;
  final double? bpm;
  final Map<String, dynamic> generationMetadata;
  final int? presetVolume;
  final bool centerPan;

  const PresetData({
    required this.id,
    required this.name,
    required this.device,
    required this.role,
    required this.effectChain,
    required this.analysisConfidence,
    required this.artist,
    required this.songTitle,
    this.catalogVersion = "",
    this.sourceFileName = "",
    this.bpm,
    this.generationMetadata = const {},
    this.presetVolume,
    this.centerPan = false,
  });

  factory PresetData.fromJson(Map<String, dynamic> json) {
    final chainJson = (json['effect_chain'] ?? []) as List;
    return PresetData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Preset',
      device: json['device'] as String? ?? '',
      role: json['role'] as String? ?? 'rhythm',
      effectChain: chainJson
          .map((e) => EffectBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
      analysisConfidence: json['analysis_confidence'] as String? ?? 'low',
      artist: json['artist'] as String? ?? '',
      songTitle: json['song_title'] as String? ?? '',
      catalogVersion: json['catalog_version'] as String? ?? '',
      sourceFileName: json['source_file_name'] as String? ?? '',
      bpm: (json['bpm'] as num?)?.toDouble(),
      generationMetadata:
          Map<String, dynamic>.from(json['generation_metadata'] as Map? ?? {}),
      presetVolume: json['preset_volume'] as int?,
      centerPan: json['center_pan'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'device': device,
        'role': role,
        'effect_chain': effectChain.map((e) => e.toJson()).toList(),
        'analysis_confidence': analysisConfidence,
        'artist': artist,
        'song_title': songTitle,
        'catalog_version': catalogVersion,
        'source_file_name': sourceFileName,
        'bpm': bpm,
        'generation_metadata': generationMetadata,
        'preset_volume': presetVolume,
        'center_pan': centerPan,
      };

  PresetData copyWith({List<EffectBlock>? effectChain, String? name}) {
    return PresetData(
      id: id,
      name: name ?? this.name,
      device: device,
      role: role,
      effectChain: effectChain ?? this.effectChain,
      analysisConfidence: analysisConfidence,
      artist: artist,
      songTitle: songTitle,
      catalogVersion: catalogVersion,
      sourceFileName: sourceFileName,
      bpm: bpm,
      generationMetadata: generationMetadata,
      presetVolume: presetVolume,
      centerPan: centerPan,
    );
  }
}

class SpectralProfile {
  final double low;
  final double lowMid;
  final double mid;
  final double highMid;
  final double high;
  final double brightness;

  const SpectralProfile({
    required this.low,
    required this.lowMid,
    required this.mid,
    required this.highMid,
    required this.high,
    required this.brightness,
  });

  factory SpectralProfile.fromJson(Map<String, dynamic> json) {
    return SpectralProfile(
      low: (json['low'] as num? ?? 0).toDouble(),
      lowMid: (json['low_mid'] as num? ?? 0).toDouble(),
      mid: (json['mid'] as num? ?? 0).toDouble(),
      highMid: (json['high_mid'] as num? ?? 0).toDouble(),
      high: (json['high'] as num? ?? 0).toDouble(),
      brightness: (json['brightness'] as num? ?? 0).toDouble(),
    );
  }
}

class AudioAnalysis {
  final String gainCharacter;
  final String confidence;
  final double distortionLevel;
  final double? estimatedBpm;
  final SpectralProfile spectral;
  final bool hasReverb;
  final bool hasDelay;
  final bool sourceSeparated, engineV2, possibleLayering;

  const AudioAnalysis({
    required this.gainCharacter,
    required this.confidence,
    required this.distortionLevel,
    required this.estimatedBpm,
    required this.spectral,
    required this.hasReverb,
    required this.hasDelay,
    this.sourceSeparated = false,
    this.engineV2 = false,
    this.possibleLayering = false,
  });

  factory AudioAnalysis.fromJson(Map<String, dynamic> json) {
    return AudioAnalysis(
      sourceSeparated: json['source_separated'] == true ||
          (json['engine_diagnostics'] as Map?)?['separation'] != null,
      engineV2: json['engine_mode'] == 'guitar_v2' ||
          (json['engine_diagnostics'] as Map?)?['engine'] == 'guitar_v2',
      possibleLayering: json['possible_layering'] == true ||
          ((json['engine_diagnostics'] as Map?)?['features']
                  as Map?)?['possible_layering'] ==
              true,
      gainCharacter: json['gain_character'] as String? ?? 'unknown',
      confidence: json['confidence'] as String? ?? 'low',
      distortionLevel: (json['distortion_level'] as num? ?? 0).toDouble(),
      estimatedBpm: (json['estimated_bpm'] as num?)?.toDouble(),
      spectral: SpectralProfile.fromJson(
        json['spectral_profile'] as Map<String, dynamic>? ?? {},
      ),
      hasReverb: (json['effect_presence']
              as Map<String, dynamic>?)?['reverb_probability'] as bool? ??
          false,
      hasDelay: (json['effect_presence']
              as Map<String, dynamic>?)?['delay_probability'] as bool? ??
          false,
    );
  }
}

class PresetPair {
  final String id;
  final PresetData rhythm;
  final PresetData lead;
  final AudioAnalysis analysis;

  const PresetPair({
    required this.id,
    required this.rhythm,
    required this.lead,
    required this.analysis,
  });

  PresetPair withPreset(PresetData preset) => PresetPair(
        id: id,
        rhythm: preset.role == 'rhythm' ? preset : rhythm,
        lead: preset.role == 'lead' ? preset : lead,
        analysis: analysis,
      );

  Map<String, dynamic> exportJson() => {
        'format': 'ai-tone-studio',
        'version': 1,
        'id': id,
        'rhythm_preset': rhythm.toJson(),
        'lead_preset': lead.toJson(),
      };

  String toReadableGuide() {
    final lines = <String>[
      'AI TONE STUDIO — CONFIGURAÇÃO MANUAL',
      'Estimativas de timbre; compatibilidade do catálogo ainda depende de confirmação no equipamento.',
      ''
    ];
    for (final preset in [rhythm, lead]) {
      lines.addAll([
        '=== ${preset.name} ===',
        'Pedaleira: ${preset.device}',
        'Função: ${preset.role == 'rhythm' ? 'Base' : 'Solo'}',
        'Música: ${preset.artist} — ${preset.songTitle}',
        'Confiança: ${preset.analysisConfidence}'
      ]);
      for (final block in preset.effectChain) {
        lines.add(
            '${block.modelName}: ${block.enabled ? 'LIGADO' : 'DESLIGADO'}');
        for (final entry in block.parameters.entries) {
          lines.add(
              '  ${entry.key}: ${entry.value} ${block.parameterSpecs[entry.key]?.unit ?? ''}');
        }
      }
      lines.add('');
    }
    return lines.join('\n');
  }

  factory PresetPair.fromJson(Map<String, dynamic> json) {
    return PresetPair(
      id: (json['id'] as String?)?.isNotEmpty == true
          ? json['id'] as String
          : (json['rhythm_preset'] as Map<String, dynamic>?)?['id']
                  as String? ??
              '',
      rhythm: PresetData.fromJson(
        json['rhythm_preset'] as Map<String, dynamic>? ?? {},
      ),
      lead: PresetData.fromJson(
        json['lead_preset'] as Map<String, dynamic>? ?? {},
      ),
      analysis: AudioAnalysis.fromJson(
        json['analysis'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class AnalysisJob {
  final String jobId;
  final String status;
  final int progressPercent;
  final String? pairId;
  final String? errorMessage;
  final String? progressMessage;

  const AnalysisJob({
    required this.jobId,
    required this.status,
    required this.progressPercent,
    this.pairId,
    this.errorMessage,
    this.progressMessage,
  });

  factory AnalysisJob.fromJson(Map<String, dynamic> json) {
    return AnalysisJob(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      progressPercent: json['progress_percent'] as int? ?? 0,
      pairId: json['pair_id'] as String?,
      errorMessage: (json['error_message'] ?? json['error']) as String?,
      progressMessage: json['progress'] as String?,
    );
  }

  bool get isDone => status == 'done' || status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isRunning => status == 'running' || status == 'processing';
}
