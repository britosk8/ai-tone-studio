import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/preset_store.dart';
import '../models/preset_pair.dart';
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/spectral_chart.dart';
import '../widgets/delete_preset_pair.dart';

class PresetListScreen extends StatefulWidget {
  final String pairId;
  const PresetListScreen({super.key, required this.pairId});

  @override
  State<PresetListScreen> createState() => _PresetListScreenState();
}

class _PresetListScreenState extends State<PresetListScreen> {
  PresetPair? _pair;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPair();
  }

  Future<void> _loadPair() async {
    // Tenta primeiro no store local
    final store = context.read<PresetStore>();
    await store.load();
    if (!mounted) return;
    final local = store.pairs.where((p) => p.id == widget.pairId).firstOrNull;
    if (local != null) {
      setState(() {
        _pair = local;
        _loading = false;
      });
      return;
    }
    // Busca do backend
    try {
      final pair = await context.read<ApiService>().getPresets(widget.pairId);
      await store.save(pair);
      if (mounted) {
        setState(() {
          _pair = pair;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _editPreset(PresetData preset) async {
    final edited = await Navigator.pushNamed(context, '/editor',
        arguments: {'preset': preset, 'pair_id': _pair!.id});
    if (!mounted || edited is! PresetData) return;
    final updated = _pair!.withPreset(edited);
    try {
      await context.read<PresetStore>().save(updated);
      if (mounted) setState(() => _pair = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    }
  }

  Future<void> _chooseCandidate(PresetData current) async {
    try {
      final candidates = await context
          .read<ApiService>()
          .getToneCandidates(_pair!.id, current.role);
      if (!mounted) return;
      final chosen = await showDialog<PresetData>(
          context: context,
          builder: (context) => SimpleDialog(
                  title: const Text('Alternativas de amplificador'),
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Opções da mesma família do catálogo. A ordem não representa fidelidade sonora. Escolher atualiza este preset na biblioteca.')),
                    for (final candidate in candidates)
                      SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, candidate),
                          child: Text(candidate.effectChain
                              .where((b) => b.effectType == 'amp')
                              .map((b) => b.modelName)
                              .join(', '))),
                  ]));
      if (chosen == null || !mounted) return;
      final replacement = PresetData.fromJson({
        ...current.toJson(),
        'effect_chain': chosen.effectChain.map((e) => e.toJson()).toList(),
        'generation_metadata': chosen.generationMetadata,
        'preset_volume': chosen.presetVolume
      });
      final updated = _pair!.withPreset(replacement);
      await context.read<PresetStore>().save(updated);
      if (mounted) setState(() => _pair = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não foi possível carregar as alternativas: $e')));
      }
    }
  }

  Future<void> _exportStem(PresetData preset) async {
    try {
      final bytes = await context
          .read<ApiService>()
          .downloadGuitarStem(_pair!.id, preset.role);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/guitarra-${preset.role}.wav');
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)],
            text: 'Guitarra extraída por IA — ${preset.songTitle}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não foi possível exportar a guitarra: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _pair == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presets')),
        body: Center(child: Text(_error ?? 'Preset não encontrado')),
      );
    }

    final pair = _pair!;
    final title = pair.rhythm.artist.isNotEmpty
        ? '${pair.rhythm.artist} — ${pair.rhythm.songTitle}'
        : pair.rhythm.songTitle.isNotEmpty
            ? pair.rhythm.songTitle
            : pair.rhythm.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Excluir análise da biblioteca",
            onPressed: () async {
              final deleted = await deletePresetPair(context, pair);
              if (deleted && context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.send_outlined),
            tooltip: 'Transferir para hardware',
            onPressed: () async {
              await Navigator.pushNamed(context, '/transfer',
                  arguments: {'pair_id': pair.id});
              if (mounted) await _loadPair();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          _AnalysisSummaryCard(analysis: pair.analysis),
          _PresetCard(
            preset: pair.rhythm,
            deviceColor: AppTheme.accentBlue,
            roleLabel: 'GUITARRA BASE',
            pairId: pair.id,
            onEdit: () => _editPreset(pair.rhythm),
            onCandidates: () => _chooseCandidate(pair.rhythm),
            onExportStem: () => _exportStem(pair.rhythm),
          ),
          _PresetCard(
            preset: pair.lead,
            deviceColor: AppTheme.accentOrange,
            roleLabel: 'GUITARRA SOLO',
            pairId: pair.id,
            onEdit: () => _editPreset(pair.lead),
            onCandidates: () => _chooseCandidate(pair.lead),
            onExportStem: () => _exportStem(pair.lead),
          ),
          Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, "/compare",
                        arguments: {"pair_id": pair.id});
                    if (mounted) await _loadPair();
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text("Gravar e comparar meu timbre"))),
          _ExportCard(pair: pair),
          if (pair.rhythm.device == 'MK300' || pair.lead.device == 'MK300')
            Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(
                        context, '/pedal-reference',
                        arguments: {'pair_id': pair.id}),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Importar preset do pedal e comparar'))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  final AudioAnalysis analysis;
  const _AnalysisSummaryCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final gainLabels = {
      'clean': 'Limpo',
      'crunch': 'Crunch',
      'overdrive': 'Overdrive',
      'high_gain': 'High Gain',
      'lead': 'Lead',
      'unknown': 'Indefinido',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined,
                    color: AppTheme.primaryGreen, size: 20),
                const SizedBox(width: 8),
                Text('Análise de áudio',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                ConfidenceBadge(level: analysis.confidence),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _InfoChip(
                    'Timbre',
                    gainLabels[analysis.gainCharacter] ??
                        analysis.gainCharacter),
                const SizedBox(width: 8),
                _InfoChip('Distorção',
                    '${(analysis.distortionLevel * 100).round()}%'),
                if (analysis.estimatedBpm != null) ...[
                  const SizedBox(width: 8),
                  _InfoChip('BPM', analysis.estimatedBpm!.round().toString()),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (analysis.hasReverb)
                  const _InfoChip('Reverb', '✓', color: AppTheme.primaryGreen),
                if (analysis.hasDelay) ...[
                  const SizedBox(width: 8),
                  const _InfoChip('Delay', '✓', color: AppTheme.primaryGreen),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SpectralChart(spectral: analysis.spectral),
            if (analysis.possibleLayering)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                      'A referência pode conter guitarras sobrepostas ou efeitos estéreo. Use trechos distintos para base e solo.')),
            if (analysis.confidence == 'low' ||
                analysis.confidence == 'speculative') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warnYellow.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: AppTheme.warnYellow.withOpacity(0.3)),
                ),
                child: Text(
                  analysis.sourceSeparated
                      ? 'Guitarra extraída por IA. O preset é uma estimativa inicial: vazamentos e artefatos podem influenciar o resultado.'
                      : 'Preset estimado a partir do áudio. A confiança não representa fidelidade sonora ao original.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.warnYellow),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoChip(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$label: ',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ]),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final PresetData preset;
  final Color deviceColor;
  final String roleLabel;
  final String pairId;
  final VoidCallback onEdit;
  final VoidCallback onCandidates, onExportStem;

  const _PresetCard({
    required this.preset,
    required this.deviceColor,
    required this.roleLabel,
    required this.pairId,
    required this.onEdit,
    required this.onCandidates,
    required this.onExportStem,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: deviceColor.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(left: BorderSide(color: deviceColor, width: 4)),
            ),
            child: Row(
              children: [
                Icon(Icons.queue_music, color: deviceColor, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(roleLabel,
                        style: TextStyle(
                            color: deviceColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    Text(preset.device,
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(foregroundColor: deviceColor),
                ),
              ],
            ),
          ),
          if (preset.generationMetadata['generator'] ==
              'guitar-v2-heuristic') ...[
            TextButton.icon(
                onPressed: onCandidates,
                icon: const Icon(Icons.tune),
                label: const Text('Comparar alternativas de amplificador')),
            if (preset.generationMetadata['separation_cache_id'] != null)
              TextButton.icon(
                  onPressed: onExportStem,
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('Exportar guitarra separada')),
          ],
          ...preset.effectChain.where((b) => b.enabled).map(
                (block) => _EffectRow(block: block),
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _EffectRow extends StatelessWidget {
  final EffectBlock block;
  const _EffectRow({required this.block});

  static const _icons = {
    'noise_gate': Icons.noise_aware,
    'compressor': Icons.compress,
    'drive': Icons.flash_on,
    'amp': Icons.speaker,
    'cabinet': Icons.speaker_group,
    'modulation': Icons.waves,
    'delay': Icons.timer_outlined,
    'reverb': Icons.blur_on,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[block.effectType] ?? Icons.settings;
    final paramSummary = block.parameters.entries.take(3).map((e) {
      final v = e.value % 1 == 0
          ? e.value.toInt().toString()
          : e.value.toStringAsFixed(1);
      return '${e.key}: $v';
    }).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(block.modelName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (!block.enabled)
                  const Text('Desligado',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                if (paramSummary.isNotEmpty)
                  Text(paramSummary,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          ConfidenceBadge(
              level: block.generatedConfidence,
              rationale: block.generationRationale),
        ],
      ),
    );
  }
}

class _ExportCard extends StatefulWidget {
  final PresetPair pair;
  const _ExportCard({required this.pair});

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  bool _exporting = false;

  Future<void> _exportGuide() async {
    setState(() => _exporting = true);
    try {
      final guide = widget.pair.toReadableGuide();
      if (mounted) {
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _GuideScreen(guide: guide),
            ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/presets-${widget.pair.id}.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(widget.pair.exportJson()));
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Presets AI Tone Studio');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha ao exportar: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exportar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportGuide,
                    icon: _exporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Guia manual'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportJson,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('JSON'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideScreen extends StatelessWidget {
  final String guide;
  const _GuideScreen({required this.guide});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guia de Configuração'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              try {
                await Share.share(guide,
                    subject: 'Guia de configuração AI Tone Studio');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Falha ao compartilhar: $e')));
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          guide,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: AppTheme.textPrimary,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
