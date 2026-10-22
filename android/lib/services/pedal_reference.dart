import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/preset_pair.dart';
import 'device/mk300_protocol.dart';

class PedalReference {
  final int slot;
  final String connection, capturedAt;
  final Uint8List image;
  PedalReference(
      {required this.slot,
      required this.connection,
      required this.capturedAt,
      required Uint8List image})
      : image = Uint8List.fromList(image) {
    if (slot < 1 || slot > 160 || image.length != Mk300Protocol.size) {
      throw const FormatException('Referência MK300 inválida');
    }
  }

  String get name => Mk300Protocol.name(image);

  PresetData decode(Map<int, Map<String, dynamic>> catalog) {
    Mk300Protocol.validateImage(
        image,
        catalog.map(
            (id, block) => MapEntry(id, (block['models'] as List).length)));
    const types = [
      'wah',
      'compressor',
      'noise_gate',
      'drive',
      'amp',
      'cabinet',
      'eq',
      'modulation',
      'delay',
      'reverb',
      'volume'
    ];
    final bytes = ByteData.sublistView(image);
    final blocks = <EffectBlock>[];
    for (var order = 0; order < 11; order++) {
      final id = image[32 + order];
      final modelId = image[54 + id];
      final model = (catalog[id]!['models'] as List)[modelId] as Map;
      final knobs = List<String>.from(model['knobs'] as List);
      if (knobs.length > 12) {
        throw const FormatException('Bloco com controles incompatíveis');
      }
      blocks.add(EffectBlock(
          slot: '$order',
          effectType: types[id],
          enabled: image[43 + id] == 1,
          modelId: '$modelId',
          modelName: model['name'] as String,
          parameters: {
            for (var k = 0; k < knobs.length; k++)
              knobs[k]:
                  bytes.getInt16(66 + 24 * id + 2 * k, Endian.little).toDouble()
          },
          generatedConfidence: 'low',
          generationRationale:
              'Leitura do slot $slot; valores raw sem conversão física.'));
    }
    return PresetData(
        id: 'reference-$slot',
        name: name,
        device: 'MK300',
        role: 'reference',
        effectChain: blocks,
        analysisConfidence: 'low',
        artist: '',
        songTitle: '',
        catalogVersion: '0.4.0',
        presetVolume: bytes.getUint16(24, Endian.little),
        centerPan: bytes.getInt16(28, Endian.little) == 0,
        bpm: bytes.getUint16(26, Endian.little).toDouble());
  }

  Map<String, dynamic> toJson() => {
        'format': 'ai-tone-pedal-reference',
        'version': 1,
        'device': 'MK300',
        'slot': slot,
        'connection': connection,
        'captured_at': capturedAt,
        'image_base64': base64Encode(image)
      };

  factory PedalReference.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'ai-tone-pedal-reference' ||
        json['version'] != 1 ||
        json['device'] != 'MK300') {
      throw const FormatException('Formato da referência incompatível');
    }
    return PedalReference(
        slot: json['slot'] as int,
        connection: json['connection'] as String,
        capturedAt: json['captured_at'] as String,
        image: base64Decode(json['image_base64'] as String));
  }
}

class PedalReferenceRepository {
  static String _key(String pairId, String role) {
    if (pairId.isEmpty || !['rhythm', 'lead'].contains(role)) {
      throw ArgumentError('Análise ou função inválida');
    }
    return 'pedal_reference_v1:${jsonEncode([pairId, role])}';
  }

  Future<PedalReference?> load(String pairId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(pairId, role));
    return raw == null
        ? null
        : PedalReference.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(
      String pairId, String role, PedalReference reference) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key(pairId, role), jsonEncode(reference.toJson()))) {
      throw StateError('Não foi possível salvar a referência');
    }
  }
}

class ConfigurationDifference {
  final String label, generated, reference;
  const ConfigurationDifference(this.label, this.generated, this.reference);
  bool get changed => generated != reference;
}

List<ConfigurationDifference> comparePedalConfiguration(
    PresetData generated, PresetData reference) {
  String value(double? v) => v == null
      ? 'Ausente'
      : v == v.roundToDouble()
          ? '${v.toInt()}'
          : '$v';
  final rows = <ConfigurationDifference>[
    ConfigurationDifference(
        'Cadeia ativa',
        generated.effectChain
            .where((b) => b.enabled)
            .map((b) => b.modelName)
            .join(' → '),
        reference.effectChain
            .where((b) => b.enabled)
            .map((b) => b.modelName)
            .join(' → ')),
    ConfigurationDifference(
        'Volume do preset',
        generated.presetVolume?.toString() ?? 'Herdado do destino',
        reference.presetVolume.toString()),
    ConfigurationDifference(
        'Panorama',
        generated.centerPan ? 'Centro' : 'Herdado do destino',
        reference.centerPan ? 'Centro' : 'Fora do centro'),
  ];
  final a = {for (final b in generated.effectChain) b.effectType: b};
  final b = {
    for (final block in reference.effectChain) block.effectType: block
  };
  const labels = {
    'wah': 'Wah',
    'compressor': 'Compressor',
    'noise_gate': 'Noise gate',
    'drive': 'Drive',
    'amp': 'Amplificador',
    'cabinet': 'Gabinete',
    'eq': 'EQ',
    'modulation': 'Modulação',
    'delay': 'Delay',
    'reverb': 'Reverb',
    'volume': 'Volume'
  };
  for (final type in {...a.keys, ...b.keys}) {
    final label = labels[type] ?? type;
    final left = a[type], right = b[type];
    rows.add(ConfigurationDifference(
        '$label • estado',
        left?.enabled == true ? 'Ligado' : 'Desligado',
        right?.enabled == true ? 'Ligado' : 'Desligado'));
    if (left?.enabled != true && right?.enabled != true) continue;
    rows.add(ConfigurationDifference('$label • modelo',
        left?.modelName ?? 'Ausente', right?.modelName ?? 'Ausente'));
    final sameModel =
        left?.modelName == right?.modelName && left?.modelId == right?.modelId;
    for (final knob in {
      ...?left?.parameters.keys,
      ...?right?.parameters.keys
    }) {
      rows.add(ConfigurationDifference(
          '$label • $knob${sameModel ? '' : ' (modelos distintos)'}',
          value(left?.parameters[knob]),
          value(right?.parameters[knob])));
    }
  }
  return rows;
}
