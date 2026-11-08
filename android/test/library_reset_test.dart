import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tone_studio/services/library_reset.dart';

void main() {
  test('reset autorizado remove biblioteca e arquivos de teste uma vez',
      () async {
    SharedPreferences.setMockInitialValues({
      'preset_pairs': ['antigo'],
      'archived_preset_pairs': ['arquivo'],
      'test_library_archive_v156_snapshot': ['snapshot'],
      'mk300_pilot_before_cleanup_v1': ['teste'],
      'pedal_reference_v1:old': 'old',
      'backend_url': 'http://servidor:8000',
    });
    expect(await LibraryReset.applyOnce(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('preset_pairs'), isFalse);
    expect(prefs.containsKey('archived_preset_pairs'), isFalse);
    expect(prefs.containsKey('pedal_reference_v1:old'), isFalse);
    expect(prefs.getString('backend_url'), 'http://servidor:8000');
    await prefs.setStringList('preset_pairs', ['novo']);
    expect(await LibraryReset.applyOnce(), isFalse);
    expect(prefs.getStringList('preset_pairs'), ['novo']);
  });
}
