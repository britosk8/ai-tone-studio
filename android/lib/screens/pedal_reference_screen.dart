import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/preset_store.dart';
import '../services/api_service.dart';
import '../services/pedal_reference.dart';
import '../services/device/device_transport.dart';
import '../services/device/preset_transfer.dart';

class PedalReferenceScreen extends StatefulWidget {
  final String pairId;
  const PedalReferenceScreen({super.key, required this.pairId});
  @override
  State<PedalReferenceScreen> createState() => _PedalReferenceScreenState();
}

class _PedalReferenceScreenState extends State<PedalReferenceScreen> {
  final _repository = PedalReferenceRepository();
  final _slot = TextEditingController(text: '1');
  final _scroll = ScrollController();
  PresetPair? _pair;
  PedalReference? _reference;
  PresetData? _decoded;
  Map<int, Map<String, dynamic>>? _catalog;
  List<Map<String, dynamic>> _devices = [];
  String? _deviceId;
  String _role = 'rhythm', _status = '';
  String _syncStatus = '';
  bool _busy = true, _confirmed = false;
  bool _operationRunning = false;
  NativeDeviceTransport? _transport;
  PresetData? get _generated => _role == 'rhythm' ? _pair?.rhythm : _pair?.lead;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => _run(() async {
        final store = context.read<PresetStore>();
        await store.load();
        final pair =
            store.pairs.where((p) => p.id == widget.pairId).firstOrNull;
        if (pair == null) {
          throw StateError('Análise não encontrada na biblioteca.');
        }
        if (pair.rhythm.device != 'MK300' && pair.lead.device != 'MK300') {
          throw StateError(
              'Esta comparação requer um preset gerado para MK300.');
        }
        _catalog = await Mk300TransferSession.loadCatalog();
        if (!mounted) return;
        _pair = pair;
        if ((_role == 'rhythm' ? pair.rhythm : pair.lead).device != 'MK300') {
          _role = pair.rhythm.device == 'MK300' ? 'rhythm' : 'lead';
        }
        await _loadReference();
      });

  Future<void> _loadReference() async {
    final reference = await _repository.load(widget.pairId, _role);
    if (!mounted) return;
    final decoded = reference?.decode(_catalog!);
    setState(() {
      _reference = reference;
      _decoded = decoded;
    });
    if (reference != null) await _syncReference();
  }

