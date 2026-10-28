import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/preset_store.dart';

class ToneStatesPanel extends StatefulWidget {
  final String pairId, rhythmDevice, leadDevice;
  final String artist, songTitle;
  final Future<void> Function(String pairId, String role) onGenerated;
  const ToneStatesPanel(
      {super.key,
      required this.pairId,
      required this.rhythmDevice,
      required this.leadDevice,
      required this.onGenerated,
      this.artist = '',
      this.songTitle = ''});
  @override
  State<ToneStatesPanel> createState() => _ToneStatesPanelState();
}

class _ToneStatesPanelState extends State<ToneStatesPanel> {
  Map<String, dynamic>? _data;
  String _version = 'unknown';
  late final _artist = TextEditingController(text: widget.artist);
  late final _song = TextEditingController(text: widget.songTitle);
  @override
  void dispose() {
    _artist.dispose();
    _song.dispose();
    super.dispose();
  }

  String? _error;
  bool _busy = false;
  final _characters = <String, String>{};
  final _devices = <String, String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<ApiService>().toneStates(widget.pairId);
      if (mounted) {
        setState(() {
          _data = data;
          final research = data['research'] as Map?;
          if (_artist.text.isEmpty) {
            _artist.text = research?['artist_display'] as String? ?? '';
          }
          if (_song.text.isEmpty) {
            _song.text = research?['song_display'] as String? ?? '';
          }
          _version =
              (data['research'] as Map?)?['version'] as String? ?? 'unknown';
        });
      }
    } catch (_) {/* A análise de estados é opcional em presets antigos. */}
  }

  Future<void> _analyze({bool refresh = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await context.read<ApiService>().analyzeToneStates(
          widget.pairId, _version,
          refresh: refresh,
          artist: _artist.text.trim(),
          songTitle: _song.text.trim());
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate(Map state, String role) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      final research = _data?['research'] as Map?;
      final result = await api.generateToneState(
          widget.pairId,
          state['id'] as String,
          role,
          _devices[state['id']] ?? widget.rhythmDevice,
          _characters[state['id']] ?? state['character'] as String,
          research?['id'] as String?,
          researchRevision: research?['revision'] as String?);
      if (!mounted) return;
      final store = context.read<PresetStore>();
      await store.load();
      final id = result['pair_id'] as String;
      if (!store.pairs.any((pair) => pair.id == id)) {
        final pair = await api.getPresets(id);
        await store.save(pair);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await widget.onGenerated(id, role);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maps = (_data?['maps'] as List? ?? []);
    final states = [
      for (final map in maps) ...((map as Map)['states'] as List? ?? [])
    ];
    final research = _data?['research'] as Map?;
    return Card(
        child: ExpansionTile(
            title: const Text('Timbres ao longo da música'),
            subtitle: Text(states.isEmpty
                ? 'Detectar limpo, crunch e distorcido e pesquisar equipamento'
                : '${states.length} estados propostos — gerar base ou solo'),
            children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Uma mesma guitarra pode alternar limpo, crunch e distorcido. As propostas abaixo não identificam base/solo automaticamente.'),
                    TextField(
                        controller: _artist,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                            labelText: 'Artista para pesquisa'),
                        onChanged: (_) => setState(() => _data = null)),
                    TextField(
                        controller: _song,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                            labelText: 'Música para pesquisa'),
                        onChanged: (_) => setState(() => _data = null)),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _version,
                        decoration: const InputDecoration(
                            labelText: 'Versão usada como referência'),
                        items: const [
                          DropdownMenuItem(
                              value: 'unknown',
                              child:
                                  Text('Versão do arquivo não identificada')),
                          DropdownMenuItem(
                              value: 'studio',
                              child: Text('Gravação de estúdio')),
                          DropdownMenuItem(
                              value: 'live', child: Text('Ao vivo')),
                          DropdownMenuItem(
                              value: 'acoustic', child: Text('Acústica'))
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _version = value!;
                                  _data = null;
                                })),
                    FilledButton.icon(
                        onPressed: _busy ? null : () => _analyze(),
                        icon: const Icon(Icons.multitrack_audio),
                        label: Text(_data == null
                            ? 'Detectar timbres e pesquisar fontes'
                            : 'Atualizar análise dos timbres')),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const Text(
                          'Analisando guitarra ou gerando variante. A música salva será reutilizada.')
                    ],
                    if (_error != null)
                      SelectableText(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (_data != null && states.isEmpty)
                      const Text(
                          'Não há sinal de guitarra suficiente para propor estados neste trecho.'),
                    for (final raw in states) ...[
                      const Divider(),
                      Builder(builder: (context) {
                        final state = raw as Map;
                        final region = state['representative'] as Map;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(state['label'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  'Referência: ${region['start_seconds']} s — duração ${region['duration_seconds']} s. Confiança baixa; confira a proposta.'),
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _characters[state['id']] ??
                                      state['character'] as String,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Estado sonoro proposto (correção opcional)'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'clean', child: Text('Limpo')),
                                    DropdownMenuItem(
                                        value: 'crunch', child: Text('Crunch')),
                                    DropdownMenuItem(
                                        value: 'distorted',
                                        child: Text('Distorcido'))
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() =>
                                          _characters[state['id'] as String] =
                                              value!)),
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _devices[state['id']] ??
                                      widget.rhythmDevice,
                                  decoration: const InputDecoration(
                                      labelText: 'Pedal da variante'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'MK300', child: Text('MK300')),
                                    DropdownMenuItem(
                                        value: 'MK20', child: Text('MK20'))
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() =>
                                          _devices[state['id'] as String] =
                                              value!)),
                              Wrap(spacing: 8, children: [
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _generate(state, 'rhythm'),
                                    child:
                                        const Text('Gerar base deste timbre')),
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _generate(state, 'lead'),
                                    child:
                                        const Text('Gerar solo deste timbre'))
                              ]),
                            ]);
                      }),
                    ],
                    if (research != null)
                      ExpansionTile(
                          title: const Text(
                              'Fontes pesquisadas e contexto do equipamento'),
                          children: [
                            Text(research['note'] as String? ??
                                'Sem pesquisa disponível.'),
                            for (final raw in research['hints'] as List? ?? [])
                              ListTile(
                                  dense: true,
                                  title: Text(
                                      '${(raw as Map)['block']}: ${raw['model']}'),
                                  subtitle: Text(
                                      'Contexto: ${raw['scope']}. Família candidata; não comprova uso na versão enviada.')),
                            if ((research['sources'] as List? ?? []).isEmpty)
                              const Text(
                                  'Nenhuma fonte confiável encontrada. Os presets continuam baseados no áudio e no catálogo.'),
                            for (final raw
                                in research['sources'] as List? ?? [])
                              Builder(builder: (context) {
                                final source = raw as Map;
                                return ListTile(
                                    title: Text(
                                        source['title'] as String? ?? 'Fonte'),
                                    subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Contexto: ${source['context']}. ${source['note'] ?? ''}'),
                                          SelectableText(
                                              source['url'] as String),
                                          if (source['available'] != true)
                                            const Text(
                                                'Página não consultada nesta tentativa; verifique a fonte pelo link.')
                                        ]),
                                    trailing: IconButton(
                                        icon: const Icon(Icons.copy),
                                        tooltip: 'Copiar fonte',
                                        onPressed: () => Clipboard.setData(
                                            ClipboardData(
                                                text:
                                                    source['url'] as String))));
                              }),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _analyze(refresh: true),
                                child:
                                    const Text('Pesquisar novamente na web')),
                          ]),
                  ]))
        ]));
  }
}
