import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/api_service.dart';
import '../services/preset_store.dart';
import '../services/tone_recording.dart';
import 'tone_result_screen.dart';

class ToneComparisonScreen extends StatefulWidget {
  final String pairId;
  final String initialRole;
  const ToneComparisonScreen(
      {super.key, required this.pairId, this.initialRole = 'lead'});
  @override
  State<ToneComparisonScreen> createState() => _ToneComparisonScreenState();
}

class _ToneComparisonScreenState extends State<ToneComparisonScreen>
    with WidgetsBindingObserver {
  final _recorder = ToneRecording();
  final _referenceStart = TextEditingController(text: '0');
  Timer? _timer;
  PresetPair? _pair;
  String _role = 'lead',
      _inputKind = 'usb',
      _captureKind = 'usb',
      _referenceKind = 'mix',
      _status = 'Conecte a saída USB processada da pedaleira.';
  List<Map<String, dynamic>> _inputs = [];
  int? _inputId;
  int _seconds = 10, _elapsed = 0;
  bool _busy = false,
      _recording = false,
      _polling = false,
      _ownedRecording = false;
  File? _capture, _reference;
  Map<String, dynamic>? _report, _savedReference;
  double _peakDbfs = -120, _clippedFraction = 0;
  bool get _v2Reference =>
      _preset?.generationMetadata['generator'] == 'guitar-v2-heuristic';
  PresetData? get _preset => _role == 'lead' ? _pair?.lead : _pair?.rhythm;
  @override
  void initState() {
    super.initState();
    _role = widget.initialRole == 'rhythm' ? 'rhythm' : 'lead';
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final store = context.read<PresetStore>();
      await store.load();
      if (!mounted) return;
      final pair = store.pairs.where((p) => p.id == widget.pairId).firstOrNull;
      if (pair == null) throw StateError('Preset não está na biblioteca.');
      setState(() => _pair = pair);
      await _refreshInputs();
      await _loadReference();
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro: $e');
    }
  }

  Future<void> _loadReference() async {
    final role = _role;
    try {
      final info =
          await context.read<ApiService>().referenceInfo(widget.pairId, role);
      if (mounted && _role == role) setState(() => _savedReference = info);
    } catch (_) {
      if (mounted && _role == role) setState(() => _savedReference = null);
    }
  }

  Future<void> _selectRegion() async {
    final saved = _savedReference;
    if (saved == null) return;
    final selected = await showDialog<Map<String, double>>(
        context: context,
        builder: (context) => _SavedRegionDialog(
            role: _role,
            start: '${saved['start_seconds']}',
            duration:
                '${saved['needs_region'] == true ? 20 : saved['duration_seconds']}'));
    if (selected == null || !mounted) return;
    final begin = selected['start']!, seconds = selected['duration']!;
    await _run(() async {
      final info = await context
          .read<ApiService>()
          .setReferenceRegion(widget.pairId, _role, begin, seconds);
      if (mounted) {
        setState(() {
          _savedReference = info;
          _reference = null;
          _report = null;
          _status = 'Trecho salvo. Toque a mesma passagem da referência.';
        });
      }
    });
  }

  Future<void> _refreshInputs() async {
    try {
      final inputs = await _recorder.inputs();
      if (!mounted) return;
      setState(() {
        _inputs = inputs;
        final choices = inputs.where((i) => i['kind'] == _inputKind);
        _inputId =
            choices.isEmpty ? null : (choices.first['id'] as num).toInt();
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro ao buscar entradas: $e');
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Erro: $e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeOwnedCapture(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } on FileSystemException {
      /* O gravador nativo pode já ter removido o arquivo. */
    }
  }

  Future<void> _clearCapture() async {
    if (_ownedRecording) await _removeOwnedCapture(_capture);
    _capture = null;
    _ownedRecording = false;
    _report = null;
  }

  Future<void> _start() => _run(() async {
        if (_inputId == null) {
          throw StateError(
              'Nenhuma entrada $_inputKind encontrada. Conecte o USB/OTG e atualize a lista.');
        }
        await _clearCapture();
        final info = await _recorder.start(_inputKind, _inputId!, _seconds);
        if (!mounted) {
          await _recorder.cancel();
          return;
        }
        setState(() {
          _recording = true;
          _captureKind = _inputKind;
          _elapsed = 0;
          _status =
              'Gravando pela entrada ${info['input']}. Toque o mesmo trecho da referência.';
        });
        _timer =
            Timer.periodic(const Duration(milliseconds: 250), (_) => _poll());
      });
  Future<void> _poll() async {
    if (_polling || !_recording || _busy) return;
    _polling = true;
    try {
      final status = await _recorder.status();
      if (!mounted) return;
      setState(() {
        _elapsed = status['elapsed_ms'] is num
            ? (status['elapsed_ms'] as num).toInt() ~/ 1000
            : _elapsed;
        _peakDbfs = (status['peak_dbfs'] as num?)?.toDouble() ?? -120;
        _clippedFraction =
            (status['clipped_fraction'] as num?)?.toDouble() ?? 0;
      });
      if (status['finished'] == true) {
        await _stop();
      }
    } catch (e) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _status = 'Erro na gravação: $e';
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _stop() => _run(() async {
        _timer?.cancel();
        try {
          final path = await _recorder.stop();
          if (!mounted) {
            final file = File(path);
            if (await file.exists()) await file.delete();
            return;
          }
          setState(() {
            _capture = File(path);
            _ownedRecording = true;
            _recording = false;
            _status = 'Gravação concluída. Compare com a referência.';
          });
        } catch (_) {
          if (mounted) setState(() => _recording = false);
          rethrow;
        }
      });
  Future<File?> _chooseAudio() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'flac', 'm4a', 'ogg', 'mp4', 'm4'],
        allowMultiple: false);
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> _importCapture() => _run(() async {
        final selected = await _chooseAudio();
        if (selected == null) return;
        await _clearCapture();
        if (mounted) {
          setState(() {
            _capture = selected;
            _captureKind = 'file';
            _status = 'Gravação importada (3–30 segundos).';
          });
        }
      });
  Future<void> _chooseReference() => _run(() async {
        final selected = await _chooseAudio();
        if (mounted && selected != null) {
          setState(() {
            _reference = selected;
            _report = null;
          });
        }
      });
  Future<void> _compare() => _run(() async {
        if (_capture == null || _preset == null) {
          throw StateError('Grave ou importe sua guitarra primeiro.');
        }
        final start =
            double.tryParse(_referenceStart.text.replaceAll(',', '.'));
        if (start == null || !start.isFinite || start < 0) {
          throw ArgumentError('Informe o início do trecho em segundos.');
        }
        if (_v2Reference && _savedReference?['needs_region'] == true) {
          throw StateError(
              'Salve o trecho de base ou solo da guitarra já separada antes de comparar.');
        }
        final snapshot = _preset!;
        setState(() =>
            _status = 'Medindo sua gravação e comparando com a referência...');
        Map<String, dynamic> result;
        try {
          result = await context.read<ApiService>().compareTone(
              recording: _capture!,
              preset: snapshot,
              pairId: widget.pairId,
              inputKind: _captureKind,
              reference: _reference,
              referenceStart: start,
              referenceKind: _referenceKind);
        } on ApiException catch (error) {
          if (error.errorCode != 'reference_required' &&
              !(error.statusCode == 404 &&
                  error.message.contains('Preset não encontrado'))) {
            rethrow;
          }
          if (!mounted) return;
          setState(() {
            _status = error.recordingId != null
                ? 'Sua gravação já está salva no backend. Selecione a música original para concluir a comparação.'
                : 'Selecione o áudio original da música. O preset está no celular, mas o backend não tem seu perfil de áudio.';
            _report = null;
          });
          if (!_v2Reference && _savedReference == null) {
            // Compatibilidade: análises antigas podem ainda não ter o original salvo.
            final selected = await _chooseAudio();
            if (mounted && selected != null) {
              setState(() {
                _reference = selected;
                _status =
                    'Áudio original selecionado. Confira o início do trecho e analise novamente.';
              });
            }
            return;
          }
          await _loadReference();
          if (mounted) {
            setState(() => _status =
                'A referência salva não está disponível. Confira o trecho desta parte no backend; sua gravação foi preservada.');
          }
          return;
        }
        if (mounted) {
          setState(() {
            _report = result;
            _status =
                'Comparação concluída. Revise as sugestões antes de salvar.';
          });
          // Libera a tela de captura antes de aguardar a revisão em outra rota.
          setState(() => _busy = false);
          await _openResult(snapshot, result);
        }
      });
  Future<void> _openResult(
      PresetData preset, Map<String, dynamic> report) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ToneResultScreen(
                pairId: widget.pairId,
                role: _role,
                preset: preset,
                report: report)));
    if (!mounted) return;
    final pair = context
        .read<PresetStore>()
        .pairs
        .where((p) => p.id == widget.pairId)
        .firstOrNull;
    setState(() {
      _pair = pair;
      _report = null;
      _status = report['quality'] == 'clipped'
          ? 'Reduza o nível da entrada e grave novamente antes de comparar.'
          : 'Resultado revisado. Grave novamente para avaliar o preset aplicado no pedal.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_recording && state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _recorder.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _status = 'Gravação cancelada ao sair do aplicativo.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _recorder.cancel().catchError((_) {});
    if (_ownedRecording) _removeOwnedCapture(_capture);
    _referenceStart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs.where((i) => i['kind'] == _inputKind).toList();
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Comparar meu timbre')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            if (_pair != null) ...[
              Text(
                  _preset!.songTitle.isNotEmpty
                      ? _preset!.songTitle
                      : _preset!.name,
                  style: Theme.of(context).textTheme.titleLarge),
              DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(
                      labelText: 'Preset que você está tocando'),
                  items: [
                    DropdownMenuItem(
                        value: 'rhythm',
                        child: Text('Base — ${_pair!.rhythm.device}')),
                    DropdownMenuItem(
                        value: 'lead',
                        child: Text('Solo — ${_pair!.lead.device}'))
                  ],
                  onChanged: _busy || _recording
                      ? null
                      : (v) => _run(() async {
                            await _clearCapture();
                            if (!mounted) return;
                            setState(() {
                              _role = v!;
                              _savedReference = null;
                              _reference = null;
                              _status =
                                  'Grave novamente com o preset selecionado.';
                            });
                            await _loadReference();
                          })),
              const SizedBox(height: 12),
              const Text(
                  'Toque 3–30 segundos da mesma passagem da referência. Grave somente sua guitarra, sem a música de fundo. Confira que a USB envia o som processado pelo preset, não o sinal DI seco.'),
              DropdownButtonFormField<String>(
                  value: _inputKind,
                  decoration:
                      const InputDecoration(labelText: 'Entrada para gravar'),
                  items: const [
                    DropdownMenuItem(
                        value: 'usb', child: Text('USB/OTG da pedaleira')),
                    DropdownMenuItem(
                        value: 'microphone',
                        child: Text('Microfone do celular'))
                  ],
                  onChanged: _busy || _recording
                      ? null
                      : (v) async {
                          setState(() => _inputKind = v!);
                          await _refreshInputs();
                        }),
              TextButton(
                  onPressed: _busy || _recording ? null : _refreshInputs,
                  child: const Text('Atualizar entradas de áudio')),
              if (inputs.isNotEmpty)
                DropdownButtonFormField<int>(
                    key: ValueKey('$_inputKind:$_inputId'),
                    value: _inputId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Dispositivo de áudio'),
                    items: inputs
                        .map((i) => DropdownMenuItem(
                            value: (i['id'] as num).toInt(),
                            child: Text(i['name'] as String,
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _busy || _recording
                        ? null
                        : (id) => setState(() => _inputId = id)),
              if (_inputId == null)
                const Text(
                    'Entrada não encontrada. Conecte USB/OTG e atualize; ou importe uma gravação abaixo.'),
              DropdownButtonFormField<int>(
                  value: _seconds,
                  decoration: const InputDecoration(labelText: 'Duração'),
                  items: [5, 10, 20, 30]
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text('$s segundos')))
                      .toList(),
                  onChanged: _busy || _recording
                      ? null
                      : (v) => setState(() => _seconds = v!)),
              FilledButton(
                  onPressed: _busy
                      ? null
                      : _recording
                          ? _stop
                          : _inputId == null
                              ? null
                              : _start,
                  child: Text(_recording
                      ? 'Parar gravação ($_elapsed s)'
                      : 'Gravar minha guitarra')),
              if (_recording || _ownedRecording) ...[
                Text('Pico de entrada: ${_peakDbfs.toStringAsFixed(1)} dBFS'),
                LinearProgressIndicator(
                    value: ((_peakDbfs + 60) / 60).clamp(0, 1),
                    color:
                        _clippedFraction >= .005 ? Colors.red : Colors.green),
                if (_clippedFraction >= .005)
                  const Text(
                      'Saturação detectada na entrada. Pare, reduza o volume pelo app e grave novamente.',
                      style: TextStyle(color: Colors.red)),
              ],
              TextButton(
                  onPressed: _busy || _recording ? null : _importCapture,
                  child: const Text('Importar gravação de guitarra')),
              const Divider(),
              const Text('Referência da guitarra',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_savedReference != null) ...[
                Text(
                    '${_role == 'lead' ? 'Solo' : 'Base'} — ${_savedReference!['title']}'),
                Text(
                    'Trecho: ${_savedReference!['start_seconds']} s — duração ${_savedReference!['duration_seconds']} s'),
                Text(_savedReference!['needs_region'] == true
                    ? 'Esta referência ainda contém a música inteira. Salve uma vez o trecho desta parte na guitarra já separada.'
                    : 'Guitarra já separada e salva no backend. Sua gravação será comparada com este trecho, sem selecionar arquivo novamente.'),
                OutlinedButton(
                    onPressed: _busy || _recording ? null : _selectRegion,
                    child: const Text('Ajustar trecho da guitarra salva')),
              ] else ...[
                Text(_v2Reference
                    ? 'Buscando a guitarra separada salva no backend...'
                    : 'Use a referência salva ou selecione um original apenas para análises antigas.'),
              ],
              if (!_v2Reference)
                OutlinedButton(
                    onPressed: _busy || _recording ? null : _chooseReference,
                    child: const Text(
                        'Selecionar outra referência (análises antigas)')),
              if (_reference != null) ...[
                Text(_reference!.path.split('/').last),
                TextField(
                    controller: _referenceStart,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: !_busy && !_recording,
                    decoration: const InputDecoration(
                        labelText: 'Início do trecho original (segundos)'),
                    onChanged: (_) => setState(() => _report = null)),
                DropdownButtonFormField<String>(
                    value: _referenceKind,
                    items: const [
                      DropdownMenuItem(
                          value: 'mix', child: Text('Música mixada')),
                      DropdownMenuItem(
                          value: 'isolated', child: Text('Guitarra isolada'))
                    ],
                    onChanged: _busy || _recording
                        ? null
                        : (v) => setState(() {
                              _referenceKind = v!;
                              _report = null;
                            })),
              ],
              FilledButton(
                  onPressed:
                      _busy || _recording || _capture == null ? null : _compare,
                  child: const Text('Analisar e sugerir ajustes')),
              if (_busy) const LinearProgressIndicator(),
              SelectableText(_status),
              if (_report != null)
                OutlinedButton(
                    onPressed:
                        _busy ? null : () => _openResult(_preset!, _report!),
                    child: const Text('Abrir resultado e ajustes')),
            ] else
              Text(_status),
          ]),
        ));
  }
}

