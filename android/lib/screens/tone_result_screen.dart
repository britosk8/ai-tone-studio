import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/preset_store.dart';
import '../services/tone_adjustments.dart';

/// Revisão explícita; só persiste ao usuário aceitar e nunca grava automaticamente no pedal.
class ToneResultScreen extends StatefulWidget {
  final String pairId, role;
  final PresetData preset;
  final Map<String, dynamic> report;
  const ToneResultScreen(
      {super.key,
      required this.pairId,
      required this.role,
      required this.preset,
      required this.report});
  @override
  State<ToneResultScreen> createState() => _ToneResultScreenState();
}

class _ToneResultScreenState extends State<ToneResultScreen> {
  bool _busy = false, _saved = false;
  String? _error;
  late final List<Map<String, dynamic>> _suggestions;
  late final Set<int> _selected;
  bool get _clipped => widget.report['quality'] == 'clipped';
  @override
  void initState() {
    super.initState();
    _suggestions = (widget.report['suggestions'] as List? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    _selected = {for (var i = 0; i < _suggestions.length; i++) i};
  }

  String _number(dynamic value) =>
      value is num ? value.toStringAsFixed(value % 1 == 0 ? 0 : 1) : '—';
  Future<void> _save({bool send = false}) async {
    if (_busy || _clipped || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = context.read<PresetStore>();
      final pair = store.pairs.where((p) => p.id == widget.pairId).firstOrNull;
      if (pair == null) {
        throw StateError('O preset foi excluído da biblioteca.');
      }
      final current = widget.role == 'lead' ? pair.lead : pair.rhythm;
      if (current.id != widget.preset.id ||
          current.catalogVersion != widget.preset.catalogVersion) {
        throw StateError(
            'O preset mudou desde a comparação. Analise novamente.');
      }
      final updated = applyToneAdjustments(
          current, [for (final i in _selected) _suggestions[i]]);
      await store.save(pair.withPreset(updated));
      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      if (send) await _send();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro: $e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _send() async {
    await Navigator.pushNamed(context, '/transfer',
        arguments: {'pair_id': widget.pairId, 'role': widget.role});
  }

  @override
  Widget build(BuildContext context) {
    final differences = widget.report['differences_db'] as Map? ?? {};
    final measuredBands = [
      'bass',
      'middle',
      'treble'
    ].every((k) => differences[k] is num && (differences[k] as num).isFinite);
    final hasDifferences =
        differences.values.whereType<num>().any((v) => v.abs() >= 3);
    final heading = _clipped
        ? 'Gravação saturada — grave novamente'
        : _suggestions.isNotEmpty
            ? 'Ajustes recomendados para o preset'
            : hasDifferences
                ? 'Há diferenças, mas sem ajuste automático disponível'
                : measuredBands
                    ? 'EQ sem ajustes recomendados'
                    : 'Sem ajustes automáticos recomendados';
    final explanation = _clipped
        ? 'O sinal chegou saturado (clipping). Essa captura não permite avaliar o timbre com segurança. Reduza o nível enviado pela pedaleira à USB ou o nível de entrada da interface e grave novamente. Reduzir o volume depois de gravar não recupera o sinal.'
        : _suggestions.isNotEmpty
            ? 'Revise as mudanças abaixo. Elas atualizam este preset da biblioteca; depois você pode enviá-lo ao pedal.'
            : hasDifferences
                ? 'As diferenças medidas não puderam ser convertidas em mudanças neste amplificador, por limites ou controles indisponíveis. Confira o trecho de referência e revise o preset manualmente.'
                : !measuredBands
                    ? 'A comparação não retornou mudanças automáticas nem medições completas. Revise a referência e faça uma nova comparação.'
                    : 'Graves, médios e agudos estão dentro do limiar de 3 dB desta comparação. Não há mudança de EQ recomendada. Isso não confirma que ganho, efeitos ou timbre sejam iguais ao original.';
    final capture = widget.report['recording'] as Map? ?? {};
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Resultado e ajustes')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(widget.preset.name,
                style: Theme.of(context).textTheme.titleLarge),
            Text(
                '${widget.role == 'lead' ? 'Solo' : 'Base'} — ${widget.preset.device}'),
            if (widget.report['reference_source'] == 'saved_track_profile')
              const Text(
                  'Referência: perfil geral da música. Para comparar a mesma passagem, selecione o áudio original e o início do trecho.'),
            if (widget.report['reference_source'] == 'selected_excerpt')
              const Text('Referência: trecho selecionado do áudio original.'),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_clipped
                              ? Icons.warning_amber
                              : _suggestions.isNotEmpty
                                  ? Icons.tune
                                  : Icons.info_outline),
                          const SizedBox(height: 8),
                          Text(heading,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(explanation),
                          if (_clipped && capture['clipped_fraction'] is num)
                            Text(
                                'Amostras próximas ao limite: ${((capture['clipped_fraction'] as num) * 100).toStringAsFixed(1)}%'),
                        ]))),
            if (!_clipped) ...[
              Text(widget.report['summary'] as String? ?? ''),
              if (differences.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Diferenças medidas em relação à referência',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final entry in {
                  'bass': 'Graves',
                  'middle': 'Médios',
                  'treble': 'Agudos'
                }.entries)
                  if (differences[entry.key] is num)
                    ListTile(
                        dense: true,
                        title: Text(entry.value),
                        trailing: Text(
                            '${(differences[entry.key] as num) >= 0 ? '+' : ''}${_number(differences[entry.key])} dB')),
                const Text(
                    'Energia relativa por faixa; não é percentual de semelhança.'),
              ],
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Mudanças no preset existente',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (var i = 0; i < _suggestions.length; i++)
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(i),
                      onChanged: _busy || _saved
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(i);
                                } else {
                                  _selected.remove(i);
                                }
                              }),
                      title: Text(
                          '${_suggestions[i]['parameter']}: ${_number(_suggestions[i]['before'])} → ${_number(_suggestions[i]['after'])}'),
                      subtitle:
                          Text(_suggestions[i]['reason'] as String? ?? '')),
                if (!_saved) ...[
                  FilledButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => _save(send: true),
                      child:
                          const Text('Atualizar preset e seguir para envio')),
                  OutlinedButton(
                      onPressed:
                          _busy || _selected.isEmpty ? null : () => _save(),
                      child:
                          const Text('Salvar ajustes sugeridos no aplicativo')),
                ],
              ],
              if (_saved) ...[
                const Text(
                    'Preset existente atualizado na biblioteca. Envie para aplicar as mudanças no pedal.'),
                FilledButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('Enviar preset ajustado ao pedal')),
              ],
              if (_suggestions.isEmpty)
                OutlinedButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('Enviar preset atual sem alterações')),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              SelectableText(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(_clipped
                    ? 'Voltar e gravar novamente'
                    : 'Voltar para gravar outra comparação')),
            if (!_clipped)
              ExpansionTile(
                  title: const Text('Limitações da comparação'),
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            'Sugestões orientativas com confiança baixa. Apenas EQ é ajustado automaticamente; ganho, amp/cabinet e efeitos não foram validados.')),
                    for (final text
                        in widget.report['limitations'] as List? ?? [])
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(text.toString())),
                  ]),
          ]),
        ));
  }
}
