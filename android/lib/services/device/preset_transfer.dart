import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../../models/preset_pair.dart';
import 'device_transport.dart';
import 'mk300_protocol.dart';

class PreparedTransfer {
  final Object session;
  final int slot;
  final String name, backupPath;
  final Uint8List original, image;
  bool attempted = false;
  PreparedTransfer(this.session, this.slot, this.name, this.backupPath,
      this.original, this.image);
}

class Mk300TransferSession {
  final DeviceTransport transport;
  final Map<int, Map<String, dynamic>> catalog;
  final String deviceLabel;
  final Future<void> Function(Duration) pause;
  final Object _identity = Object();
  bool _busy = false;
  bool verified = false;
  bool _closed = false;
  Mk300TransferSession(this.transport, this.catalog,
      {required this.deviceLabel, Future<void> Function(Duration)? pause})
      : pause = pause ?? Future<void>.delayed;
  static Future<Map<int, Map<String, dynamic>>> loadCatalog() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/mk300_catalog.json'))
            as Map<String, dynamic>;
    return {
      for (final b in data['blocks'] as List)
        (b['id'] as num).toInt(): Map<String, dynamic>.from(b as Map)
    };
  }

  Map<int, int> get counts =>
      catalog.map((k, v) => MapEntry(k, (v['models'] as List).length));
  Future<T> _exclusive<T>(Future<T> Function() task) async {
    if (_closed || _busy) {
      throw StateError('Conexão fechada ou operação em andamento');
    }
    _busy = true;
    try {
      return await task();
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List> _request(
      Uint8List command, bool Function(Uint8List) matches,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final response = Completer<Uint8List>();
    final subscription = transport.frames.listen((f) {
      try {
        if (!response.isCompleted && matches(f)) response.complete(f);
      } on FormatException {/* Frame incorreto não autoriza a transferência. */}
    }, onError: (Object error) {
      if (!response.isCompleted) response.completeError(error);
    });
    // Instala o handler de erro antes de enviar, inclusive para falha imediata.
    final timer = Timer(timeout, () {
      if (!response.isCompleted) {
        response.completeError(
            TimeoutException('Pedaleira não respondeu', timeout));
      }
    });
    final pending = response.future;
    try {
      final results = await Future.wait<Object?>(
          [transport.send(command).then<Object?>((_) => null), pending],
          eagerError: true);
      return results[1] as Uint8List;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<Uint8List> _read(int field, int length, [int space = 1]) async {
    final frame =
        await _request(Mk300Protocol.read(field, length, space), (data) {
      final parsed = Mk300Protocol.parse(data);
      return parsed.cls == 13 &&
          parsed.space == space &&
          parsed.field == field &&
          parsed.length == length &&
          parsed.payload.length == length;
    });
    return Mk300Protocol.parse(frame).payload;
  }

  Future<void> _write(Uint8List command) async {
    await _request(command, Mk300Protocol.isAck,
        timeout: const Duration(seconds: 6));
  }

  Future<String> probe() => _exclusive(() async {
        verified = false;
        final image = await _read(0, 448);
        Mk300Protocol.validateImage(image, counts);
        // Valida também a leitura de flash sem modificar o preset ativo.
        final slot = await _read(0, 448, 0);
        Mk300Protocol.validateImage(slot, counts);
        verified = true;
        return Mk300Protocol.name(image);
      });
  static void validateName(String name) {
    if (!RegExp(r'^[\x20-\x7e]{1,19}$').hasMatch(name) || name.trim().isEmpty) {
      throw ArgumentError('Nome no pedal: 1 a 19 caracteres sem acentos.');
    }
  }

  Uint8List buildImage(PresetData preset, String name, Uint8List original) {
    validateName(name);
    if (preset.device != 'MK300' || preset.catalogVersion != '0.4.0') {
      throw StateError(
          'Reanalise o áudio para gerar um preset MK300 com o catálogo 0.4.0. Presets antigos não têm índices conferidos.');
    }
    Mk300Protocol.validateImage(original, counts);
    final image = Uint8List.fromList(
        original); // Preserva footswitches e todos os campos não documentados.
    final bytes = ByteData.sublistView(image);
    if (preset.presetVolume != null) {
      final volume = preset.presetVolume!;
      if (volume < 0 || volume > 100) {
        throw StateError('Volume do preset fora da escala');
      }
      bytes.setUint16(24, volume, Endian.little);
    }
    if (preset.centerPan) bytes.setInt16(28, 0, Endian.little);
    image.fillRange(0, 20, 0);
    image.setRange(0, name.length, name.codeUnits);
    image.fillRange(43, 54, 0);
    const blocks = {
      'wah': 0,
      'compressor': 1,
      'noise_gate': 2,
      'drive': 3,
      'amp': 4,
      'cabinet': 5,
      'eq': 6,
      'modulation': 7,
      'delay': 8,
      'reverb': 9,
      'volume': 10
    };
    final selected = <int>[];
    for (final block in preset.effectChain) {
      final id = blocks[block.effectType];
      if (id == null || selected.contains(id)) {
        throw StateError('Bloco não suportado ou duplicado');
      }
      selected.add(id);
      final modelId = int.tryParse(block.modelId);
      final models = catalog[id]!['models'] as List;
      if (modelId == null || modelId < 0 || modelId >= models.length) {
        throw StateError('Modelo fora do catálogo');
      }
      final model = Map<String, dynamic>.from(models[modelId] as Map);
      if (model['name'] != block.modelName) {
        throw StateError(
            'Nome/ID de modelo não corresponde ao catálogo capturado. Reanalise o áudio.');
      }
      final knobs = List<String>.from(model['knobs'] as List);
      final defaults = List<int>.from(model['defaults'] as List? ?? []);
      image[43 + id] = block.enabled ? 1 : 0;
      final changed = image[54 + id] != modelId;
      image[54 + id] = modelId;
      if (changed) {
        for (var k = 0; k < defaults.length; k++) {
          bytes.setInt16(66 + 24 * id + 2 * k, defaults[k], Endian.little);
        }
        final sync = knobs.indexOf('Sync');
        if (sync >= 0) {
          bytes.setInt16(66 + 24 * id + 2 * sync, 0, Endian.little);
        }
        // AMP/DS/CAB conservam knobs por mudança de modelo, como no editor.
        if (![3, 4, 5].contains(id) &&
            knobs.asMap().entries.any((e) =>
                e.key >= defaults.length &&
                e.value != 'Sync' &&
                !block.parameters.containsKey(e.value))) {
          throw StateError(
              'Defaults incompletos para ${block.modelName}; envio interrompido.');
        }
      }
      for (final param in block.parameters.entries) {
        final k = knobs.indexOf(param.key);
        final spec = block.parameterSpecs[param.key];
        if (k < 0 ||
            k >= 12 ||
            spec == null ||
            !param.value.isFinite ||
            param.value < spec.min ||
            param.value > spec.max ||
            param.value != param.value.roundToDouble() ||
            param.value < -32768 ||
            param.value > 32767) {
          throw StateError('Parâmetro não validado: ${param.key}');
        }
        bytes.setInt16(
            66 + 24 * id + 2 * k, param.value.toInt(), Endian.little);
      }
    }
    // Garante que a cadeia exibida pelo app seja a cadeia gravada.
    final order = [
      ...selected,
      ...List.generate(11, (i) => i).where((i) => !selected.contains(i))
    ];
    image.setRange(32, 43, order);
    if (preset.bpm != null) {
      bytes.setUint16(26, preset.bpm!.round().clamp(40, 250), Endian.little);
    }
    Mk300Protocol.validateImage(image, counts);
    return image;
  }

  Future<PreparedTransfer> prepare(PresetData preset, String name, int slot,
          Directory backupDirectory) =>
      _exclusive(() async {
        if (!verified || slot < 0 || slot >= 160) {
          throw StateError('Conexão não verificada ou slot inválido');
        }
        validateName(name);
        final original = await _read(slot * 448, 448, 0);
        final image = buildImage(preset, name, original);
        await backupDirectory.create(recursive: true);
        final file = File(
            '${backupDirectory.path}/mk300-slot-${slot + 1}-${DateTime.now().microsecondsSinceEpoch}.json');
        await file.writeAsString(
            jsonEncode({
              'format': 'ai-tone-backup',
              'version': 1,
              'device': 'MK300',
              'device_connection': deviceLabel,
              'slot': slot + 1,
              'original_name': Mk300Protocol.name(original),
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'image_base64': base64Encode(original)
            }),
            flush: true);
        // Falha ao salvar/ler o backup impede qualquer gravação no pedal.
        final saved =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (!Mk300Protocol.same(
            base64Decode(saved['image_base64'] as String), original)) {
          throw StateError('Falha ao validar backup');
        }
        return PreparedTransfer(_identity, slot, name, file.path,
            Uint8List.fromList(original), image);
      });
  Future<void> send(PreparedTransfer transfer, {required bool confirmed}) =>
      _exclusive(() async {
        if (!confirmed ||
            !verified ||
            !identical(transfer.session, _identity) ||
            transfer.attempted) {
          throw StateError('Envio sem confirmação ou de outra sessão');
        }
        final backup =
            jsonDecode(await File(transfer.backupPath).readAsString())
                as Map<String, dynamic>;
        if (!Mk300Protocol.same(base64Decode(backup['image_base64'] as String),
            transfer.original)) {
          throw StateError('Backup alterado. Prepare novamente.');
        }
        final current = await _read(transfer.slot * 448, 448, 0);
        if (!Mk300Protocol.same(current, transfer.original)) {
          throw StateError(
              'O slot mudou desde o backup. Prepare o envio novamente.');
        }
        transfer.attempted = true; // Nunca repete automaticamente uma gravação.
        await _write(Mk300Protocol.bankWrite(transfer.slot, transfer.image));
        await _write(Mk300Protocol.commit());
        await pause(const Duration(
            seconds: 3)); // Não envia comandos enquanto flash está ocupado.
        for (var attempt = 0; attempt < 8; attempt++) {
          try {
            final readback = await _read(transfer.slot * 448, 448, 0);
            if (Mk300Protocol.same(readback, transfer.image)) return;
          } on TimeoutException {/* Só repete leitura. */}
          await pause(const Duration(milliseconds: 750));
        }
        throw StateError(
            'Gravação não confirmada por leitura. Não repita o envio; confira o pedal. Backup preservado em ${transfer.backupPath}.');
      });
  Future<void> close() async {
    _closed = true;
    verified = false;
    await transport.close();
  }
}
