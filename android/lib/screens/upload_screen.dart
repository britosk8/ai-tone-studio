import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class UploadScreen extends StatefulWidget {
  final String? initialArtist, initialSongTitle;
  final String initialRhythmDevice, initialLeadDevice;
  const UploadScreen(
      {super.key,
      this.initialArtist,
      this.initialSongTitle,
      this.initialRhythmDevice = "MK20",
      this.initialLeadDevice = "MK300"});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedFile;
  String _fileName = '';
  String _rhythmDevice = 'MK20';
  String _leadDevice = 'MK300';
  final _artistController = TextEditingController();
  final _songController = TextEditingController();
  bool _uploading = false;
  String _autoTitle = "";
  String _sourceKind = 'mix';
  bool _useExcerpt = false;
  bool _differentLead = false;
  final _leadStart = TextEditingController(text: '0');
  final _leadDuration = TextEditingController(text: '20');
  final _excerptStart = TextEditingController(text: '0');
  final _excerptDuration = TextEditingController(text: '20');
  String? _error;

  @override
  void initState() {
    super.initState();
    _artistController.text = widget.initialArtist ?? "";
    _songController.text = widget.initialSongTitle ?? "";
    _rhythmDevice = widget.initialRhythmDevice;
    _leadDevice = widget.initialLeadDevice;
  }

  @override
  void dispose() {
    _artistController.dispose();
    _songController.dispose();
    _leadStart.dispose();
    _leadDuration.dispose();
    _excerptStart.dispose();
    _excerptDuration.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // O seletor do Android concede acesso ao arquivo escolhido.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'm4a', 'm4', 'mp4'],
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final size = await file.length();
      if (size > 50 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error = 'Arquivo muito grande. Limite: 50 MB');
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        final name = result.files.single.name;
        final dot = name.lastIndexOf(".");
        final title = dot > 0 ? name.substring(0, dot) : name;
        if (_songController.text.trim().isEmpty ||
            _songController.text == _autoTitle) {
          _songController.text = title;
        }
        _autoTitle = title;
        _selectedFile = file;
        _fileName = result.files.single.name;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedFile == null) {
      setState(() => _error = 'Selecione um arquivo de áudio primeiro');
      return;
    }

    final start = double.tryParse(_excerptStart.text.replaceAll(',', '.'));
    final duration =
        double.tryParse(_excerptDuration.text.replaceAll(',', '.'));
    if (_useExcerpt &&
        (start == null ||
            !start.isFinite ||
            start < 0 ||
            start > 7200 ||
            duration == null ||
            !duration.isFinite ||
            duration < 3 ||
            duration > 120)) {
      setState(() => _error =
          'Informe início entre 0 e 7200 s e duração entre 3 e 120 s.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });

    final leadStart = double.tryParse(_leadStart.text.replaceAll(',', '.'));
    final leadDuration =
        double.tryParse(_leadDuration.text.replaceAll(',', '.'));
    if (_differentLead &&
        (leadStart == null ||
            !leadStart.isFinite ||
            leadStart < 0 ||
            leadStart > 7200 ||
            leadDuration == null ||
            !leadDuration.isFinite ||
            leadDuration < 3 ||
            leadDuration > 120)) {
      setState(() => _error =
          'Informe um trecho solo válido: início 0–7200 s e duração 3–120 s.');
      return;
    }
    try {
      final api = context.read<ApiService>();
      final job = await api.submitAnalysis(
        audioFile: _selectedFile!,
        rhythmDevice: _rhythmDevice,
        leadDevice: _leadDevice,
        artist: _artistController.text,
        songTitle: _songController.text,
        originalFileName: _fileName,
        sourceKind: _sourceKind,
        excerptStart: _useExcerpt ? start! : 0,
        excerptDuration: _useExcerpt ? duration : null,
        leadStart: _differentLead ? leadStart : null,
        leadDuration: _differentLead ? leadDuration : null,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/analysis',
            arguments: {'job_id': job.jobId});
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Erro de conexão: verifique o backend em Ajustes';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar Música')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('Arquivo de Áudio'),
            const SizedBox(height: 12),
            _FileSelector(
              fileName: _fileName,
              onTap: _pickFile,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      const TextStyle(color: AppTheme.errorRed, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            const _SectionHeader('Referência do timbre'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _sourceKind,
              decoration: const InputDecoration(labelText: 'Conteúdo do áudio'),
              items: const [
                DropdownMenuItem(
                    value: 'mix',
                    child: Text('Música com outros instrumentos')),
                DropdownMenuItem(
                    value: 'isolated',
                    child: Text('Somente guitarra, já isolada')),
              ],
              onChanged:
                  _uploading ? null : (v) => setState(() => _sourceKind = v!),
            ),
            const SizedBox(height: 8),
            const Text(
                'A música será separada por IA no backend antes de analisar a guitarra. Prefira trechos de 20 segundos: em CPU a separação pode levar minutos. Base e solo simultâneos podem permanecer juntos.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Selecionar trecho da base'),
              subtitle: const Text(
                  'Sem seleção, analisa a música completa. O solo pode usar outro trecho abaixo.'),
              value: _useExcerpt,
              onChanged:
                  _uploading ? null : (v) => setState(() => _useExcerpt = v),
            ),
            if (_useExcerpt) ...[
              TextField(
                  controller: _excerptStart,
                  enabled: !_uploading,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Início do trecho (segundos)')),
              TextField(
                  controller: _excerptDuration,
                  enabled: !_uploading,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Duração do trecho (3–120 segundos)')),
            ],
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usar outro trecho para o solo'),
              value: _differentLead,
              onChanged:
                  _uploading ? null : (v) => setState(() => _differentLead = v),
            ),
            if (_differentLead) ...[
              TextField(
                  controller: _leadStart,
                  enabled: !_uploading,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Início do solo (segundos)')),
              TextField(
                  controller: _leadDuration,
                  enabled: !_uploading,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Duração do solo (3–120 segundos)')),
            ],
            const SizedBox(height: 24),
            const _SectionHeader('Informações (opcional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'Artista',
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _songController,
              decoration: const InputDecoration(
                labelText: 'Música',
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader('Dispositivos'),
            const SizedBox(height: 12),
            _DeviceSelector(
              label: 'Guitarra base (ritmo)',
              selected: _rhythmDevice,
              options: const ['MK20', 'MK300'],
              onChanged: (v) => setState(() => _rhythmDevice = v!),
            ),
            const SizedBox(height: 12),
            _DeviceSelector(
              label: 'Guitarra solo (lead)',
              selected: _leadDevice,
              options: const ['MK300', 'MK20'],
              onChanged: (v) => setState(() => _leadDevice = v!),
            ),
            const SizedBox(height: 8),
            const _TransferNote(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _submit,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send),
                label: Text(_uploading ? 'Enviando...' : 'Analisar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.primaryGreen,
              fontWeight: FontWeight.bold,
            ));
  }
}

class _FileSelector extends StatelessWidget {
  final String fileName;
  final VoidCallback onTap;

  const _FileSelector({required this.fileName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                fileName.isEmpty ? AppTheme.bgElevated : AppTheme.primaryGreen,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              fileName.isEmpty ? Icons.upload_file : Icons.audio_file,
              size: 48,
              color: fileName.isEmpty
                  ? AppTheme.textSecondary
                  : AppTheme.primaryGreen,
            ),
            const SizedBox(height: 12),
            Text(
              fileName.isEmpty
                  ? 'Toque para selecionar MP3, WAV, FLAC, M4A ou MP4'
                  : fileName,
              style: TextStyle(
                color: fileName.isEmpty
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
                fontWeight:
                    fileName.isEmpty ? FontWeight.normal : FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (fileName.isEmpty) ...[
              const SizedBox(height: 4),
              const Text('Máximo 50 MB',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceSelector extends StatelessWidget {
  final String label;
  final String selected;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _DeviceSelector({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.textSecondary))),
        DropdownButton<String>(
          value: selected,
          dropdownColor: AppTheme.bgCard,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TransferNote extends StatelessWidget {
  const _TransferNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warnYellow.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warnYellow.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.warnYellow),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'MK300: envio USB/OTG e BLE em validação física, com backup e confirmação. '
              'MK20: utilize o guia manual enquanto o perfil de comunicação é verificado.',
              style: TextStyle(fontSize: 12, color: AppTheme.warnYellow),
            ),
          ),
        ],
      ),
    );
  }
}
