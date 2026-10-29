import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../../models/preset_pair.dart';
import 'device_transport.dart';
import 'mk20_diagnostics.dart';
import 'mk300_protocol.dart';
import 'preset_transfer.dart';

/// MK20 AM4 only. Slot 150 is the first complete-preset hardware pilot.
/// Never uses the MK300 bank-write command or its 448-byte layout.
class Mk20TransferSession implements PedalTransferSession {
  static const size = 412, targetSlot = 149;
  final DeviceTransport transport;
  final Map<String, dynamic> catalog;
  final String deviceLabel;
  final Future<void> Function(Duration) pause;
  final Duration timeout;
  final Object _identity = Object();
  final List<Map<String, dynamic>> trace = [];
  Map<String, dynamic>? lastReport;
  bool _busy = false, _closed = false;
  @override
  bool verified = false;
  Mk20TransferSession(this.transport, this.catalog,
      {required this.deviceLabel,
      Future<void> Function(Duration)? pause,
      this.timeout = const Duration(seconds: 5)})
      : pause = pause ?? Future<void>.delayed;
  static Future<Map<String, dynamic>> loadCatalog() async =>
      Map<String, dynamic>.from(
          jsonDecode(await rootBundle.loadString('assets/mk20_catalog.json'))
              as Map);
  static void validateName(String name) {
    if (!RegExp(r'^[\x20-\x7e]{1,16}$').hasMatch(name) || name.trim().isEmpty) {
      throw ArgumentError('Nome MK20: 1 a 16 caracteres sem acentos.');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() task) async {
    if (_closed || _busy) {
      throw StateError('Conexão fechada ou operação em andamento.');
    }
    _busy = true;
    try {
      return await task();
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List> _request(
      Uint8List command, bool Function(Uint8List) matches) async {
    final response = Completer<Uint8List>();
    void record(String direction, Uint8List bytes) {
      if (trace.length < 192) {
        trace
            .add({'direction': direction, 'bytes_base64': base64Encode(bytes)});
      }
    }

    final subscription = transport.frames.listen((f) {
      record('rx', f);
      try {
        if (!response.isCompleted && matches(f)) response.complete(f);
      } on FormatException {/* Malformed data cannot authorize writing. */}
    }, onError: (Object error) {
      if (!response.isCompleted) response.completeError(error);
    });
    final timer = Timer(timeout, () {
      if (!response.isCompleted) {
        response.completeError(TimeoutException('MK20 não respondeu.'));
      }
    });
    record('tx', command);
    try {
      final result = await Future.wait<Object?>(
          [transport.send(command).then<Object?>((_) => null), response.future],
          eagerError: true);
      return result[1] as Uint8List;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<Uint8List> _read(int slot, [int space = 0]) async {
    final offset = space == 1 ? 0 : slot * size;
    final frame = await _request(Mk300Protocol.read(offset, size, space), (f) {
      final p = Mk300Protocol.parse(f);
      return p.cls == 13 &&
          [0x41, 0x101, 0xD21].contains(p.command) &&
          p.field == offset &&
          p.space == space &&
          p.length == size &&
          p.payload.length == size;
    });
    final image = Mk300Protocol.parse(frame).payload;
    Mk20Diagnostics.decode(image);
    return image;
  }

  @override
  Future<String> probe() => _exclusive(() async {
        verified = false;
        final active = await _read(0, 1);
        await _read(targetSlot);
        verified = true;
        return Mk300Protocol.name(active);
      });
  static Uint8List bankWrite(int slot, List<int> image) {
    if (slot != targetSlot) {
      throw ArgumentError('Teste MK20 disponível somente no slot 150.');
    }
    Mk20Diagnostics.decode(image);
    return Mk300Protocol.build(9, 0x41 + 8 * size, slot * size, size, 0, image);
  }

  Uint8List buildImage(PresetData preset, String name, Uint8List original) {
    validateName(name);
    if (preset.device != 'MK20' || preset.catalogVersion != '0.4.0') {
      throw StateError(
          'Gere um preset MK20 atualizado com catálogo 0.4.0 antes de enviar.');
    }
    Mk20Diagnostics.decode(original);
    final image = Uint8List.fromList(original);
    image.fillRange(0, 20, 0);
    image.setRange(0, name.length, name.codeUnits);
    image.fillRange(40, 50, 0);
    const keys = {
      'noise_gate': 'GATE',
      'drive': 'DS',
      'amp': 'AMP',
      'cabinet': 'CAB',
      'eq': 'EQ',
      'modulation': 'MOD',
      'delay': 'DLY',
      'reverb': 'REV',
      'volume': 'VOL'
    };
    final selected = <int>[];
    for (final block in preset.effectChain) {
      final key = keys[block.effectType];
      final definition = (catalog['blocks'] as Map)[key];
      if (definition == null) {
        throw StateError('Bloco MK20 ainda não mapeado: ${block.effectType}.');
      }
      final id = definition['block_id'] as int;
      if (selected.contains(id)) throw StateError('Bloco MK20 duplicado.');
      selected.add(id);
      final models = definition['models'] as List;
      final model = models
          .where((m) =>
              '${m['id']}' == block.modelId && m['name'] == block.modelName)
          .firstOrNull;
      if (model == null) {
        throw StateError(
            'Modelo/ID fora do catálogo MK20: ${block.modelName}. Gere um preset atualizado.');
      }
      final specs = model['params'] as Map, knobs = model['knobs'] as List;
      if (block.parameters.keys.any((k) => !specs.containsKey(k))) {
        throw StateError('Parâmetro MK20 não mapeado.');
      }
      image[40 + id] = block.enabled ? 1 : 0;
      image[50 + id] = int.parse(block.modelId);
      // Every known control gets an explicit app value; never inherits destination tone.
      for (var k = 0; k < 12; k++) {
        var raw = 0;
        if (k < knobs.length) {
          final parameter = knobs[k] as String, spec = specs[parameter] as Map;
          final value = block.parameters[parameter] ??
              (spec['default'] as num?)?.toDouble();
          final minimum = (spec['min'] as num).toDouble(),
              maximum = (spec['max'] as num).toDouble();
          final step = (spec['step'] as num?)?.toDouble() ?? 1;
          if (value == null ||
              !value.isFinite ||
              value < minimum ||
              value > maximum ||
              ((value - minimum) / step - ((value - minimum) / step).round())
                      .abs() >
                  0.00001) {
            throw StateError('Controle MK20 inválido: $parameter.');
          }
          final scaled =
              value * ((spec['wire_scale'] as num?)?.toDouble() ?? 1);
          if ((scaled - scaled.round()).abs() > 0.00001 ||
              scaled < -32768 ||
              scaled > 32767) {
            throw StateError('Escala MK20 inválida: $parameter.');
          }
          raw = scaled.round();
        }
        ByteData.sublistView(image)
            .setInt16(60 + 24 * id + 2 * k, raw, Endian.little);
      }
    }
    if (!preset.effectChain.any((b) => b.effectType == 'amp' && b.enabled) ||
        !preset.effectChain
            .any((b) => b.effectType == 'cabinet' && b.enabled)) {
      throw StateError('AMP e CAB devem estar ligados.');
    }
    image.setRange(30, 40, [
      ...selected,
      ...List.generate(10, (i) => i).where((i) => !selected.contains(i))
    ]);
    final volume = preset.presetVolume ?? 40;
    if (volume < 0 || volume > 100) throw StateError('Volume MK20 inválido.');
    final data = ByteData.sublistView(image);
    data.setUint16(24, volume, Endian.little);
    if (preset.bpm != null) {
      if (!preset.bpm!.isFinite) throw StateError('BPM inválido.');
      data.setUint16(26, preset.bpm!.round().clamp(40, 250), Endian.little);
    }
    if (preset.centerPan) data.setInt16(28, 0, Endian.little);
    Mk20Diagnostics.decode(image);
    return image;
  }

  @override
  Future<PreparedTransfer> prepare(
          PresetData preset, String name, int slot, Directory directory) =>
      _exclusive(() async {
        if (!verified || slot != targetSlot) {
          throw StateError('Conecte a MK20 e escolha o slot 150.');
        }
        final original = await _read(slot);
        final image = buildImage(preset, name, original);
        await directory.create(recursive: true);
        final file = File(
            '${directory.path}/mk20-slot-150-${DateTime.now().microsecondsSinceEpoch}.json');
        await file.writeAsString(
            jsonEncode({
              'format': 'ai-tone-mk20-full-backup',
              'version': 1,
              'device': 'MK20',
              'device_connection': deviceLabel,
              'slot': 150,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'original_name': Mk300Protocol.name(original),
              'image_base64': base64Encode(original),
              'target_base64': base64Encode(image),
              'send_attempted': false,
              'restore_attempted': false,
              'preset': preset.toJson()
            }),
            flush: true);
        await _backup(file.path, original, image);
        await File('${directory.path}/mk20-latest-full.json').writeAsString(
            jsonEncode({'filename': file.uri.pathSegments.last}),
            flush: true);
        return PreparedTransfer(_identity, slot, name, file.path,
            Uint8List.fromList(original), image);
      });
  Future<Map<String, dynamic>> _backup(
      String path, Uint8List original, Uint8List image) async {
    final backup = Map<String, dynamic>.from(
        jsonDecode(await File(path).readAsString()) as Map);
    if (backup['format'] != 'ai-tone-mk20-full-backup' ||
        backup['version'] != 1 ||
        backup['device'] != 'MK20' ||
        backup['slot'] != 150 ||
        !Mk300Protocol.same(base64Decode(backup['image_base64']), original) ||
        !Mk300Protocol.same(base64Decode(backup['target_base64']), image)) {
      throw StateError('Backup MK20 inválido ou alterado.');
    }
    Mk20Diagnostics.decode(original);
    Mk20Diagnostics.decode(image);
    return backup;
  }

  Future<PreparedTransfer?> recover(Directory directory) =>
      _exclusive(() async {
        final pointer = File('${directory.path}/mk20-latest-full.json');
        if (!await pointer.exists()) return null;
        final filename =
            jsonDecode(await pointer.readAsString())['filename'] as String;
        if (!RegExp(r'^mk20-slot-150-[0-9]+\.json$').hasMatch(filename)) {
          throw StateError('Referência de backup inválida.');
        }
        final path = '${directory.path}/$filename',
            backup = jsonDecode(
                await File('${directory.path}/$filename').readAsString());
        final original = base64Decode(backup['image_base64']),
            image = base64Decode(backup['target_base64']);
        await _backup(path, original, image);
        return PreparedTransfer(_identity, targetSlot,
            Mk300Protocol.name(image), path, original, image)
          ..attempted = backup['send_attempted'] == true;
      });
  @override
  Future<void> send(PreparedTransfer transfer, {required bool confirmed}) =>
      _recorded(transfer, confirmed: confirmed, restore: false);
  Future<void> restore(PreparedTransfer transfer, {required bool confirmed}) =>
      _recorded(transfer, confirmed: confirmed, restore: true);
  Future<void> _recorded(PreparedTransfer t,
          {required bool confirmed, required bool restore}) =>
      _exclusive(() async {
        Object? error;
        lastReport = null;
        trace.clear();
        try {
          await _perform(t, confirmed: confirmed, restore: restore);
        } catch (e) {
          error = e;
          rethrow;
        } finally {
          if (confirmed) {
            try {
              final backup = await _backup(t.backupPath, t.original, t.image);
              lastReport = {
                'format': 'ai-tone-mk20-full-transfer',
                'version': 1,
                'device': 'MK20',
                'transport': 'usb',
                'slot': 150,
                'operation': restore ? 'restore' : 'send',
                'captured_at': DateTime.now().toUtc().toIso8601String(),
                'backup': backup,
                'trace': List<Map<String, dynamic>>.from(trace),
                'error': error?.toString()
              };
              await File(
                      '${File(t.backupPath).parent.path}/mk20-transfer-${DateTime.now().microsecondsSinceEpoch}.json')
                  .writeAsString(jsonEncode(lastReport), flush: true);
            } catch (_) {
              /* Hardware result remains authoritative; backup already exists. */
            }
          }
        }
      });

  Future<void> _perform(PreparedTransfer t,
      {required bool confirmed, required bool restore}) async {
    if (!confirmed ||
        !verified ||
        !identical(t.session, _identity) ||
        t.slot != targetSlot) {
      throw StateError('Operação MK20 sem confirmação ou de outra sessão.');
    }
    final backup = await _backup(t.backupPath, t.original, t.image);
    final current = await _read(t.slot);
    if (restore && Mk300Protocol.same(current, t.original)) return;
    final flag = restore ? 'restore_attempted' : 'send_attempted';
    if (backup[flag] != false || (!restore && t.attempted)) {
      throw StateError(
          'Esta gravação já foi tentada. Confira o pedal; não repetir automaticamente.');
    }
    if (!Mk300Protocol.same(current, restore ? t.image : t.original)) {
      throw StateError('Slot 150 mudou desde o backup. Operação cancelada.');
    }
    final target = restore ? t.original : t.image;
    // Rebuild from the archived preset, preventing mutable in-memory payload changes.
    if (!restore &&
        !Mk300Protocol.same(
            buildImage(
                PresetData.fromJson(
                    Map<String, dynamic>.from(backup['preset'])),
                t.name,
                t.original),
            target)) throw StateError('Preset preparado foi alterado.');
    backup[flag] = true;
    await File(t.backupPath).writeAsString(jsonEncode(backup), flush: true);
    if (!restore) t.attempted = true;
    await _request(bankWrite(t.slot, target), Mk300Protocol.isAck);
    await _request(Mk300Protocol.commit(), Mk300Protocol.isAck);
    await pause(const Duration(seconds: 3));
    for (var i = 0; i < 8; i++) {
      try {
        if (Mk300Protocol.same(await _read(t.slot), target)) return;
      } on TimeoutException {/* Only reads are retried. */}
      await pause(const Duration(milliseconds: 750));
    }
    throw StateError(
        'Gravação MK20 não confirmada por leitura. Backup preservado. Não repita o envio.');
  }

  @override
  Future<void> close() async {
    _closed = true;
    verified = false;
    await transport.close();
  }
}
