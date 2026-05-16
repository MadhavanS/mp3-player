import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track_item.dart';
import '../services/music_library_path_key.dart';

/// Subdirectory under the temp dir — one cached PNG per track (not a shared file).
const String _notifyArtCacheDirName = 'media_notify_art';

/// Android's notification pipeline decodes [MediaItem.artUri] via [BitmapFactory].
/// Rasterize embedded art to a modest PNG and cache by stable track id so skips and
/// metadata refresh do not overwrite another song's bitmap mid-playback.
Future<Uint8List?> _encodeCoverForPlatformNotification(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(
      raw,
      targetWidth: 512,
      targetHeight: 512,
    );
    final frame = await codec.getNextFrame();
    try {
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final out = byteData?.buffer.asUint8List();
      if (out == null || out.isEmpty) return null;
      return out;
    } finally {
      frame.image.dispose();
    }
  } catch (e, st) {
    debugPrint('notification cover rasterize failed: $e\n$st');
    return null;
  }
}

int _bytesFingerprint(Uint8List bytes) {
  if (bytes.length < 8) return bytes.hashCode;
  return Object.hash(
    bytes[0],
    bytes[1],
    bytes[bytes.length ~/ 2],
    bytes[bytes.length - 1],
    bytes.length,
  );
}

/// Stable cache file name per track path (and art revision when cover bytes change).
String _notificationArtCacheFileName(TrackItem track, int contentHash) {
  final fp = track.filePath?.trim() ?? '';
  final pathKey = fp.isNotEmpty ? canonicalMusicLibraryPathKey(fp) : '';
  final trackId = pathKey.isNotEmpty
      ? pathKey.hashCode.abs()
      : Object.hash(track.title, track.artist).abs();
  return 'art_${trackId}_$contentHash.png';
}

Future<Directory> _notificationArtCacheDirectory() async {
  final root = await getTemporaryDirectory();
  final dir = Directory(p.join(root.path, _notifyArtCacheDirName));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Returns a `file://` [Uri] for [audio_service] / [MediaItem.artUri] on Android.
Future<Uri?> uriForNotificationAlbumArt(TrackItem track) async {
  final bytes = track.albumArtBytes;
  if (bytes == null || bytes.isEmpty) return null;

  final forDisk = await _encodeCoverForPlatformNotification(bytes);
  if (forDisk == null || forDisk.isEmpty) return null;

  final contentHash = _bytesFingerprint(forDisk);
  final cacheDir = await _notificationArtCacheDirectory();
  final file = File(
    p.join(cacheDir.path, _notificationArtCacheFileName(track, contentHash)),
  );

  if (await file.exists()) {
    try {
      if (await file.length() > 0) {
        return Uri.file(file.absolute.path);
      }
    } catch (_) {}
  }

  await file.writeAsBytes(forDisk, flush: true);
  return Uri.file(file.absolute.path);
}
