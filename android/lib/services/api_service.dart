import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/preset_pair.dart';
import 'pedal_reference.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? errorCode;
  final String? recordingId;
  ApiException(this.message,
      {this.statusCode, this.errorCode, this.recordingId});
  @override
  String toString() =>
      'ApiException($statusCode): $message${recordingId == null ? '' : ' Gravação preservada no backend.'}';
}

class ApiService {
  String _baseUrl = 'http://192.168.15.8:8000';

  String get baseUrl => _baseUrl;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("backend_url");
    if (saved != null && saved.isNotEmpty) setBaseUrl(saved);
  }

  void setBaseUrl(String url) {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
  }

  Future<List<PresetData>> getToneCandidates(String pairId, String role) async {
    final data = await _get('/api/v1/presets/$pairId/candidates/$role');
    return (data['candidates'] as List)
        .map((e) => PresetData.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<int>> downloadGuitarStem(String pairId, String role) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/api/v1/presets/$pairId/stems/$role/guitar'))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      _handleResponse(response);
    }
    return response.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> referenceLibrary() async {
    final data = await _get('/api/v1/reference-library');
    return (data['songs'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> referenceInfo(String pairId, String role) =>
      _get('/api/v1/presets/$pairId/reference/$role');
  Future<Map<String, dynamic>> setReferenceRegion(
      String pairId, String role, double start, double duration) async {
    final response = await http
        .put(Uri.parse('$_baseUrl/api/v1/presets/$pairId/reference/$role'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'start_seconds': start, 'duration_seconds': duration}))
        .timeout(const Duration(seconds: 60));
    return _handleResponse(response);
  }

  Future<AnalysisJob> submitSavedAnalysis(
      {required String pairId,
      required String rhythmDevice,
      required String leadDevice,
      required double rhythmStart,
      required double rhythmDuration,
      required double leadStart,
      required double leadDuration}) async {
    final response = await http
        .post(Uri.parse('$_baseUrl/api/v1/analyze-saved'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'pair_id': pairId,
              'analyze_states': true,
              'reference_version': 'unknown',
              'rhythm_device': rhythmDevice,
              'lead_device': leadDevice,
              'rhythm_region': {
                'start_seconds': rhythmStart,
                'duration_seconds': rhythmDuration
              },
              'lead_region': {
                'start_seconds': leadStart,
                'duration_seconds': leadDuration
              }
            }))
        .timeout(const Duration(seconds: 60));
    return AnalysisJob.fromJson(_handleResponse(response));
  }

  Future<Map<String, dynamic>> saveMk20NamePilot(
      Map<String, dynamic> report) async {
    final response = await http
        .post(Uri.parse('$_baseUrl/api/v1/mk20/name-pilots'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'report': report}))
        .timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> saveMk20Diagnostic(
      Map<String, dynamic> report) async {
    final response = await http
        .post(Uri.parse('$_baseUrl/api/v1/mk20/diagnostics'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'report': report}))
        .timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> toneStates(String pairId) =>
      _get('/api/v1/presets/$pairId/tone-states');
  Future<Map<String, dynamic>> analyzeToneStates(String pairId, String version,
      {bool refresh = false, String? artist, String? songTitle}) async {
    final response = await http
        .post(Uri.parse('$_baseUrl/api/v1/presets/$pairId/tone-states/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'version': version,
              'refresh_research': refresh,
              'artist': artist,
              'song_title': songTitle
            }))
        .timeout(const Duration(seconds: 240));
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> generateToneState(String pairId, String stateId,
      String role, String device, String character, String? researchId,
      {String? researchRevision}) async {
    final response = await http
        .post(
            Uri.parse(
                '$_baseUrl/api/v1/presets/$pairId/tone-states/$stateId/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'role': role,
              'device': device,
              'character': character,
              'research_id': researchId,
              'research_revision': researchRevision
            }))
        .timeout(const Duration(seconds: 120));
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = utf8.decode(response.bodyBytes);
      return json.decode(body) as Map<String, dynamic>;
    }
    final body = utf8.decode(response.bodyBytes);
    String message = 'Erro ${response.statusCode}';
    String? code;
    String? recordingId;
    try {
      final decoded = json.decode(body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (decoded['recording_saved'] == true) {
        recordingId = decoded['recording_id'] as String?;
      }
      if (detail is Map) {
        message = detail['message']?.toString() ?? message;
        code = detail['code']?.toString();
      } else {
        message = detail?.toString() ?? message;
      }
    } catch (_) {}
    throw ApiException(message,
        statusCode: response.statusCode,
        errorCode: code,
        recordingId: recordingId);
  }

  Future<Map<String, dynamic>> checkHealth() async {
    return _get('/api/v1/health');
  }

  Future<Map<String, dynamic>> listDevices() async {
    return _get('/api/v1/devices');
  }

  Future<AnalysisJob> submitAnalysis({
    required File audioFile,
    required String rhythmDevice,
    required String leadDevice,
    String? artist,
    String? songTitle,
    String? originalFileName,
    String sourceKind = 'mix',
    double excerptStart = 0,
    double? excerptDuration,
    double? leadStart,
    double? leadDuration,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/analyze');
    final request = http.MultipartRequest('POST', uri);

    request.fields['rhythm_device'] = rhythmDevice;
    request.fields['lead_device'] = leadDevice;
    request.fields['source_kind'] = sourceKind;
    request.fields['engine_mode'] = 'guitar_v2';
    request.fields['analyze_states'] = 'true';
    request.fields['reference_version'] = 'unknown';
    if (leadStart != null && leadDuration != null) {
      request.fields['lead_start'] = leadStart.toString();
      request.fields['lead_duration'] = leadDuration.toString();
    }
    request.fields['excerpt_start'] = excerptStart.toString();
    if (excerptDuration != null) {
      request.fields['excerpt_duration'] = excerptDuration.toString();
    }
    if (artist != null && artist.isNotEmpty) request.fields['artist'] = artist;
    if (songTitle != null && songTitle.isNotEmpty) {
      request.fields['song_title'] = songTitle;
    }

    final ext = audioFile.path.split('.').last.toLowerCase();
    final mime = _mimeForExt(ext);
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      audioFile.path,
      filename: originalFileName,
      contentType: MediaType.parse(mime),
    ));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final body = _handleResponse(response);
    return AnalysisJob.fromJson(body);
  }

  Future<AnalysisJob> getJobStatus(String jobId) async {
    final body = await _get('/api/v1/jobs/$jobId');
    return AnalysisJob.fromJson(body);
  }

  Future<PresetPair> getPresets(String pairId) async {
    final body = await _get('/api/v1/presets/$pairId');
    return PresetPair.fromJson(body);
  }

  Future<String> exportGuide(String pairId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/presets/$pairId/export/guide');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    }
    throw ApiException('Falha ao exportar guia',
        statusCode: response.statusCode);
  }

  Future<Map<String, dynamic>> exportJson(String pairId) async {
    return _get('/api/v1/presets/$pairId/export/json');
  }

  Future<void> syncPedalReference(
      PresetPair pair, String role, PedalReference reference) async {
    if (!['rhythm', 'lead'].contains(role)) {
      throw ArgumentError('Função inválida');
    }
    final preset = role == 'rhythm' ? pair.rhythm : pair.lead;
    final response = await http
        .put(
            Uri.parse(
                '$_baseUrl/api/v1/presets/${Uri.encodeComponent(pair.id)}/pedal-reference/$role'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reference': reference.toJson(),
              'generated_preset': preset.toJson()
            }))
        .timeout(const Duration(seconds: 10));
    _handleResponse(response);
  }

  Future<int> syncSavedPedalReferences(Iterable<PresetPair> pairs) async {
    final repository = PedalReferenceRepository();
    var failures = 0;
    for (final pair in pairs) {
      for (final role in ['rhythm', 'lead']) {
        try {
          final reference = await repository.load(pair.id, role);
          if (reference != null) {
            await syncPedalReference(pair, role, reference);
          }
        } catch (_) {
          failures++;
        } // Referência local mantida para nova tentativa.
      }
    }
    return failures;
  }

  Future<Map<String, dynamic>> compareTone(
      {required File recording,
      required PresetData preset,
      required String pairId,
      required String inputKind,
      File? reference,
      double referenceStart = 0,
      String referenceKind = 'mix'}) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$_baseUrl/api/v1/compare-tone'));
    request.fields.addAll({
      'pair_id': pairId,
      'preset_json': jsonEncode(preset.toJson()),
      'input_kind': inputKind,
      'reference_start': referenceStart.toString(),
      'reference_kind': referenceKind
    });
    request.files
        .add(await http.MultipartFile.fromPath('file', recording.path));
    if (reference != null) {
      request.files.add(
          await http.MultipartFile.fromPath('reference_file', reference.path));
    }
    final response = await http.Response.fromStream(await request.send())
        .timeout(const Duration(seconds: 120));
    return _handleResponse(response);
  }

  String _mimeForExt(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
      case 'm4':
        return 'audio/m4a';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'audio/mpeg';
    }
  }
}
