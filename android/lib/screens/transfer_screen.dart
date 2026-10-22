import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/preset_pair.dart';
import '../services/api_service.dart';
import '../services/preset_store.dart';
import '../services/device/device_transport.dart';
import '../services/device/preset_transfer.dart';
import '../services/device/mk300_protocol.dart';

class TransferScreen extends StatefulWidget {
  final String pairId;
  final String? initialRole;
  const TransferScreen({super.key, required this.pairId, this.initialRole});
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  PresetPair? _pair;
  String _role = 'rhythm',
      _kind = 'usb',
      _status = 'Escolha o preset e conecte a pedaleira.';
  String _firmware = 'V75';
  List<Map<String, dynamic>> _devices = [];
  String? _deviceId;
  final _name = TextEditingController(),
      _slot = TextEditingController(text: '160');
  Mk300TransferSession? _session;
  NativeDeviceTransport? _transport;
  PreparedTransfer? _prepared;
  bool _busy = false, _confirmedModel = false;
  int? _mtu;
  PresetData? get _preset => _role == 'rhythm' ? _pair?.rhythm : _pair?.lead;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = context.read<PresetStore>();
      await store.load();
      if (!mounted) return;
      final pair =
          store.pairs.where((p) => p.id == widget.pairId).firstOrNull ??
              await context.read<ApiService>().getPresets(widget.pairId);
      if (!mounted) return;
      if (!store.pairs.any((p) => p.id == pair.id)) await store.save(pair);
      if (!mounted) return;
      setState(() {
        _pair = pair;
        _role = ['rhythm', 'lead'].contains(widget.initialRole)
            ? widget.initialRole!
            : pair.rhythm.device == "MK300"
                ? "rhythm"
                : pair.lead.device == "MK300"
                    ? "lead"
                    : "rhythm";
      });
      _setName();
    } catch (e) {
      if (mounted) setState(() => _status = 'Não foi possível carregar: $e');
    }
  }

  void _setName() {
    final preset = _preset;
    if (preset == null) return;
    final text = preset.name.replaceAll(RegExp(r'[^\x20-\x7e]'), '-');
    _name.text = preset.device == 'MK300' && text.length > 19
        ? text.substring(0, 19)
        : text;
    _slot.text = preset.device == 'MK300' ? '160' : '150';
    _prepared = null;
  }

  String _pairLabel(PresetPair pair) {
    final title = pair.rhythm.songTitle.isNotEmpty
        ? pair.rhythm.songTitle
        : pair.rhythm.name;
    return pair.rhythm.artist.isNotEmpty
        ? '${pair.rhythm.artist} — $title'
        : title;
  }

  Future<void> _selectPreset(PresetPair pair, String role) => _run(() async {
        final previousDevice = _preset?.device;
        final selected = role == 'rhythm' ? pair.rhythm : pair.lead;
        if (selected.device != previousDevice) {
          await _disconnect();
          _confirmedModel = false;
        }
        if (mounted) {
          setState(() {
            _pair = pair;
            _role = role;
            _setName();
          });
        }
      });
  Future<void> _reanalyze() async {
    final pair = _pair;
    if (pair == null) return;
    await _disconnect();
    if (!mounted) return;
    await Navigator.pushNamed(context, '/upload', arguments: {
      'artist': pair.rhythm.artist,
      'song_title': pair.rhythm.songTitle.isNotEmpty
          ? pair.rhythm.songTitle
          : pair.lead.songTitle,
      'rhythm_device': pair.rhythm.device,
      'lead_device': pair.lead.device,
    });
    // A importação substitui sua rota durante a análise. A biblioteca se atualiza
    // pelo store; a nova tela de resultados permite enviar o preset recém-gerado.
  }

  String? _blockReason(PresetData? preset) {
    if (_busy) return 'Aguarde a operação em andamento.';
    if (preset == null) return 'Escolha um preset da biblioteca.';
    if (preset.device != 'MK300') {
      return 'Envio MK20 indisponível. Selecione um preset gerado para MK300.';
    }
    if (preset.catalogVersion != '0.4.0') {
      return 'Envio bloqueado pelo preset antigo. Toque em Gerar preset atualizado ou selecione uma análise recente.';
    }
    if (!_confirmedModel) return 'Confirme o modelo do equipamento conectado.';
    if (_session?.verified != true) {
      return 'Conecte e confira a leitura do pedal antes de preparar o envio.';
    }
    if (_kind == 'ble' && (_mtu ?? 23) < 466) {
      return 'MTU Bluetooth insuficiente. Use USB/OTG.';
    }
    final slot = int.tryParse(_slot.text);
    if (slot == null || slot < 1 || slot > 160) {
      return 'Informe um slot entre 1 e 160.';
    }
    try {
      Mk300TransferSession.validateName(_name.text.trim());
    } catch (_) {
      return 'Informe um nome de 1 a 19 caracteres sem acentos.';
    }
    return null;
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) {
        final message = 'Erro: $e';
        setState(() => _status = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final session = _session;
    final transport = _transport;
    _session = null;
    _transport = null;
    _prepared = null;
    _mtu = null;
    if (session != null) {
      await session.close();
    } else {
      await transport?.close();
    }
  }

  Future<void> _scan() => _run(() async {
        await _disconnect();
        if (_kind == 'ble') {
          // Android 12+ pede dispositivos próximos; versões anteriores usam localização para busca BLE.
          final nearby = await Permission.bluetoothScan.request();
          final connect = await Permission.bluetoothConnect.request();
          if (!nearby.isGranted || !connect.isGranted) {
            await Permission.locationWhenInUse.request();
          }
        }
        if (mounted) {
          setState(() => _status = _kind == 'ble'
              ? 'Buscando BLE por alguns segundos...'
              : 'Buscando USB MIDI...');
        }
        final found = await NativeDeviceTransport.devices(_kind);
        if (mounted) {
          setState(() {
            _devices = found;
            _deviceId = found.isEmpty ? null : found.first['id'] as String;
            _status = found.isEmpty
                ? 'Nenhuma pedaleira encontrada. Confira energia, Bluetooth/cabo OTG e feche o M-EFCS.'
                : 'Selecione o dispositivo encontrado.';
          });
        }
      });
  Future<void> _connect() => _run(() async {
        if (_deviceId == null || !_confirmedModel) {
          throw StateError(
              'Selecione o dispositivo e confirme o modelo conectado.');
        }
        await _disconnect();
        final transport = NativeDeviceTransport(_kind, _deviceId!);
        _transport = transport;
        final info = await transport.connect();
        _mtu = (info['mtu'] as num?)?.toInt();
        if (_preset?.device != 'MK300') {
          if (mounted) {
            setState(() => _status =
                'Transporte conectado. MK20: envio bloqueado; perfil ainda sem captura de comandos. Use o guia manual.');
          }
          return;
        }
        try {
          final session = Mk300TransferSession(
              transport, await Mk300TransferSession.loadCatalog(),
              deviceLabel:
                  '$_kind:${_deviceId!}; firmware informado $_firmware');
          _session = session;
          final current = await session.probe();
          if (mounted) {
            setState(() => _status =
                'MK300: layout e leitura conferidos. Preset ativo: $current. Firmware informado: $_firmware.${_mtu != null ? ' MTU BLE: $_mtu.' : ''}');
          }
        } catch (_) {
          await _disconnect();
          rethrow;
        }
      });
  Future<void> _renameLocal() => _run(() async {
        final preset = _preset;
        if (preset == null) return;
        final name = _name.text.trim();
        if (name.isEmpty) throw ArgumentError('Informe um nome.');
        final updated = _pair!.withPreset(preset.copyWith(name: name));
        await context.read<PresetStore>().save(updated);
        if (mounted) {
          setState(() {
            _pair = updated;
            _prepared = null;
            _status =
                'Nome salvo na biblioteca. O título do áudio foi mantido.';
          });
        }
      });
  Future<void> _prepare() => _run(() async {
        final session = _session, preset = _preset;
        if (session == null || preset == null) {
          throw StateError('Conecte e confira a pedaleira primeiro.');
        }
        if (_kind == 'ble' && (_mtu ?? 23) < 466) {
          throw StateError(
              'MTU BLE insuficiente para a imagem completa. Use USB/OTG.');
        }
        final value = int.tryParse(_slot.text);
        if (value == null || value < 1 || value > 160) {
          throw ArgumentError('Escolha slot de 1 a 160.');
        }
        final directory = await getApplicationDocumentsDirectory();
        final prepared = await session.prepare(preset, _name.text.trim(),
            value - 1, Directory('${directory.path}/pedal_backups'));
        if (mounted) {
          setState(() {
            _prepared = prepared;
            _status =
                'Backup salvo. Slot $value contém "${Mk300Protocol.name(prepared.original)}". Revise e confirme o envio.';
          });
        }
      });
  Future<void> _send() => _run(() async {
        final prepared = _prepared, session = _session;
        if (prepared == null || session == null) {
          throw StateError('Prepare o backup novamente.');
        }
        final confirmation = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
                  title: const Text('Substituir preset no pedal?'),
                  content: Text(
                      'MK300 — slot ${prepared.slot + 1}\nAtual: ${Mk300Protocol.name(prepared.original)}\nNovo nome: ${prepared.name}\n\nO backup já foi salvo. Confirme que os modelos de fábrica usados não foram substituídos por NAM/IR. O envio ainda precisa de validação física no seu equipamento.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirmar envio'))
                  ],
                ));
        if (confirmation != true || !mounted) return;
        setState(() => _status =
            'Enviando e aguardando confirmação por leitura. Mantenha o cabo/Bluetooth e a energia.');
        await session.send(prepared, confirmed: true);
        if (!mounted) return;
        final message = 'Preset ${prepared.name} enviado com sucesso';
        try {
          await _disconnect();
        } catch (_) {/* Leitura de retorno já confirmou o envio. */}
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        setState(() => _busy = false);
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        messenger.showSnackBar(SnackBar(
            content: Text(message), duration: const Duration(seconds: 5)));
      });
  Future<void> _shareBackup() => _run(() async {
        final file = _prepared?.backupPath;
        if (file == null) return;
        await Share.shareXFiles([XFile(file)],
            subject: 'Backup original MK300');
      });
  @override
  void dispose() {
    _session?.close();
    if (_session == null) _transport?.close();
    _name.dispose();
    _slot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = _preset;
    final library = context.watch<PresetStore>().pairs;
    final blockReason = _blockReason(preset);
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Enviar para pedaleira')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            if (_pair == null)
              Text(_status)
            else ...[
              const Text('1. Escolha a música e o preset',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_pair!.id),
                value: _pair!.id,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Música / análise salva'),
                items: library
                    .map((pair) => DropdownMenuItem(
                        value: pair.id,
                        child: Text(_pairLabel(pair),
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) {
                        final selected = library.firstWhere((p) => p.id == id);
                        _selectPreset(selected, _role);
                      },
              ),
              const SizedBox(height: 8),
              RadioListTile<String>(
                  value: 'rhythm',
                  groupValue: _role,
                  title: Text(_pair!.rhythm.name),
                  subtitle: Text('Base — ${_pair!.rhythm.device}'),
                  onChanged:
                      _busy ? null : (role) => _selectPreset(_pair!, role!)),
              RadioListTile<String>(
                  value: 'lead',
                  groupValue: _role,
                  title: Text(_pair!.lead.name),
                  subtitle: Text('Solo — ${_pair!.lead.device}'),
                  onChanged:
                      _busy ? null : (role) => _selectPreset(_pair!, role!)),
              Text(
                  'Áudio: ${preset!.songTitle.isNotEmpty ? preset.songTitle : "Nome não registrado nesta análise antiga"}'),
              if (preset.device == 'MK300' && preset.catalogVersion != '0.4.0')
                Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Preset antigo — envio bloqueado',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const Text(
                                  'A conexão com o pedal pode funcionar, mas este preset não tem os índices do catálogo atual. Escolha uma análise recente acima ou gere uma nova análise com o áudio original.'),
                              FilledButton(
                                  onPressed: _busy ? null : _reanalyze,
                                  child: const Text('Gerar preset atualizado')),
                            ]))),
              TextField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: InputDecoration(
                      labelText: 'Nome do preset no envio',
                      helperText: preset.device == 'MK300'
                          ? 'Até 19 caracteres sem acentos. O nome do áudio não muda.'
                          : 'Nome para biblioteca e guia manual.'),
                  onChanged: (_) => setState(() => _prepared = null)),
              TextButton(
                  onPressed: _busy ? null : _renameLocal,
                  child: const Text('Salvar nome na biblioteca')),
              if (preset.device == 'MK20')
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            'MK20: a conexão pode ser investigada, mas o envio está bloqueado até comprovar o perfil de comandos. Seu formato é diferente da MK300.'))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: const InputDecoration(labelText: 'Conexão'),
                  items: const [
                    DropdownMenuItem(
                        value: 'usb', child: Text('USB MIDI — cabo OTG')),
                    DropdownMenuItem(
                        value: 'ble',
                        child: Text('Bluetooth BLE — em validação'))
                  ],
                  onChanged: _busy
                      ? null
                      : (v) async {
                          await _disconnect();
                          if (mounted) {
                            setState(() {
                              _kind = v!;
                              _devices = [];
                              _deviceId = null;
                            });
                          }
                        }),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _busy ? null : _scan,
                  child: const Text('Buscar pedaleiras')),
              if (_devices.isNotEmpty)
                DropdownButtonFormField<String>(
                    value: _deviceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Dispositivo encontrado'),
                    items: _devices
                        .map((d) => DropdownMenuItem(
                            value: d['id'] as String,
                            child: Text('${d['name']} (${d['id']})',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) async {
                            await _disconnect();
                            if (mounted) setState(() => _deviceId = v);
                          }),
              if (preset.device == 'MK300')
                DropdownButtonFormField<String>(
                    value: _firmware,
                    decoration: const InputDecoration(
                        labelText: 'Firmware informado por você'),
                    items: const [
                      DropdownMenuItem(
                          value: 'V75',
                          child: Text('V75 — disponível no site oficial')),
                      DropdownMenuItem(
                          value: 'V73',
                          child: Text('V73 — captura de referência'))
                    ],
                    onChanged: _busy
                        ? null
                        : (v) async {
                            await _disconnect();
                            if (mounted) setState(() => _firmware = v!);
                          }),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmedModel,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _confirmedModel = v ?? false),
                  title: Text(
                      'Confirmo que o equipamento conectado é ${preset.device} e fechei o M-EFCS.')),
              FilledButton(
                  onPressed: _busy || _deviceId == null || !_confirmedModel
                      ? null
                      : _connect,
                  child: const Text('Conectar e conferir leitura')),
              const SizedBox(height: 12),
              TextField(
                  controller: _slot,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Slot de destino (1–160 na MK300)'),
                  onChanged: (_) => setState(() => _prepared = null)),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: blockReason == null ? _prepare : null,
                  child: const Text('Ler destino e salvar backup')),
              if (blockReason != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(blockReason,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (_prepared != null) ...[
                TextButton(
                    onPressed: _busy ? null : _shareBackup,
                    child: const Text('Compartilhar backup original')),
                FilledButton(
                    onPressed: _busy || _prepared!.attempted ? null : _send,
                    child: const Text('Revisar e enviar preset')),
              ],
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              SelectableText(_status),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.pushNamed(context, '/presets',
                          arguments: {'pair_id': _pair!.id}),
                  child: const Text('Abrir presets e guia manual')),
            ],
          ]),
        ));
  }
}
