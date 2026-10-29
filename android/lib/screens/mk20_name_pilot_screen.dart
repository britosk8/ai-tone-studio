import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/device/device_transport.dart';
import '../services/device/mk20_diagnostics.dart';
import '../services/device/mk20_name_pilot.dart';

class Mk20NamePilotScreen extends StatefulWidget {
  const Mk20NamePilotScreen({super.key});
  @override
  State<Mk20NamePilotScreen> createState() => _Mk20NamePilotScreenState();
}

class _Mk20NamePilotScreenState extends State<Mk20NamePilotScreen> {
  bool _busy = false, _confirmedModel = false;
  List<Map<String, dynamic>> _devices = [];
  String? _deviceId;
  File? _backupFile;
  Map<String, dynamic>? _backup, _report;
  String _status = 'Conecte a MK20 por USB/OTG e feche o M-EFCS.';
  NativeDeviceTransport? _transport;

  @override
  void initState() {
    super.initState();
    _recover();
  }

  Future<Directory> _directory() async => Directory(
      '${(await getApplicationDocumentsDirectory()).path}/mk20_name_pilot');
  Future<void> _recover() async {
    try {
      final directory = await _directory();
      final pointer = File('${directory.path}/latest.json');
      if (await pointer.exists()) {
        final filename = (jsonDecode(await pointer.readAsString())
            as Map)['filename'] as String;
        if (!RegExp(r'^mk20-name-\d+\.json$').hasMatch(filename)) return;
        final file = File('${directory.path}/$filename');
        final backup = await Mk20NamePilot.load(file);
        final result = File('${directory.path}/last_result.json');
        final report = await result.exists()
            ? Map<String, dynamic>.from(
                jsonDecode(await result.readAsString()) as Map)
            : null;
        if (mounted && !_busy) {
          setState(() {
            _backupFile = file;
            _backup = backup;
            _report = report;
            _status =
                'Backup anterior recuperado. Você pode conferir o slot e restaurar o original após conectar.';
          });
        }
      }
    } catch (_) {
      /* No backup on first use. Invalid files never authorize writes. */
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
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
            _confirmedModel = false;
            _status = devices.isEmpty
                ? 'Nenhuma porta USB MIDI encontrada. Confira o cabo OTG.'
                : 'Confirme que o dispositivo conectado é a MK20.';
          });
        }
      });

  Future<T> _connected<T>(
      Future<T> Function(Mk20NamePilot pilot) action) async {
    if (!_confirmedModel || _deviceId == null) {
      throw StateError('Selecione e confirme a MK20 conectada.');
    }
    final transport = NativeDeviceTransport('usb', _deviceId!);
    _transport = transport;
    try {
      await transport.connect();
      return await action(Mk20NamePilot(transport));
    } finally {
      try {
        await transport.close();
      } catch (_) {/* Keep backup and result. */}
      if (_transport == transport) _transport = null;
    }
  }

  Future<void> _prepare() => _run(() async {
        if (_backup?['rename_attempted'] == true &&
            _backup?['restore_verified'] != true) {
          throw StateError(
              'Confira ou restaure o backup anterior antes de preparar outro teste.');
        }
        final directory = await _directory();
        final file = await _connected((pilot) => pilot.prepare(directory,
            deviceName: _devices.firstWhere(
                    (device) => device['id'] == _deviceId)['name'] as String? ??
                'USB MIDI'));
        final backup = await Mk20NamePilot.load(file);
        if (mounted) {
          setState(() {
            _backupFile = file;
            _backup = backup;
            _status =
                'Slot 150 lido. Backup integral salvo e conferido. Nada foi gravado ainda.';
          });
        }
      });

  Future<bool> _confirm(bool restore) async {
    final verifyOnly = restore && _backup?['restore_attempted'] == true;
    final original = Mk20Diagnostics.decode(
        base64Decode(_backup!['original_base64']))['name'];
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(verifyOnly
                      ? 'Conferir restauração por leitura?'
                      : restore
                          ? 'Restaurar slot 150?'
                          : 'Testar gravação do nome?'),
                  content: Text(verifyOnly
                      ? 'A restauração já foi tentada. Esta operação apenas relê o slot e confere o backup, sem repetir a escrita.'
                      : restore
                          ? 'Restaurar integralmente o backup do slot 150: $original. O app só grava se a leitura ainda corresponder ao teste.'
                          : 'O nome do slot 150 mudará de "$original" para "${Mk20NamePilot.testName}". Os demais bytes serão preservados. O backup original já está salvo. Este é o primeiro teste de escrita MK20; não desconecte até terminar.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(restore
                            ? 'Confirmar restauração'
                            : 'Confirmar teste no slot 150'))
                  ],
                )) ??
        false;
  }

  Future<void> _perform(bool restore) async {
    if (_busy || _backupFile == null || !await _confirm(restore) || !mounted) {
      return;
    }
    await _run(() async {
      setState(() => _status =
          'Gravando e aguardando a leitura de retorno. Mantenha o cabo conectado...');
      final report = await _connected((pilot) =>
          pilot.perform(_backupFile!, restore: restore, confirmed: true));
      final backup = await Mk20NamePilot.load(_backupFile!);
      if (!mounted) return;
      setState(() {
        _report = report;
        _backup = backup;
        _status = _result(report);
      });
      await _sync();
    });
  }

  String _result(Map report) {
    if (report['status'] == 'confirmed') {
      return report['operation'] == 'restore'
          ? 'Original do slot 150 restaurado e conferido por leitura.'
          : 'Nome do slot 150 gravado e conferido: ${Mk20NamePilot.testName}. Controles preservados.';
    }
    if (report['status'] == 'already_original') {
      return 'Slot 150 já corresponde ao backup original. Nenhuma gravação necessária.';
    }
    return 'Operação não confirmada: ${report['error'] ?? report['status']}. Backup preservado. Não repita a gravação; confira o slot.';
  }

  Future<void> _sync() async {
    final report = _report;
    if (report == null) return;
    try {
      final receipt =
          await context.read<ApiService>().saveMk20NamePilot(report);
      if (mounted) {
        setState(() => _status =
            '${_result(report)} Resultado salvo no backend: ${receipt['status']} (${receipt['id']}).');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status =
            '${_result(report)} Relatório preservado neste celular. Sincronização pendente: $error');
      }
    }
  }

  @override
  void dispose() {
    _transport?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Teste de escrita MK20')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Etapa 2 — testar nome do slot 150',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text(
              'Este teste altera apenas o nome. AMP, CAB, ganho, EQ e demais controles são preservados. '
              'O envio dos presets gerados pela música continua em preparação.'),
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
                          _confirmedModel = false;
                        })),
          CheckboxListTile(
              value: _confirmedModel,
              contentPadding: EdgeInsets.zero,
              title: const Text('Conectei a MK20 e fechei o M-EFCS.'),
              onChanged: _busy
                  ? null
                  : (value) =>
                      setState(() => _confirmedModel = value ?? false)),
          FilledButton(
              onPressed: _busy || !_confirmedModel || _deviceId == null
                  ? null
                  : _prepare,
              child: const Text('Ler slot 150 e preparar backup')),
          if (_backup != null) ...[
            Text(
                'Backup: ${Mk20Diagnostics.decode(base64Decode(_backup!['original_base64']))['name']} → ${Mk20Diagnostics.decode(base64Decode(_backup!['named_base64']))['name']}'),
            TextButton(
                onPressed: _busy || _backupFile == null
                    ? null
                    : () => _run(() async {
                          await Share.shareXFiles([XFile(_backupFile!.path)],
                              text: 'Backup original MK20 — slot 150');
                        }),
                child: const Text('Compartilhar backup original')),
            FilledButton(
                onPressed: _busy ||
                        !_confirmedModel ||
                        _deviceId == null ||
                        _backup!['rename_attempted'] == true
                    ? null
                    : () => _perform(false),
                child: const Text('Revisar e testar gravação do nome')),
            OutlinedButton(
                onPressed: _busy ||
                        !_confirmedModel ||
                        _deviceId == null ||
                        _backup!['rename_attempted'] != true ||
                        _backup!['restore_verified'] == true
                    ? null
                    : () => _perform(true),
                child: Text(_backup!['restore_attempted'] == true
                    ? 'Conferir restauração por leitura'
                    : 'Restaurar original do slot 150')),
          ],
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SelectableText(_status),
          if (_report != null)
            TextButton(
                onPressed: _busy ? null : () => _run(_sync),
                child: const Text('Enviar resultado ao backend')),
          OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.pushNamed(context, '/mk20-diagnostics'),
              child: const Text('Conferir por leitura, sem gravar')),
        ]),
      );
}
