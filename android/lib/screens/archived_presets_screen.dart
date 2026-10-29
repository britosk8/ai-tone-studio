import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/preset_store.dart';
import '../services/preset_archive.dart';

class ArchivedPresetsScreen extends StatefulWidget {
  const ArchivedPresetsScreen({super.key});
  @override
  State<ArchivedPresetsScreen> createState() => _ArchivedPresetsScreenState();
}

class _ArchivedPresetsScreenState extends State<ArchivedPresetsScreen> {
  List<PresetPair>? _pairs;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pairs = await PresetArchive.load();
      if (mounted) setState(() => _pairs = pairs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _restore(PresetPair pair) async {
    setState(() => _busy = true);
    try {
      await PresetArchive.restore(context.read<PresetStore>(), pair.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preset restaurado na biblioteca.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Presets arquivados')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Os presets dos testes anteriores estão guardados aqui. Suas músicas, instrumentos separados, gravações e backups foram preservados.'),
        if (_error != null) Text(_error!),
        if (_pairs == null) const LinearProgressIndicator(),
        if (_pairs?.isEmpty == true)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nenhum preset arquivado.')),
        for (final pair in _pairs ?? <PresetPair>[])
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            pair.rhythm.songTitle.isNotEmpty
                                ? pair.rhythm.songTitle
                                : pair.rhythm.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            'Base: ${pair.rhythm.name} — ${pair.rhythm.device}\nSolo: ${pair.lead.name} — ${pair.lead.device}'),
                        TextButton.icon(
                            onPressed: _busy ? null : () => _restore(pair),
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('Restaurar na biblioteca')),
                      ]))),
      ]));
}
