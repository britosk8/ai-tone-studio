import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

/// Auditions a temporary copy. Selection is returned only after confirmation.
class ReferencePreviewScreen extends StatefulWidget {
  final String pairId, role;
  final Map<String, dynamic> info;
  final List<Map<String, dynamic>>? intervals;
  final int? fixedChannel;
  const ReferencePreviewScreen(
      {super.key,
      required this.pairId,
      required this.role,
      required this.info,
      this.intervals,
      this.fixedChannel});
  @override
  State<ReferencePreviewScreen> createState() => _ReferencePreviewScreenState();
}

class _ReferencePreviewScreenState extends State<ReferencePreviewScreen>
    with WidgetsBindingObserver {
  static const _audio = MethodChannel('ai_tone/preview');
  final _id = 'preview-${DateTime.now().microsecondsSinceEpoch}';
  late List<Map<String, dynamic>> _intervals;
  late double _start, _duration;
  int _interval = 0, _generation = 0;
  int? _channel;
  double _gain = 0, _position = 0, _total = 0;
  bool _loading = false, _playing = false, _disposed = false;
  String? _error;
  Timer? _timer;
  File? _file;
  double get _lower =>
      (_intervals[_interval]['start_seconds'] as num).toDouble();
  double get _span =>
      (_intervals[_interval]['duration_seconds'] as num).toDouble();
  double get _end => _lower + _span;
  String _time(double s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toStringAsFixed(1).padLeft(4, '0')}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lower = (widget.info['cache_start_seconds'] as num?)?.toDouble() ??
        (widget.info['available_duration'] == null
            ? (widget.info['start_seconds'] as num).toDouble()
            : 0);
    final span = (widget.info['available_duration'] as num?)?.toDouble() ??
        (widget.info['duration_seconds'] as num).toDouble();
    _intervals = (widget.intervals ??
            [
              {'start_seconds': lower, 'duration_seconds': span}
            ])
        .where((i) => (i['duration_seconds'] as num) >= 3)
        .toList();
    if (_intervals.isEmpty) {
      _intervals = [
        {'start_seconds': lower, 'duration_seconds': math.max(3, span)}
      ];
    }
    _start = (widget.info['start_seconds'] as num).toDouble();
    _interval = math.max(
        0,
        _intervals.indexWhere((i) =>
            _start >= (i['start_seconds'] as num) &&
            _start <
                (i['start_seconds'] as num) + (i['duration_seconds'] as num)));
    _duration = math
        .min(
            30,
            math.min(
                _span, (widget.info['duration_seconds'] as num).toDouble()))
        .clamp(3, 30)
        .toDouble();
    _start = _start.clamp(_lower, _end - _duration).toDouble();
    _channel = widget.fixedChannel ??
        (widget.info['analysis_channel'] as num?)?.toInt() ??
        -1;
  }

  Future<void> _stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final old = _file;
    _file = null;
    if (mounted && !_disposed) setState(() => _playing = _loading = false);
    try {
      await _audio.invokeMethod<void>('stop', {'id': _id});
    } catch (_) {/* Already stopped at Activity lifecycle. */}
    if (old != null) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  void _changed(VoidCallback change) {
    unawaited(_stop());
    setState(() {
      change();
      _position = 0;
    });
  }

  Future<void> _play() async {
    await _stop();
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<ApiService>().downloadReferencePreview(
          widget.pairId, widget.role, _start, _duration,
          channel: _channel, listenGainDb: _gain);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$_id-$generation.wav');
      await file.writeAsBytes(List<int>.from(data['bytes'] as List),
          flush: true);
      if (!mounted || generation != _generation) {
        await file.delete();
        return;
      }
      _file = file;
      final result = await _audio.invokeMapMethod<String, dynamic>('play',
          {'id': _id, 'path': file.path}).timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _playing = true;
        _total =
            ((result?['duration_ms'] as num?)?.toDouble() ?? _duration * 1000) /
                1000;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
        try {
          final status = await _audio
              .invokeMapMethod<String, dynamic>('status', {'id': _id});
          if (!mounted || generation != _generation) return;
          setState(() {
            _position =
                ((status?['position_ms'] as num?)?.toDouble() ?? 0) / 1000;
            _playing = status?['playing'] == true;
            if (status?['error'] != null) _error = '${status!['error']}';
          });
          if (!_playing) {
            _timer?.cancel();
            _timer = null;
          }
        } catch (_) {
          await _stop();
        }
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        await _stop();
        if (mounted) {
          setState(() => _error = 'Não foi possível ouvir o trecho: $e');
        }
      }
    }
  }

  Future<void> _confirm() async {
    final selected = {
      'start_seconds': _start,
      'duration_seconds': _duration,
      if (_channel != null) 'channel': _channel!
    };
    await _stop();
    if (mounted) Navigator.pop(context, selected);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Ouvir e escolher trecho')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Guitarra separada da música',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Ouça a guitarra separada. Escolha uma passagem em que ela esteja audível e toque a mesma passagem ao gravar seu pedal.'),
        if (_intervals.length > 1)
          DropdownButtonFormField<int>(
              value: _interval,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Intervalo deste timbre'),
              items: [
                for (var i = 0; i < _intervals.length; i++)
                  DropdownMenuItem(
                      value: i,
                      child: Text(
                          '${_time((_intervals[i]['start_seconds'] as num).toDouble())} — ${_time((_intervals[i]['start_seconds'] as num).toDouble() + (_intervals[i]['duration_seconds'] as num))}'))
              ],
              onChanged: _loading
                  ? null
                  : (i) => _changed(() {
                        _interval = i!;
                        _duration = math.min(_duration, _span);
                        _start = _lower;
                      })),
        const SizedBox(height: 16),
        Text('Início: ${_time(_start)}'),
        Slider(
            value: _start,
            min: _lower,
            max: math.max(_lower, _end - _duration),
            divisions: math.max(1, ((_span - _duration) * 10).round()),
            onChanged: _loading ? null : (v) => _changed(() => _start = v)),
        Text('Duração: ${_duration.toStringAsFixed(1)} segundos'),
        Slider(
            value: _duration,
            min: 3,
            max: math.max(3, math.min(30, _span)),
            divisions: math.max(1, ((math.min(30, _span) - 3) * 10).round()),
            onChanged: _loading
                ? null
                : (v) => _changed(() {
                      _duration = v;
                      _start =
                          _start.clamp(_lower, _end - _duration).toDouble();
                    })),
        if (widget.fixedChannel == null &&
            (widget.info['channels'] as num? ?? 2) > 1)
          DropdownButtonFormField<int>(
              isExpanded: true,
              value: _channel ?? -1,
              decoration: const InputDecoration(labelText: 'Canal da guitarra'),
              items: const [
                DropdownMenuItem(
                    value: -1, child: Text('Canal mais audível do trecho')),
                DropdownMenuItem(value: 0, child: Text('Esquerdo (L)')),
                DropdownMenuItem(value: 1, child: Text('Direito (R)'))
              ],
              onChanged: _loading ? null : (v) => _changed(() => _channel = v)),
        Text('Volume extra para escuta: +${_gain.round()} dB'),
        Slider(
            value: _gain,
            min: 0,
            max: 18,
            divisions: 6,
            onChanged: _loading ? null : (v) => _changed(() => _gain = v)),
        const Text(
            'Este volume altera apenas a reprodução. A geração e a comparação usam o áudio original.'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _loading
                ? null
                : _playing
                    ? _stop
                    : _play,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(_loading
                ? 'Preparando áudio...'
                : _playing
                    ? 'Parar'
                    : 'Ouvir trecho')),
        if (_loading) const LinearProgressIndicator(),
        if (_playing) ...[
          LinearProgressIndicator(
              value: _total > 0 ? (_position / _total).clamp(0, 1) : 0),
          Text('${_time(_position)} / ${_time(_total)}')
        ],
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 20),
        OutlinedButton(
            onPressed: _loading ? null : _confirm,
            child: const Text('Usar este trecho')),
      ]));
}
