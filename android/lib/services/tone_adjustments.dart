import '../models/preset_pair.dart';

PresetData applyToneAdjustments(
    PresetData preset, List<Map<String, dynamic>> suggestions) {
  var chain = List<EffectBlock>.from(preset.effectChain);
  for (final suggestion in suggestions) {
    final index = chain.indexWhere((b) =>
        b.slot == suggestion['slot']?.toString() &&
        b.modelId == suggestion['model_id']?.toString() &&
        b.effectType == suggestion['effect_type']);
    if (index < 0) {
      throw StateError(
          'O preset mudou desde a comparação. Grave e analise novamente.');
    }
    final block = chain[index];
    final parameter = suggestion['parameter'] as String;
    final before = (suggestion['before'] as num).toDouble(),
        after = (suggestion['after'] as num).toDouble();
    final spec = block.parameterSpecs[parameter];
    if (block.parameters[parameter] != before ||
        spec == null ||
        !after.isFinite ||
        after < spec.min ||
        after > spec.max) {
      throw StateError(
          'Sugestão inválida ou parâmetro já alterado: $parameter');
    }
    final values = Map<String, double>.from(block.parameters);
    values[parameter] = after;
    chain[index] = block.copyWith(parameters: values);
  }
  return preset.copyWith(effectChain: chain);
}
