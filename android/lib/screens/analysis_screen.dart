import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/preset_store.dart';
import '../models/preset_pair.dart';
import '../theme/app_theme.dart';

class AnalysisScreen extends StatefulWidget {
  final String jobId;
  const AnalysisScreen({super.key, required this.jobId});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  Timer? _timer;
  AnalysisJob? _job;
  String _statusLabel = 'Iniciando análise...';
  bool _done = false;
  bool _failed = false;
  bool _polling = false;
  String? _errorMessage;

  static const _labels = {
    'pending': 'Aguardando processamento...',
    'running': 'Analisando características do áudio...',
    'separating': 'Separando guitarra e demais instrumentos por IA...',
    'compiling': 'Gerando presets...',
    'done': 'Presets gerados!',
    'failed': 'Falha no processamento',
  };

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_done && !_failed) _poll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _done || _failed) return;
    _polling = true;
    try {
      final api = context.read<ApiService>();
      final job = await api.getJobStatus(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _statusLabel = job.progressMessage ?? _labels[job.status] ?? job.status;
        _errorMessage = job.errorMessage;
        _done = job.isDone;
        _failed = job.isFailed;
      });

      if (job.isDone && job.pairId != null) {
        _timer?.cancel();
        await _loadAndSavePair(job.pairId!);
      } else if (job.isFailed) {
        _timer?.cancel();
      }
    } catch (e) {
      if (mounted) {
        if (e is ApiException && e.statusCode == 404) {
          _timer?.cancel();
          setState(() {
            _failed = true;
            _errorMessage =
                'Análise não encontrada. O backend pode ter reiniciado. Importe a música novamente.';
          });
        } else {
          setState(() =>
              _statusLabel = 'Conexão interrompida. Tentando novamente...');
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadAndSavePair(String pairId) async {
    try {
      final store = context.read<PresetStore>();
      await store.load();
      if (!mounted) return;
      if (!store.pairs.any((pair) => pair.id == pairId)) {
        final pair = await context.read<ApiService>().getPresets(pairId);
        if (!mounted) return;
        await store.save(pair);
      }
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/presets',
            arguments: {'pair_id': pairId});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analisando'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_failed) ...[
              const _AnimatedWaveform(),
              const SizedBox(height: 48),
              Text(_statusLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              if (_job != null && _job!.progressPercent > 0) ...[
                const SizedBox(height: 24),
                _ProgressBar(value: _job!.progressPercent / 100),
                Text('${_job!.progressPercent}%',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
              if (!_done) ...[
                const SizedBox(height: 32),
                const _StepList(),
              ],
            ] else ...[
              const Icon(Icons.error_outline,
                  size: 64, color: AppTheme.errorRed),
              const SizedBox(height: 24),
              Text('Falha no processamento',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppTheme.errorRed)),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Erro desconhecido',
                  style: const TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/', (_) => false),
                child: const Text('Voltar ao início'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedWaveform extends StatefulWidget {
  const _AnimatedWaveform();

  @override
  State<_AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<_AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(7, (i) {
          final phase = (i / 7 + _ctrl.value) % 1.0;
          final h = 20.0 + 50.0 * (0.5 + 0.5 * _sineApprox(phase * 6.28));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 6,
              height: h,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }

  double _sineApprox(double x) {
    // Aproximação rápida de sin(x)
    final t = x / (2 * 3.14159265);
    final normalized = t - t.floor();
    return normalized < 0.5
        ? 4 * normalized * (1 - 2 * normalized)
        : -4 * (normalized - 1) * (2 * normalized - 1);
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList();

  static const steps = [
    (Icons.audio_file, 'Carregamento do áudio'),
    (Icons.equalizer, 'Análise espectral'),
    (Icons.graphic_eq, 'Estimativa de timbre'),
    (Icons.tune, 'Geração de presets'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: steps
          .map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(s.$1, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Text(s.$2,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
