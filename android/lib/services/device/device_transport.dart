import 'dart:async';
import 'package:flutter/services.dart';
import 'mk300_protocol.dart';

abstract class DeviceTransport {
  Stream<Uint8List> get frames;
  Future<void> send(Uint8List frame);
  Future<void> close();
}

class NativeDeviceTransport implements DeviceTransport {
  static const channel = MethodChannel('ai_tone/device');
  static const events = EventChannel('ai_tone/device_events');
  static Stream<dynamic>? _events;
  final String kind;
  final String deviceId;
  final _frames = StreamController<Uint8List>.broadcast();
  late final PedalFramer _framer;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  NativeDeviceTransport(this.kind, this.deviceId) {
    _framer = PedalFramer(rawBle: kind == 'ble');
  }
  @override
  Stream<Uint8List> get frames => _frames.stream;
  static Future<List<Map<String, dynamic>>> devices(String kind) async {
    final values = await channel
            .invokeListMethod<dynamic>(kind == 'usb' ? 'listUsb' : 'scanBle') ??
        [];
    return values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  }

  Future<Map<String, dynamic>> connect() async {
    _events ??= events.receiveBroadcastStream();
    _subscription = _events!.listen((dynamic event) {
      if (_closed || event is! Map) return;
      if (event['type'] == 'data') {
        for (final frame
            in _framer.add(List<int>.from(event['bytes'] as List))) {
          _frames.add(frame);
        }
      } else if (event['type'] == 'disconnected') {
        _frames.addError(StateError(
            'Conexão com a pedaleira encerrada. Nenhum envio pode ser confirmado.'));
      }
    }, onError: (Object error) => _frames.addError(error));
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('connect',
          {'kind': kind, 'id': deviceId}).timeout(const Duration(seconds: 15));
      return result ?? {};
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<void> send(Uint8List frame) async {
    if (_closed) throw StateError('Transporte fechado');
    final data = kind == 'ble'
        ? Mk300Protocol.unpack7(frame.sublist(1, frame.length - 1))
        : frame;
    await channel.invokeMethod<void>(
        'send', {'bytes': data}).timeout(const Duration(seconds: 8));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    try {
      await channel.invokeMethod<void>('disconnect');
    } finally {
      await _frames.close();
    }
  }
}
