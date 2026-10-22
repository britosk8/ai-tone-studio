import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/preset_store.dart';
import '../services/mk300_pilot.dart';

class Mk300PilotScreen extends StatefulWidget {
  const Mk300PilotScreen({super.key});
  @override
  State<Mk300PilotScreen> createState() => _Mk300PilotScreenState();
}

class _Mk300PilotScreenState extends State<Mk300PilotScreen> {
  String? _sourceId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<PresetStore>().load();
  }

  Future<void> _generate(PresetPair source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _sourceId = source.id;
    });
    try {
      final candidates = await Mk300Pilot.generate(source);
      if (!mounted) return;
      await context.read<PresetStore>().saveOrReusePilotBatch(candidates);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível gerar os candidatos: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await context.read<PresetStore>().clearPilotCandidates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '$count candidatos removidos. Presets de origem preservados.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível limpar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PresetStore>();
    final pairs = store.pairs.where(Mk300Pilot.supports).toList();
    final selected = pairs.where((p) => p.id == _sourceId).firstOrNull ??
        (pairs.isEmpty ? null : pairs.first);
    final candidates = selected == null
        ? <PresetPair>[]
        : Mk300Pilot.existingFor(store.pairs, selected.id);
    final generatedCount = store.pairs.where(Mk300Pilot.isCandidate).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Piloto Infest — MK300')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Base • Konig Stratocaster SSS',
            style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        const Text(
            'Gere três candidatos a partir da referência aprovada no MK20. '
            'São pontos iniciais para comparar o som na MK300, ainda sem fidelidade validada.'),
        const SizedBox(height: 16),
        if (selected == null)
          const Text(
              'Nenhuma análise compatível. Analise Infest no app selecionando MK300 para base e solo. '
              'Os presets existentes de Infest com catálogo atualizado também podem ser usados.')
        else ...[
          DropdownButtonFormField<String>(
            value: selected.id,
            decoration: const InputDecoration(labelText: 'Preset de origem'),
            isExpanded: true,
            items: pairs
                .map((p) => DropdownMenuItem(
                    value: p.id,
                    child:
                        Text(p.rhythm.name, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged:
                _busy ? null : (value) => setState(() => _sourceId = value),
          ),
          const SizedBox(height: 16),
          const Text(
              'Os três candidatos usam os mesmos cortes do gabinete do preset de origem. '
              'Nesta rodada, o EQ adicional fica desligado. '
              'O solo anterior será mantido como cópia; somente a base será gerada.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || candidates.length == 3
                ? null
                : () => _generate(selected),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(_busy
                ? 'Gerando candidatos...'
                : candidates.length == 3
                    ? 'Candidatos já existentes'
                    : candidates.isEmpty
                        ? 'Gerar candidatos na biblioteca'
                        : 'Gerar somente candidatos faltantes'),
          ),
        ],
        if (generatedCount > 0)
          TextButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text('Limpar candidatos e recomeçar ($generatedCount)'),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        for (var i = 0; i < candidates.length; i++) ...[
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(candidates[i].rhythm.name,
                          style: const TextStyle(fontSize: 20)),
                      Text(candidates[i]
                                  .rhythm
                                  .generationMetadata['candidate'] ==
                              'A'
                          ? 'A • Primeiro candidato'
                          : candidates[i]
                                      .rhythm
                                      .generationMetadata['candidate'] ==
                                  'B'
                              ? 'B • Troca somente o amplificador de A'
                              : 'C • Troca somente o gabinete de A'),
                      Text(candidates[i]
                          .rhythm
                          .effectChain
                          .where((b) =>
                              b.effectType == 'amp' ||
                              b.effectType == 'cabinet')
                          .map((b) => b.modelName)
                          .join(' → ')),
                      FilledButton(
                          onPressed: () => Navigator.pushNamed(
                                  context, '/transfer', arguments: {
                                'pair_id': candidates[i].id,
                                'role': 'rhythm'
                              }),
                          child: const Text('Enviar base para a MK300')),
                      TextButton(
                          onPressed: () => Navigator.pushNamed(
                              context, '/presets',
                              arguments: {'pair_id': candidates[i].id}),
                          child: const Text('Ver presets salvos')),
                    ],
                  ))),
        ],
        const SizedBox(height: 16),
        const Text(
            'Toque a passagem 00:50–01:10 com o mesmo captador, volume e tone. '
            'Use o fluxo de envio com backup e escolha do slot. Depois, grave pelo app para comparar o resultado.'),
      ]),
    );
  }
}
