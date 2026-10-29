import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/preset_pair.dart';
import 'preset_store.dart';

/// User-authorized, one-time archive for the end of the hardware pilot.
/// Saves exact serialized records before removing any active library entry.
class PresetArchive {
  static const completedKey = 'test_library_archive_v156_done';
  static const snapshotKey = 'test_library_archive_v156_snapshot';
  static const recordsKey = 'archived_preset_pairs';
  static PresetPair decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return PresetPair(
        id: data['id'] as String,
        rhythm: PresetData.fromJson(Map<String, dynamic>.from(data['rhythm'])),
        lead: PresetData.fromJson(Map<String, dynamic>.from(data['lead'])),
        analysis: AudioAnalysis.fromJson(
            Map<String, dynamic>.from(data['analysis'] ?? {})));
  }

  static Future<List<PresetPair>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <PresetPair>[];
    for (final raw in prefs.getStringList(recordsKey) ?? <String>[]) {
      try {
        result.add(decode(raw));
      } catch (_) {/* Raw record retained for recovery. */}
    }
    return result;
  }

  static Future<int> archiveOnce(PresetStore store) async {
    await store.load();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(completedKey) == true) return 0;
    var snapshot = prefs.getStringList(snapshotKey);
    if (snapshot == null) {
      snapshot = List<String>.from(prefs.getStringList('preset_pairs') ?? []);
      if (!await prefs.setStringList(snapshotKey, snapshot)) {
        throw StateError('Não foi possível salvar o arquivo da biblioteca.');
      }
    }
    final archive = List<String>.from(prefs.getStringList(recordsKey) ?? []);
    for (final raw in snapshot) {
      if (!archive.contains(raw)) archive.add(raw);
    }
    if (!await prefs.setStringList(recordsKey, archive)) {
      throw StateError('Não foi possível conferir o arquivo dos presets.');
    }
    // Read back before touching active entries. The snapshot also makes retries
    // after interruption exclude any newly generated presets.
    final saved = prefs.getStringList(recordsKey) ?? [];
    if (snapshot.any((r) => !saved.contains(r))) {
      throw StateError('Arquivo de presets incompleto; biblioteca preservada.');
    }
    final ids = <String>{};
    for (final raw in prefs.getStringList('preset_pairs') ?? <String>[]) {
      if (!snapshot.contains(raw)) continue;
      try {
        ids.add((jsonDecode(raw) as Map)['id'] as String);
      } catch (_) {/* Preserved in snapshot. */}
    }
    final count = store.pairs.where((p) => ids.contains(p.id)).length;
    for (final id in ids) {
      await store.remove(id);
    }
    if (!await prefs.setBool(completedKey, true)) {
      throw StateError('Arquivo salvo; conclusão será conferida ao reiniciar.');
    }
    return count;
  }

  static Future<void> restore(PresetStore store, String id) async {
    await store.load();
    final prefs = await SharedPreferences.getInstance();
    final rows = List<String>.from(prefs.getStringList(recordsKey) ?? []);
    final matches = rows.where((raw) {
      try {
        return decode(raw).id == id;
      } catch (_) {
        return false;
      }
    }).toList();
    if (matches.isEmpty) throw StateError('Preset arquivado não encontrado.');
    // An active version wins: restoring never overwrites newer edits.
    if (!store.pairs.any((p) => p.id == id)) {
      await store.save(decode(matches.first));
    }
    rows.removeWhere(matches.contains);
    if (!await prefs.setStringList(recordsKey, rows)) {
      throw StateError(
          'Preset restaurado; o arquivo será mantido para recuperação.');
    }
  }
}
