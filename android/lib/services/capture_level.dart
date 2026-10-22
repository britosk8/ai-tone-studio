import '../models/preset_pair.dart';

/// Reduz apenas o volume global documentado; não corrige clipping já gravado.
PresetData reduceCaptureLevel(PresetData preset) {
  final before = preset.presetVolume;
  if (preset.device != 'MK300' || before == null || before <= 1) {
    throw StateError(
        'Volume global do preset indisponível ou no mínimo. Confira o nível de envio USB na pedaleira.');
  }
  final after = (before * .75).floor().clamp(1, 100);
  return PresetData.fromJson({
    ...preset.toJson(),
    'preset_volume': after,
    'generation_metadata': {
      ...preset.generationMetadata,
      'capture_level_adjustment': {
        'before': before,
        'after': after,
        'reason': 'clipping_on_usb_capture',
        'usb_response_verified': false
      }
    }
  });
}
