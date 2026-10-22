import 'package:flutter/material.dart';
import '../models/preset_pair.dart';
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';

class PresetEditorScreen extends StatefulWidget {
  final PresetData preset;
  final String pairId;

  const PresetEditorScreen(
      {super.key, required this.preset, required this.pairId});

  @override
  State<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends State<PresetEditorScreen> {
  late List<EffectBlock> _chain;
  bool _modified = false;

  @override
  void initState() {
    super.initState();
    _chain = List.from(widget.preset.effectChain);
  }

  void _toggleBlock(int i, bool enabled) {
    setState(() {
      _chain[i] = _chain[i].copyWith(enabled: enabled);
      _modified = true;
    });
  }

  void _updateParam(int blockIndex, String paramName, double value) {
    final block = _chain[blockIndex];
    final newParams = Map<String, double>.from(block.parameters);
    newParams[paramName] = value;
    setState(() {
      _chain[blockIndex] = block.copyWith(parameters: newParams);
      _modified = true;
    });
  }

  Future<bool> _onWillPop() async {
    if (!_modified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Descartar alterações?'),
        content: const Text('As edições não foram salvas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuar editando')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _save() {
    // Retorna o preset editado para a tela anterior
    setState(() => _modified = false);
    Navigator.pop(context, widget.preset.copyWith(effectChain: _chain));
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        widget.preset.role == 'rhythm' ? 'Base (Ritmo)' : 'Solo (Lead)';

    return PopScope<PresetData>(
      canPop: !_modified,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _onWillPop() && mounted) {
          setState(() => _modified = false);
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Editar — $roleLabel'),
          actions: [
            if (_modified)
              TextButton(
                onPressed: _save,
                child: const Text('Salvar',
                    style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        body: Column(
          children: [
            _DeviceHeader(
                device: widget.preset.device, role: widget.preset.role),
            Expanded(
              child: ListView.builder(
                itemCount: _chain.length,
                padding: const EdgeInsets.only(bottom: 24),
                itemBuilder: (ctx, i) => _EffectEditor(
                  block: _chain[i],
                  onToggle: (v) => _toggleBlock(i, v),
                  onParamChanged: (name, v) => _updateParam(i, name, v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  final String device;
  final String role;

  const _DeviceHeader({required this.device, required this.role});

  @override
  Widget build(BuildContext context) {
    final color =
        role == 'rhythm' ? AppTheme.accentBlue : AppTheme.accentOrange;
    return Container(
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.08),
      child: Row(
        children: [
          Icon(Icons.queue_music, color: color, size: 24),
          const SizedBox(width: 12),
          Text(device, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              role == 'rhythm' ? 'RITMO' : 'SOLO',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectEditor extends StatelessWidget {
  final EffectBlock block;
  final ValueChanged<bool> onToggle;
  final void Function(String, double) onParamChanged;

  const _EffectEditor({
    required this.block,
    required this.onToggle,
    required this.onParamChanged,
  });

  static const _typeLabels = {
    'noise_gate': 'Gate de Ruído',
    'compressor': 'Compressor',
    'drive': 'Drive / Overdrive',
    'amp': 'Amplificador',
    'cabinet': 'Gabinete',
    'modulation': 'Modulação',
    'delay': 'Delay',
    'reverb': 'Reverberação',
    'wah': 'Wah',
    'eq': 'Equalizador',
    'volume': 'Volume',
  };

  @override
  Widget build(BuildContext context) {
    final typeLabel = _typeLabels[block.effectType] ?? block.effectType;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          // Cabeçalho do bloco
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeLabel,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                      Text(block.modelName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
                ConfidenceBadge(level: block.generatedConfidence),
                const SizedBox(width: 8),
                Switch(value: block.enabled, onChanged: onToggle),
              ],
            ),
          ),
          // Parâmetros
          if (block.enabled && block.parameters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: block.parameters.entries.map((entry) {
                  return _ParamSlider(
                    name: entry.key,
                    value: entry.value,
                    spec: block.parameterSpecs[entry.key],
                    onChanged: (v) => onParamChanged(entry.key, v),
                  );
                }).toList(),
              ),
            ),
          // Justificativa de geração
          if (block.generationRationale.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      block.generationRationale,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String name;
  final double value;
  final ValueChanged<double> onChanged;
  final ParameterSpec? spec;

  const _ParamSlider(
      {required this.name,
      required this.value,
      required this.onChanged,
      this.spec});

  @override
  Widget build(BuildContext context) {
    final min = spec?.min ?? 0;
    final max = spec?.max ?? 100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(name, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(
                '${value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1)} ${spec?.unit ?? ''}',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (spec == null)
            const Text(
                "Limites indisponíveis neste preset antigo. Gere novamente para editar este parâmetro.",
                style: TextStyle(fontSize: 11))
          else
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / spec!.step).round().clamp(1, 10000),
              onChanged: (v) => onChanged(
                  (min + ((v - min) / spec!.step).round() * spec!.step)
                      .clamp(min, max)),
            ),
        ],
      ),
    );
  }
}
