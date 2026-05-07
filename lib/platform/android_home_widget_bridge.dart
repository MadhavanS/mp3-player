import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Writes widget prefs on Android and refreshes [Mp3PlayerAppWidget].
class AndroidHomeWidgetBridge {
  static const _channel = MethodChannel('com.example.mp3_player/widget');

  static Future<void> sync({
    required bool hasTrack,
    required String title,
    required String artist,
    required String? artFilePath,
    required bool playing,
    required int positionMs,
    required int durationMs,
    required bool canSkipNext,
    required bool isDarkTheme,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('sync', <String, dynamic>{
      'has_track': hasTrack,
      'title': title,
      'artist': artist,
      'art_path': artFilePath ?? '',
      'playing': playing,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'can_skip_next': canSkipNext,
      'is_dark': isDarkTheme,
    });
  }

  static Future<void> syncPlaybackProgress({
    required bool playing,
    required int positionMs,
    required int durationMs,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('syncPlaybackProgress', <String, dynamic>{
      'playing': playing,
      'position_ms': positionMs,
      'duration_ms': durationMs,
    });
  }
}
