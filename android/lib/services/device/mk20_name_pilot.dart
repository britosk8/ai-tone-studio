import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'device_transport.dart';
import 'mk300_protocol.dart';
import 'mk20_diagnostics.dart';

/// Isolated MK20 USB pilot: only slot 150 and only its name can change.
/// Envelope derived from M-EFCS makeWritePacket; no MK300 bank-write call.
class Mk20NamePilot {
  static const slot = 150, size = 412, field = (slot - 1) * size;
  static const testName = 'AI TONE MK20 TEST';
  final DeviceTransport transport;
  final Future<void> Function(Duration) pause;
  final Duration timeout;
  final List<Map<String, dynamic>> trace = [];
  bool _busy = false;
  Mk20NamePilot(this.transport,
      {Future<void> Function(Duration)? pause,
      this.timeout = const Duration(seconds: 5)})
      : pause = pause ?? Future<void>.delayed;

  static Uint8List renamed(List<int> original) {
    Mk20Diagnostics.decode(original);
    final output = Uint8List.fromList(original);
    output.fillRange(0, 20, 0);
    output.setRange(0, testName.length, testName.codeUnits);
    return output;
  }

  static Uint8List bankWrite(List<int> image) {
    Mk20Diagnostics.decode(image);
    // The raw M-EFCS packet length is payload.length + 8. After bit packing,
    // this becomes CMD=0x41 + 8*length, including the low digits for 412 bytes.
    return Mk300Protocol.build(9, 0x41 + 8 * size, field, size, 0, image);
  }

  static Map<String, dynamic> validateBackup(Map<String, dynamic> backup) {
    if (backup['format'] != 'ai-tone-mk20-name-backup' ||
        backup['version'] != 1 ||
        backup['slot'] != slot) {
      throw const FormatException(
          'Backup não pertence ao teste do slot 150 da MK20.');
    }
    final original = base64Decode(backup['original_base64'] as String);
    final named = base64Decode(backup['named_base64'] as String);
    Mk20Diagnostics.decode(original);
    if (!Mk300Protocol.same(renamed(original), named) ||
        Mk300Protocol.same(original, named)) {
      throw const FormatException('Backup inválido ou alteração fora do nome.');
    }
    return backup;
  }

