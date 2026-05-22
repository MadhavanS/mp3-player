import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android task lifecycle helpers (remove from Recents on Quit, etc.).
class AndroidAppTaskBridge {
  static const _channel = MethodChannel('com.example.mp3_player/app_task');

  static Future<void> finishAndRemoveTask() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('finishAndRemoveTask');
    } catch (_) {}
  }
}
