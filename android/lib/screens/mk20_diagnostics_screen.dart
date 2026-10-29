import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/device/device_transport.dart';
import '../services/device/mk20_diagnostics.dart';

class Mk20DiagnosticsScreen extends StatefulWidget {
  const Mk20DiagnosticsScreen({super.key});
  @override
  State<Mk20DiagnosticsScreen> createState() => _Mk20DiagnosticsScreenState();
}

class _Mk20DiagnosticsScreenState extends State<Mk20DiagnosticsScreen> {
  final _slot = TextEditingController(text: '150');
  String _firmware = 'Não sei',
      _status = 'Conecte a MK20 por USB/OTG e feche o M-EFCS.';
  String? _deviceId, _filePath;
  List<Map<String, dynamic>> _devices = [];
  Map<String, dynamic>? _report;
  bool _busy = false, _confirmed = false;
  NativeDeviceTransport? _transport;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<Directory> _directory() async => Directory(
      '${(await getApplicationDocumentsDirectory()).path}/mk20_diagnostics');

  Future<void> _restore() async {
    try {
      final directory = await _directory();
      final latest = File('${directory.path}/latest.json');
      if (!await latest.exists()) return;
      final saved =
          jsonDecode(await latest.readAsString()) as Map<String, dynamic>;
      if (mounted && !_busy && _report == null) {
        setState(() {
          _report = saved;
          _filePath = latest.path;
          _status =
              'Último diagnóstico recuperado. Você pode enviá-lo ao backend novamente.';
        });
      }
    } catch (_) {/* A primeira leitura não exige arquivo prévio. */}
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) setState(() => _status = 'Erro: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() => _run(() async {
        final devices = await NativeDeviceTransport.devices('usb');
        if (mounted) {
          setState(() {
            _devices = devices;
            _deviceId = devices.isEmpty ? null : devices.first['id'] as String;
            _status = devices.isEmpty
                ? 'Nenhuma porta USB MIDI encontrada. Confira energia, cabo de dados e adaptador OTG.'
                : 'Selecione a MK20 e confirme o equipamento antes de testar.';
          });
        }
      });

  Future<void> _sync() async {
    final report = _report;
    if (report == null) return;
    try {
      final result =
          await context.read<ApiService>().saveMk20Diagnostic(report);
      if (mounted) {
        final summary = result['status'] == 'read_layout_confirmed'
            ? 'Backend confirmou as duas leituras MK20 preservadas no diagnóstico.'
            : _localResult(report);
        setState(() {
          _status = '$summary Diagnóstico salvo no backend: ${result['id']}. '
              'Envio de preset MK20 ainda indisponível.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status =
            '${_localResult(report)} Cópia salva neste celular. Backend indisponível: $error. '
                'Use Enviar diagnóstico ao backend para tentar novamente.');
      }
    }
  }

  String _localResult(Map<String, dynamic> report) {
    final reads = report['reads'] as List;
    final valid =
        reads.where((read) => (read as Map)['decoded'] != null).length;
    if (valid == 2) {
      final active = (reads.first as Map)['decoded'] as Map;
      final stored = (reads.last as Map)['decoded'] as Map;
      return 'Duas leituras compatíveis com MK20. Ativo: ${active['name']}. '
          'Slot ${report['slot']}: ${stored['name']}. Nenhum preset alterado.';
    }
    return 'Teste incompleto: $valid de 2 leituras compatíveis. Nenhum comando de gravação foi enviado.';
  }

  Future<void> _test() => _run(() async {
        final slot = int.tryParse(_slot.text);
        if (!_confirmed ||
            _deviceId == null ||
            slot == null ||
            slot < 1 ||
            slot > 150) {
          throw StateError(
              'Selecione a MK20, confirme o modelo e informe um slot entre 1 e 150.');
        }
        final device =
            _devices.firstWhere((device) => device['id'] == _deviceId);
        late Mk20Diagnostics diagnostics;
        final transport = NativeDeviceTransport('usb', _deviceId!,
            onRawData: (bytes) => diagnostics.record('rx_raw', bytes));
        diagnostics = Mk20Diagnostics(transport);
        _transport = transport;
        Map<String, dynamic> report;
        try {
          await transport.connect();
          if (mounted) {
            setState(
                () => _status = 'Lendo preset ativo e slot $slot. Aguarde...');
          }
          report = await diagnostics.run(
              slot: slot,
              deviceName: device['name'] as String? ?? 'USB MIDI',
              firmware: _firmware);
        } catch (error) {
          report = {
            'format': 'ai-tone-mk20-diagnostic',
            'version': 1,
            'device': 'MK20',
            'transport': 'usb',
            'device_name': device['name'] as String? ?? 'USB MIDI',
            'firmware_reported': _firmware,
            'slot': slot,
            'captured_at': DateTime.now().toUtc().toIso8601String(),
            'reads': [
              for (final space in [1, 0])
                {
                  'space': space,
                  'field': space == 1 ? 0 : (slot - 1) * Mk20Diagnostics.size,
                  'error': '$error',
                }
            ],
            'trace': diagnostics.trace,
            'write_enabled': false,
          };
        } finally {
          await transport.close();
          if (_transport == transport) _transport = null;
        }
        final directory = await _directory();
        await directory.create(recursive: true);
        final file = File(
            '${directory.path}/mk20-${DateTime.now().microsecondsSinceEpoch}.json');
        final json = const JsonEncoder.withIndent('  ').convert(report);
        await file.writeAsString(json, flush: true);
        await File('${directory.path}/latest.json')
            .writeAsString(json, flush: true);
        if (!mounted) return;
        setState(() {
          _report = report;
          _filePath = file.path;
          _status = '${_localResult(report)} Sincronizando diagnóstico...';
        });
        await _sync();
      });

  @override
  void dispose() {
    _transport?.close();
    _slot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Testar MK20 por USB')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Primeiro teste da MK20',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text(
              'Este teste lê o preset ativo e um slot, salva uma cópia e envia o diagnóstico ao backend. '
              'Não troca o preset ativo nem grava no pedal. O envio dos presets gerados será uma etapa posterior.'),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _busy ? null : _scan,
              child: const Text('Buscar MK20 por USB/OTG')),
          if (_devices.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _deviceId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Dispositivo USB MIDI'),
              items: _devices
                  .map((device) => DropdownMenuItem(
                      value: device['id'] as String,
                      child: Text('${device['name']} (${device['id']})',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _deviceId = value;
                        _confirmed = false;
                      }),
            ),
          DropdownButtonFormField<String>(
            value: _firmware,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Firmware informado por você'),
            items: const [
              DropdownMenuItem(
                  value: 'Não sei',
                  child: Text('Não sei — não detectado automaticamente',
                      overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(
                  value: 'V085',
                  child: Text('V085 — versão listada no site oficial',
                      overflow: TextOverflow.ellipsis))
            ],
            onChanged:
                _busy ? null : (value) => setState(() => _firmware = value!),
          ),
          TextField(
              controller: _slot,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Slot para ler (1–150)',
                  helperText:
                      'Somente leitura. O conteúdo não será sobrescrito.')),
          CheckboxListTile(
              value: _confirmed,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                  'Confirmei que conectei a MK20 e fechei o M-EFCS.'),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false)),
          FilledButton(
              onPressed:
                  _busy || !_confirmed || _deviceId == null ? null : _test,
              child: const Text('Ler MK20 e salvar diagnóstico')),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SelectableText(_status),
          if (_report != null) ...[
            for (final raw in _report!['reads'] as List)
              ListTile(
                  title: Text((raw as Map)['space'] == 1
                      ? 'Preset ativo'
                      : 'Slot ${_report!['slot']}'),
                  subtitle: Text(raw['decoded'] == null
                      ? '${raw['error']}'
                      : '${raw['decoded']['name']} — imagem MK20 de 412 bytes')),
            TextButton(
                onPressed: _busy ? null : () => _run(_sync),
                child: const Text('Enviar diagnóstico ao backend')),
            TextButton(
                onPressed: _busy || _filePath == null
                    ? null
                    : () => _run(() async {
                          await Share.shareXFiles([XFile(_filePath!)],
                              text: 'Diagnóstico MK20 — somente leitura');
                        }),
                child: const Text('Compartilhar cópia do diagnóstico')),
          ],
        ]),
      );
}
