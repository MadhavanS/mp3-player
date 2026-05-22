import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads a pending home-widget transport action when AudioService was not running.
class AndroidWidgetLaunchBridge {
  static const _channel = MethodChannel('com.example.mp3_player/widget_launch');

  static const actionPlay = 'play';
  static const actionSkipNext = 'skip_next';
  static const actionSkipPrevious = 'skip_previous';

  static Future<String?> consumeLaunchAction() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final action = await _channel.invokeMethod<String>('consumeLaunchAction');
      final trimmed = action?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    } catch (_) {
      return null;
    }
  }
}
