import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/preset_pair.dart';

class PresetImport {
  static const maxBytes = 1024 * 1024;
  static String _id() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<PresetPair> decode(String text) async {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('JSON acima do limite de 1 MB.');
    }
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> ||
        value['format'] != 'ai-tone-studio' ||
        value['version'] != 1) {
      throw const FormatException(
          'Selecione um par de presets exportado pelo AI Tone Studio (versão 1).');
    }
    final catalog = jsonDecode(
            await rootBundle.loadString('assets/mk300_import_catalog.json'))
        as Map<String, dynamic>;
    Map<String, dynamic> preset(String key, String role) {
      final raw = value[key];
      if (raw is! Map<String, dynamic> ||
          raw['device'] != 'MK300' ||
          raw['catalog_version'] != catalog['catalog_version'] ||
          raw['role'] != role) {
        throw const FormatException(
            'A importação aceita pares MK300 com catálogo 0.4.0 e funções base/solo válidas.');
      }
      if (raw['name'] is! String || (raw['name'] as String).trim().isEmpty) {
        throw const FormatException('Preset sem nome.');
      }
      final volume = raw['preset_volume'];
      if ((volume != null && (volume is! int || volume < 0 || volume > 100)) ||
          (raw['center_pan'] != null && raw['center_pan'] is! bool)) {
        throw const FormatException('Volume ou panorama de preset inválido.');
      }
      final blocks = raw['effect_chain'];
      if (blocks is! List || blocks.isEmpty || blocks.length > 11) {
        throw const FormatException('Cadeia de efeitos inválida.');
      }
      final seenTypes = <String>{}, seenSlots = <int>{};
      final validated = <Map<String, dynamic>>[];
      for (final item in blocks) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Bloco de efeito inválido.');
        }
        final type = item['effect_type'];
        final slot = int.tryParse(item['slot'].toString());
        if (type is! String ||
            !seenTypes.add(type) ||
            slot == null ||
            slot < 0 ||
            slot > 10 ||
            !seenSlots.add(slot) ||
            item['enabled'] is! bool) {
          throw const FormatException('Bloco duplicado ou posição inválida.');
        }
        final models = (catalog['blocks'] as Map)[type];
        if (models is! List) {
          throw const FormatException('Tipo de efeito desconhecido.');
        }
        final model = models
            .whereType<Map<String, dynamic>>()
            .where((m) =>
                m['id'] == item['model_id'].toString() &&
                m['name'] == item['model_name'])
            .firstOrNull;
        if (model == null) {
          throw const FormatException(
              'Nome/ID do modelo não corresponde ao catálogo MK300.');
        }
        final params = item['parameters'];
        if (params is! Map<String, dynamic>) {
          throw const FormatException('Parâmetros inválidos.');
        }
        final canonical = model['parameters'] as Map<String, dynamic>;
        for (final entry in params.entries) {
          final spec = canonical[entry.key];
          final v = entry.value;
          if (spec is! Map<String, dynamic> ||
              v is! num ||
              !v.isFinite ||
              v != v.roundToDouble() ||
              v < (spec['min'] as num) ||
              v > (spec['max'] as num)) {
            throw FormatException('Parâmetro fora do catálogo: ${entry.key}.');
          }
        }
        validated.add({
          ...item,
          'slot': slot.toString(),
          'parameter_specs': {
            for (final key in params.keys) key: canonical[key]
          }
        });
      }
      // Uma cópia nova evita sobrescrever edições ou presets existentes na biblioteca.
      return {...raw, 'id': _id(), 'effect_chain': validated};
    }

    return PresetPair.fromJson({
      ...value,
      'id': _id(),
      'rhythm_preset': preset('rhythm_preset', 'rhythm'),
      'lead_preset': preset('lead_preset', 'lead')
    });
  }
}