  Future<void> _syncReference() async {
    final reference = _reference;
    final pair = _pair;
    if (reference == null || pair == null) return;
    try {
      await context
          .read<ApiService>()
          .syncPedalReference(pair, _role, reference);
      if (mounted) {
        setState(() => _syncStatus = 'Referência salva também no backend.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _syncStatus =
            'Referência salva no celular. Sincronização com o backend pendente; tente novamente quando ele estiver disponível.');
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_operationRunning) return;
    _operationRunning = true;
    if (mounted) setState(() => _busy = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro: $e');
    } finally {
      _operationRunning = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() => _run(() async {
        final devices = await NativeDeviceTransport.devices('usb');
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _deviceId = devices.isEmpty ? null : devices.first['id'] as String;
          _status = devices.isEmpty
              ? 'Nenhuma entrada USB MIDI encontrada. Confira o cabo OTG.'
              : 'Selecione a MK300 e o slot que deseja importar.';
        });
      });

  Future<void> _import() => _run(() async {
        final slot = int.tryParse(_slot.text.trim());
        if (!_confirmed ||
            _deviceId == null ||
            _generated?.device != 'MK300' ||
            slot == null ||
            slot < 1 ||
            slot > 160) {
          throw StateError(
              'Selecione a MK300, confirme o modelo e informe um slot entre 1 e 160.');
        }
        final role = _role;
        FocusScope.of(context).unfocus();
        final transport = NativeDeviceTransport('usb', _deviceId!);
        _transport = transport;
        Mk300TransferSession? session;
        try {
          await transport.connect();
          session = Mk300TransferSession(transport, _catalog!,
              deviceLabel: 'usb:$_deviceId');
          await session.probe();
          final image = await session.readSlot(slot - 1);
          final reference = PedalReference(
              slot: slot,
              connection: 'usb:$_deviceId',
              capturedAt: DateTime.now().toUtc().toIso8601String(),
              image: image);
          final decoded = reference.decode(_catalog!);
          if (!mounted) return;
          await _repository.save(widget.pairId, role, reference);
          if (!mounted) return;
          setState(() {
            _reference = reference;
            _decoded = decoded;
            _status =
                'Preset ${reference.name} importado como referência. Nenhum preset foi alterado.';
          });
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_status)));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) {
              _scroll.animateTo(0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
            }
          });
        } finally {
          if (session != null) {
            await session.close();
          } else {
            await transport.close();
          }
          _transport = null;
        }
        if (mounted) await _syncReference();
      });

  @override
  void dispose() {
    _slot.dispose();
    _scroll.dispose();
    _transport?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generated = _generated;
    final reference = _decoded;
    final rows = generated != null && reference != null
        ? comparePedalConfiguration(generated, reference)
        : <ConfigurationDifference>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Referência do pedal')),
      body: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
                'A música continua sendo a referência principal. Importe um preset da MK300 que você gosta para comparar com o resultado gerado pelo app.'),
            if (_pair != null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(
                    labelText: 'Preset gerado para comparar'),
                isExpanded: true,
                items: [
                  for (final p in [_pair!.rhythm, _pair!.lead])
                    if (p.device == 'MK300')
                      DropdownMenuItem(
                          value: p.role,
                          child: Text(
                              '${p.role == 'rhythm' ? 'Base' : 'Solo'} — ${p.name}',
                              overflow: TextOverflow.ellipsis))
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          _run(() async {
                            setState(() {
                              _role = value;
                              _reference = null;
                              _decoded = null;
                              _status = '';
                              _syncStatus = '';
                            });
                            await _loadReference();
                          });
                        }
                      },
              ),
            ],
            const SizedBox(height: 16),
            if (_reference != null && reference != null && generated != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(),
                            Text(
                                'Referência: ${_reference!.name} • slot ${_reference!.slot}',
                                style: const TextStyle(fontSize: 20)),
                            Text('Gerado: ${generated.name}'),
                            if (_syncStatus.isNotEmpty) Text(_syncStatus),
                            TextButton(
                                onPressed:
                                    _busy ? null : () => _run(_syncReference),
                                child: const Text(
                                    'Sincronizar referência com o backend')),
                            Text(
                                '${rows.where((r) => r.changed).length} diferenças de configuração'),
                            const Text(
                                'Valores lidos do pedal, sem conversão de escala. Valores iguais em modelos diferentes não significam sons iguais. Nomes seguem o catálogo de fábrica; modelos ou gabinetes importados no pedal podem ter outro som.'),
                            ExpansionTile(
                                title: const Text('Ver modelos e controles'),
                                children: [
                                  for (final row in rows)
                                    ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(row.label),
                                        subtitle: Text(
                                            'Gerado: ${row.generated}\nPedal: ${row.reference}'),
                                        leading: Icon(
                                            row.changed
                                                ? Icons.compare_arrows
                                                : Icons.check,
                                            size: 18)),
                                ]),
                            const Text(
                                'Esta comparação não mede fidelidade sonora e não altera automaticamente o preset gerado. Para avaliar o som, grave sua guitarra e compare com a música original.'),
                            FilledButton(
                                onPressed: () => Navigator.pushNamed(
                                        context, '/compare', arguments: {
                                      'pair_id': widget.pairId
                                    }).then((_) {
                                      if (mounted) _load();
                                    }),
                                child: const Text(
                                    'Gravar e comparar com a música')),
                          ]))),
            const Text(
                'Conecte a MK300 por USB/OTG e feche o M-EFCS. Esta operação apenas lê o slot, sem trocar o preset ativo ou gravar no pedal.'),
            OutlinedButton(
                onPressed: _busy ? null : _scan,
                child: const Text('Buscar MK300 por USB')),
            if (_devices.isNotEmpty)
              DropdownButtonFormField<String>(
                  value: _deviceId,
                  decoration:
                      const InputDecoration(labelText: 'Dispositivo USB'),
                  items: _devices
                      .map((d) => DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text((d['name'] ?? d['id']).toString())))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (id) => setState(() {
                            _deviceId = id;
                            _confirmed = false;
                          })),
            CheckboxListTile(
                value: _confirmed,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Confirmo que o equipamento conectado é a MK300.'),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _confirmed = value == true)),
            TextField(
                controller: _slot,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Slot para importar (1–160)')),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _busy ||
                        !_confirmed ||
                        _deviceId == null ||
                        generated == null
                    ? null
                    : _import,
                icon: const Icon(Icons.download_outlined),
                label: Text(_busy ? 'Aguarde...' : 'Importar preset do pedal')),
            const Text(
                'Importar novamente substitui somente a referência desta análise e função. O preset gerado e a música permanecem preservados.'),
            if (_status.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_status)),
          ]),
    );
  }
}
