import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class CalibrationTestCard extends StatefulWidget {
  final String recordingId, role;
  const CalibrationTestCard(
      {super.key, required this.recordingId, required this.role});
  @override
  State<CalibrationTestCard> createState() => _CalibrationTestCardState();
}

class _CalibrationTestCardState extends State<CalibrationTestCard> {
  String _guitar = 'unknown',
      _pickup = 'unknown',
      _route = 'unknown',
      _signal = 'unknown',
      _assessment = 'unrated';
  bool _applied = false, _busy = false, _dirty = false;
  String? _status;
  final _notes = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted && !_dirty) {
      setState(() {
        _guitar = prefs.getString('calibration_guitar_${widget.role}') ??
            (widget.role == 'rhythm'
                ? 'konig_strat_sss'
                : 'strinberg_les_paul_hh');
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await context
          .read<ApiService>()
          .saveRecordingEvaluation(widget.recordingId, {
        'guitar': _guitar,
        'pickup': _pickup,
        'route': _route,
        'signal': _signal,
        'preset_applied': _applied,
        'assessment': _assessment,
        'notes': _notes.text.trim()
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('calibration_guitar_${widget.role}', _guitar);
      if (mounted) {
        setState(() => _status = result['eligible_for_review'] == true
            ? 'Teste registrado com áudio, preset, referência e sua avaliação.'
            : 'Teste registrado. Complete os dados e use a mesma passagem para uma comparação mais útil.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Não foi possível registrar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _select(String label, String value, Map<String, String> choices,
          ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          decoration: InputDecoration(labelText: label),
          items: choices.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: _busy
              ? null
              : (v) {
                  _dirty = true;
                  setState(() => onChanged(v!));
                });
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
          child: ExpansionTile(
              title: const Text('Registrar teste para calibração'),
              subtitle: const Text(
                  'Guardar guitarra, captador e avaliação deste resultado'),
              children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  _select('Guitarra', _guitar, {
                    'unknown': 'Não informado',
                    'konig_strat_sss': 'Konig Stratocaster — SSS',
                    'strinberg_les_paul_hh': 'Strinberg Les Paul — HH'
                  }, (v) {
                    _guitar = v;
                    _pickup = 'unknown';
                  }),
                  _select(
                      'Captador / posição',
                      _pickup,
                      {
                        'unknown': 'Não informado',
                        'bridge': 'Ponte',
                        if (_guitar == 'konig_strat_sss') ...{
                          'bridge_middle': 'Ponte + meio',
                          'middle': 'Meio',
                          'middle_neck': 'Meio + braço'
                        },
                        if (_guitar == 'strinberg_les_paul_hh') 'both': 'Ambos',
                        'neck': 'Braço'
                      },
                      (v) => _pickup = v),
                  _select(
                      'Conexão usada na gravação',
                      _route,
                      {
                        'unknown': 'Não informado',
                        'pedal_usb': 'USB/OTG da pedaleira',
                        'mq44_analog': 'Saída analógica → MQ44',
                        'other': 'Outra entrada'
                      },
                      (v) => _route = v),
                  _select(
                      'Sinal gravado',
                      _signal,
                      {
                        'unknown': 'Não conferi',
                        'processed': 'Som processado pelo preset',
                        'dry': 'DI seco, sem o preset'
                      },
                      (v) => _signal = v),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _applied,
                      onChanged:
                          _busy ? null : (v) => setState(() => _applied = v!),
                      title: const Text(
                          'Toquei com este preset aplicado no pedal.')),
                  _select(
                      'Como ficou em relação à referência?',
                      _assessment,
                      {
                        'unrated': 'Ainda não avaliei',
                        'needs_adjustment': 'Precisa melhorar',
                        'close': 'Ficou próximo',
                        'worse': 'Piorou após o ajuste',
                        'approved': 'Aprovado para o ensaio'
                      },
                      (v) => _assessment = v),
                  TextField(
                      controller: _notes,
                      enabled: !_busy,
                      maxLength: 1000,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'O que você ouviu? (opcional)',
                          hintText:
                              'Ex.: muito grave, pouco ataque, drive excessivo')),
                  const Text(
                      'A avaliação registra o teste. Ela não altera o preset nem treina automaticamente o motor.'),
                  FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy
                          ? 'Salvando...'
                          : 'Guardar avaliação deste teste')),
                  if (_status != null) Text(_status!),
                ]))
          ]));
}
