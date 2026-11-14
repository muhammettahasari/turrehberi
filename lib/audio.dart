import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Yerel ses: 16 kHz, mono, 16 bit PCM; 20 ms'lik (640 bayt) parçalar.
/// Mikrofon ve çalma Android tarafında (AudioEngine.kt).
class NativeAudio {
  static const _m = MethodChannel('turses/audio');
  static const _mic = EventChannel('turses/mic');

  /// Mikrofon parçaları. Önce bu akışa abone olun, sonra [startCapture].
  static Stream<Uint8List> micFrames() =>
      _mic.receiveBroadcastStream().where((e) => e is Uint8List).cast<Uint8List>();

  static Future<bool> startCapture() async {
    try {
      return await _m.invokeMethod<bool>('startCapture') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopCapture() async {
    try {
      await _m.invokeMethod('stopCapture');
    } catch (_) {}
  }

  static Future<bool> startPlayback() async {
    try {
      return await _m.invokeMethod<bool>('startPlayback') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopPlayback() async {
    try {
      await _m.invokeMethod('stopPlayback');
    } catch (_) {}
  }

  static void play(Uint8List frame) {
    _m.invokeMethod('play', frame).catchError((_) => null);
  }

  /// Parçanın ses seviyesi, 0..1 (gösterge için).
  static double level(Uint8List frame) {
    final d = ByteData.sublistView(frame);
    var peak = 0;
    for (var i = 0; i + 1 < frame.length; i += 8) {
      final v = d.getInt16(i, Endian.little).abs();
      if (v > peak) peak = v;
    }
    return (peak / 32768.0).clamp(0.0, 1.0);
  }
}
