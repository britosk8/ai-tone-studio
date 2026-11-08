import 'package:shared_preferences/shared_preferences.dart';

/// Reset requested for the fresh generation round, applied once on upgrade.
/// Pedal backup files and connection settings are deliberately retained.
class LibraryReset {
  static const completedKey = 'library_reset_20261108_done';
  static Future<bool> applyOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(completedKey) == true) return false;
    final keys = <String>{
      'preset_pairs',
      'archived_preset_pairs',
      'test_library_archive_v156_snapshot',
      'mk300_pilot_before_cleanup_v1',
      'mk300_pilot_before_latest_cleanup',
      ...prefs.getKeys().where((key) => key.startsWith('pedal_reference_v1:')),
    };
    for (final key in keys) {
      if (prefs.containsKey(key) && !await prefs.remove(key)) {
        throw StateError('Não foi possível limpar a biblioteca.');
      }
    }
    // Retire the old cleanup migrations so they never archive fresh work.
    for (final key in [
      'test_library_archive_v156_done',
      'mk300_pilot_cleanup_v1_done',
      completedKey
    ]) {
      if (!await prefs.setBool(key, true)) {
        throw StateError('Não foi possível registrar a limpeza.');
      }
    }
    return true;
  }
}
