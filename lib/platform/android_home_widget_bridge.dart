import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Writes widget prefs on Android and refreshes [Mp3PlayerAppWidget].
class AndroidHomeWidgetBridge {
  static const _channel = MethodChannel('com.example.mp3_player/widget');

  static Future<void> sync({
    required bool hasTrack,
    required String title,
    required String artist,
    required String album,
    required String? artFilePath,
    /// When there is no file art: `daisy`, `silver`, or `gradient` (matches [TrackAlbumArt]).
    required String artPlaceholderStyle,
    required int artPlaceholderColor0Argb,
    required int artPlaceholderColor1Argb,
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
      'album': album,
      'art_path': artFilePath ?? '',
      'art_placeholder_style': artPlaceholderStyle,
      'art_placeholder_c0': artPlaceholderColor0Argb,
      'art_placeholder_c1': artPlaceholderColor1Argb,
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