  static Future<Map<String, dynamic>> load(File file) async => validateBackup(
      Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map));

  void _record(String direction, Uint8List bytes) {
    if (trace.length < 96) {
      trace.add({'direction': direction, 'bytes_base64': base64Encode(bytes)});
    }
  }

  Future<Uint8List> _exchange(
      Uint8List command, bool Function(Uint8List) matches) async {
    final response = Completer<Uint8List>();
    final subscription = transport.frames.listen((bytes) {
      _record('rx', bytes);
      try {
        if (!response.isCompleted && matches(bytes)) response.complete(bytes);
      } on FormatException {
        /* Never authorizes writing on malformed replies. */
      }
    }, onError: (Object error) {
      if (!response.isCompleted) response.completeError(error);
    });
    final timer = Timer(timeout, () {
      if (!response.isCompleted) {
        response.completeError(TimeoutException('MK20 não respondeu.'));
      }
    });
    final pending = response.future;
    _record('tx', command);
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

  Future<Uint8List> _read([int space = 0]) async {
    final offset = space == 1 ? 0 : field;
    final response =
        await _exchange(Mk300Protocol.read(offset, size, space), (bytes) {
      final frame = Mk300Protocol.parse(bytes);
      return frame.cls == 13 &&
          [0x41, 0x101, 0xD21].contains(frame.command) &&
          frame.space == space &&
          frame.field == offset &&
          frame.length == size &&
          frame.payload.length == size;
    });
    final image = Mk300Protocol.parse(response).payload;
    Mk20Diagnostics.decode(image);
    return image;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('Aguarde a operação em andamento.');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<File> prepare(Directory directory, {required String deviceName}) =>
      _exclusive(() async {
        await _read(1);
        final original = await _read();
        final named = renamed(original);
        if (Mk300Protocol.same(original, named)) {
          throw StateError(
              'O slot já tem o nome do teste. Recupere e restaure o backup anterior.');
        }
        await directory.create(recursive: true);
        final file = File(
            '${directory.path}/mk20-name-${DateTime.now().microsecondsSinceEpoch}.json');
        await file.writeAsString(
            jsonEncode({
              'format': 'ai-tone-mk20-name-backup',
              'version': 1,
              'slot': slot,
              'device_name': deviceName,
              'captured_at': DateTime.now().toUtc().toIso8601String(),
              'original_base64': base64Encode(original),
              'named_base64': base64Encode(named),
              'rename_attempted': false,
              'restore_attempted': false,
              'restore_verified': false,
            }),
            flush: true);
        final saved = await load(file);
        if (!Mk300Protocol.same(
            base64Decode(saved['original_base64']), original)) {
          throw StateError('Falha ao conferir backup salvo.');
        }
        await File('${directory.path}/latest.json').writeAsString(
            jsonEncode({'filename': file.uri.pathSegments.last}),
            flush: true);
        return file;
      });

  /// Every operation is one-shot. Lost ACK/timeout never repeats bank-write.
  /// Returns an archived report on success or failure; never fabricates success.
  Future<Map<String, dynamic>> perform(File file,
          {required bool restore, required bool confirmed}) =>
      _exclusive(() async {
        if (!confirmed) throw StateError('Confirme a alteração do slot 150.');
        final backup = await load(file);
        final attempt = restore ? 'restore_attempted' : 'rename_attempted';
        if (backup[attempt] == true && !restore) {
          throw StateError(
              'Esta operação já foi tentada. Confira a leitura; não há repetição automática.');
        }
        if (restore && backup['rename_attempted'] != true) {
          throw StateError('Nenhuma renomeação foi tentada neste backup.');
        }
        final original = base64Decode(backup['original_base64']);
        final named = base64Decode(backup['named_base64']);
        final target = restore ? original : named;
        final expected = restore ? named : original;
        trace.clear();
        String status = 'not_attempted';
        String? error;
        try {
          await _read(1);
          final current = await _read();
          if (restore && Mk300Protocol.same(current, original)) {
            status = 'already_original';
            backup['restore_verified'] = true;
            await file.writeAsString(jsonEncode(backup), flush: true);
          } else {
            if (backup[attempt] == true) {
              throw StateError(
                  'Restauração já tentada. Apenas leitura; não repetiremos a escrita.');
            }
            if (!Mk300Protocol.same(current, expected)) {
              throw StateError(
                  'Slot 150 mudou desde o backup. Operação cancelada.');
            }
            // Persist before the first write, including across app restarts.
            backup[attempt] = true;
            await file.writeAsString(jsonEncode(backup), flush: true);
            if (!Mk300Protocol.same(
                base64Decode((await load(file))['original_base64']),
                original)) {
              throw StateError('Backup não corresponde à imagem original.');
            }
            status = 'unconfirmed';
            await _exchange(bankWrite(target), Mk300Protocol.isAck);
            await _exchange(Mk300Protocol.commit(), Mk300Protocol.isAck);
            await pause(const Duration(seconds: 3));
            for (var i = 0; i < 5; i++) {
              try {
                if (Mk300Protocol.same(await _read(), target)) {
                  status = 'confirmed';
                  if (restore) {
                    backup['restore_verified'] = true;
                    await file.writeAsString(jsonEncode(backup), flush: true);
                  }
                  break;
                }
              } on TimeoutException {/* Read retries only. */}
              await pause(const Duration(milliseconds: 750));
            }
            if (status != 'confirmed') {
              throw StateError(
                  'Gravação não confirmada por leitura. Preserve o backup e não repita o envio.');
            }
          }
        } catch (failure) {
          error = '$failure';
        }
        final report = <String, dynamic>{
          'format': 'ai-tone-mk20-name-pilot',
          'version': 1,
          'device': 'MK20',
          'transport': 'usb',
          'slot': slot,
          'operation': restore ? 'restore' : 'rename',
          'captured_at': DateTime.now().toUtc().toIso8601String(),
          'status': status,
          'error': error,
          'backup': backup,
          'trace': List.of(trace),
        };
        final reportFile = File(
            '${file.parent.path}/result-${DateTime.now().microsecondsSinceEpoch}.json');
        await reportFile.writeAsString(jsonEncode(report), flush: true);
        await File('${file.parent.path}/last_result.json')
            .writeAsString(jsonEncode(report), flush: true);
        return report;
      });
}
