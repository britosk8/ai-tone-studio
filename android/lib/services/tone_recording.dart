import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class ToneRecording {
  static const channel = MethodChannel('ai_tone/recording');
  Future<List<Map<String, dynamic>>> inputs() async =>
      (await channel.invokeListMethod<dynamic>('inputs') ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<Map<String, dynamic>> start(String kind, int id, int seconds) async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw StateError(
          'Permissão para gravar áudio negada. Autorize nas configurações do Android.');
    }
    return Map<String, dynamic>.from(await channel.invokeMethod<Map>(
            'start', {'kind': kind, 'id': id, 'seconds': seconds}) ??
        {});
  }

  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await channel.invokeMethod<Map>('status') ?? {});
  Future<String> stop() async =>
      await channel
          .invokeMethod<String>('stop')
          .timeout(const Duration(seconds: 5)) ??
      (throw StateError('Gravação indisponível'));
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}