class _SavedRegionDialog extends StatefulWidget {
  final String role, start, duration;
  const _SavedRegionDialog(
      {required this.role, required this.start, required this.duration});
  @override
  State<_SavedRegionDialog> createState() => _SavedRegionDialogState();
}

class _SavedRegionDialogState extends State<_SavedRegionDialog> {
  late final _start = TextEditingController(text: widget.start);
  late final _duration = TextEditingController(text: widget.duration);
  String? _error;
  @override
  void dispose() {
    _start.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.role == 'lead'
              ? 'Trecho da guitarra solo'
              : 'Trecho da guitarra base'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'A guitarra já está separada. Este trecho ficará salvo para esta parte nas próximas comparações.'),
            TextField(
                controller: _start,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Início na música (segundos)')),
            TextField(
                controller: _duration,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Duração (3–120 segundos)')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  final start =
                          double.tryParse(_start.text.replaceAll(',', '.')),
                      duration =
                          double.tryParse(_duration.text.replaceAll(',', '.'));
                  if (start == null ||
                      duration == null ||
                      !start.isFinite ||
                      !duration.isFinite ||
                      start < 0 ||
                      duration < 3 ||
                      duration > 120) {
                    setState(() => _error =
                        'Informe um início válido e duração entre 3 e 120 s.');
                    return;
                  }
                  Navigator.pop(
                      context, {'start': start, 'duration': duration});
                },
                child: const Text('Salvar trecho'))
          ]);
}
