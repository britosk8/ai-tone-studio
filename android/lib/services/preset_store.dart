import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/preset_pair.dart';

class PresetStore extends ChangeNotifier {
  final List<PresetPair> _pairs = [];
  bool _loaded = false;
  Future<void>? _loading;

  List<PresetPair> get pairs => List.unmodifiable(_pairs);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('preset_pairs') ?? [];
    _pairs.clear();
    for (final item in raw) {
      try {
        final decoded = json.decode(item) as Map<String, dynamic>;
        // Carrega os presets completos; recupera IDs ausentes da versão anterior.
        _pairs.add(PresetPair(
          id: (decoded['id'] as String?)?.isNotEmpty == true
              ? decoded['id'] as String
              : (decoded['rhythm'] as Map<String, dynamic>)['id'] as String,
          rhythm:
              PresetData.fromJson(decoded['rhythm'] as Map<String, dynamic>),
          lead: PresetData.fromJson(decoded['lead'] as Map<String, dynamic>),
          analysis: AudioAnalysis.fromJson(
            decoded['analysis'] as Map<String, dynamic>? ?? {},
          ),
        ));
      } catch (_) {}
    }
    await _persist();
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(PresetPair pair) async {
    await load();
    if (pair.id.isEmpty) throw StateError("Preset sem identificador");
    final original = List<PresetPair>.from(_pairs);
    final existing = _pairs.indexWhere((p) => p.id == pair.id);
    if (existing >= 0) {
      _pairs[existing] = pair;
    } else {
      _pairs.insert(0, pair);
    }
    try {
      await _persist();
    } catch (_) {
      _pairs.clear();
      _pairs.addAll(original);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> saveNewBatch(List<PresetPair> pairs) async {
    await load();
    final ids = pairs.map((p) => p.id).toSet();
    if (pairs.isEmpty ||
        ids.length != pairs.length ||
        ids.contains('') ||
        _pairs.any((p) => ids.contains(p.id))) {
      throw StateError('Candidatos sem identidade nova ou duplicados');
    }
    final original = List<PresetPair>.from(_pairs);
    _pairs.insertAll(0, pairs);
    try {
      await _persist();
    } catch (_) {
      _pairs.clear();
      _pairs.addAll(original);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> remove(String pairId) async {
    await load();
    final original = List<PresetPair>.from(_pairs);
    _pairs.removeWhere((p) => p.id == pairId);
    try {
      await _persist();
    } catch (_) {
      _pairs.clear();
      _pairs.addAll(original);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _pairs
        .map((p) => json.encode({
              'id': p.id,
              'rhythm': p.rhythm.toJson(),
              'lead': p.lead.toJson(),
              'analysis': {
                'gain_character': p.analysis.gainCharacter,
                'confidence': p.analysis.confidence,
                'distortion_level': p.analysis.distortionLevel,
                'estimated_bpm': p.analysis.estimatedBpm,
                'spectral_profile': {
                  'low': p.analysis.spectral.low,
                  'low_mid': p.analysis.spectral.lowMid,
                  'mid': p.analysis.spectral.mid,
                  'high_mid': p.analysis.spectral.highMid,
                  'high': p.analysis.spectral.high,
                  'brightness': p.analysis.spectral.brightness,
                },
                'effect_presence': {
                  'reverb_probability': p.analysis.hasReverb,
                  'delay_probability': p.analysis.hasDelay,
                },
              },
            }))
        .toList();
    if (!await prefs.setStringList('preset_pairs', serialized)) {
      throw StateError('Falha ao salvar a biblioteca');
    }
  }
}
