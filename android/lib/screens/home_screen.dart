import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/preset_import.dart';
import 'package:provider/provider.dart';
import '../services/preset_store.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../models/preset_pair.dart';
import '../widgets/delete_preset_pair.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _backendOk = false;
  bool _checking = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    context.read<PresetStore>().load();
  }

  Future<void> _checkBackend() async {
    try {
      await context.read<ApiService>().checkHealth();
      if (mounted) {
        setState(() {
          _backendOk = true;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _backendOk = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _importPresets() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final selected = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (selected == null) return;
      final path = selected.files.single.path;
      if (path == null) {
        throw const FormatException('Não foi possível acessar o arquivo.');
      }
      final file = File(path);
      if (await file.length() > PresetImport.maxBytes) {
        throw const FormatException('JSON acima do limite de 1 MB.');
      }
      final pair = await PresetImport.decode(await file.readAsString());
      if (!mounted) return;
      final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Importar presets MK300?'),
                  content: Text(
                      'Base: ${pair.rhythm.name}\nSolo: ${pair.lead.name}\n\nSerá criada uma nova análise na biblioteca, preservando as anteriores. Importar não envia nada ao pedal. Os presets precisam de avaliação no seu equipamento.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Importar como nova análise'))
                  ]));
      if (accepted != true || !mounted) return;
      await context.read<PresetStore>().save(pair);
      if (!mounted) return;
      await Navigator.pushNamed(context, '/presets',
          arguments: {'pair_id': pair.id});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PresetStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tone Studio'),
        actions: [
          IconButton(
              tooltip: 'Piloto Infest — MK300',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.pushNamed(context, '/mk300-pilot')),
          IconButton(
              tooltip: 'Importar presets MK300 (JSON)',
              icon: const Icon(Icons.file_open_outlined),
              onPressed: _importing ? null : _importPresets),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings')
                .then((_) => _checkBackend()),
          ),
        ],
      ),
      body: Column(
        children: [
          _BackendStatusBar(checking: _checking, ok: _backendOk),
          Expanded(
            child: store.pairs.isEmpty
                ? _EmptyState(backendOk: _backendOk, onAnalyze: _openUpload)
                : _PairList(pairs: store.pairs, onAnalyze: _openUpload),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _backendOk ? _openUpload : null,
        backgroundColor: _backendOk ? AppTheme.primaryGreen : Colors.grey,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.music_note),
        label: const Text('Analisar música'),
      ),
    );
  }

  void _openUpload() => Navigator.pushNamed(context, '/upload');
}

class _BackendStatusBar extends StatelessWidget {
  final bool checking;
  final bool ok;

  const _BackendStatusBar({required this.checking, required this.ok});

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return Container(
        color: AppTheme.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(children: [
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Verificando backend...',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ]),
      );
    }

    final color = ok ? AppTheme.primaryGreen : AppTheme.errorRed;
    final label = ok
        ? 'Backend conectado'
        : 'Backend indisponível — configure em Ajustes';

    return Container(
      color: color.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(ok ? Icons.circle : Icons.warning_amber_rounded,
            size: 10, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool backendOk;
  final VoidCallback onAnalyze;

  const _EmptyState({required this.backendOk, required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq,
                size: 80, color: AppTheme.textSecondary),
            const SizedBox(height: 24),
            Text('Nenhum preset gerado ainda',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Importe um MP3, WAV ou FLAC e gere presets automáticos para MK20 (base) e MK300 (solo).',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (backendOk)
              ElevatedButton.icon(
                onPressed: onAnalyze,
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar música'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PairList extends StatelessWidget {
  final List<PresetPair> pairs;
  final VoidCallback onAnalyze;

  const _PairList({required this.pairs, required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: pairs.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (ctx, i) {
        final pair = pairs[i];
        final title = pair.rhythm.artist.isNotEmpty
            ? '${pair.rhythm.artist} — ${pair.rhythm.songTitle}'
            : pair.rhythm.songTitle.isNotEmpty
                ? pair.rhythm.songTitle
                : pair.id.substring(0, pair.id.length < 8 ? pair.id.length : 8);

        return Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.queue_music,
                color: AppTheme.primaryGreen, size: 32),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Base: ${pair.rhythm.device} · Solo: ${pair.lead.device}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                Text(
                    'Timbre: ${pair.analysis.gainCharacter.replaceAll('_', ' ')}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Ações dos presets',
              onSelected: (action) async {
                if (action == 'delete') {
                  await deletePresetPair(ctx, pair);
                } else {
                  if (ctx.mounted) {
                    Navigator.pushNamed(
                        ctx, action == 'send' ? '/transfer' : '/presets',
                        arguments: {'pair_id': pair.id});
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Abrir presets')),
                PopupMenuItem(
                    value: 'send', child: Text('Escolher preset e enviar')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Excluir análise (base e solo)')),
              ],
            ),
            onTap: () => Navigator.pushNamed(ctx, '/presets',
                arguments: {'pair_id': pair.id}),
          ),
        );
      },
    );
  }
}
