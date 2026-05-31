import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../services/music_library_path_key.dart';
import '../services/notification_art_theme_bridge.dart';
import '../theme/track_art_placeholder.dart';

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

int _placeholderFingerprint(TrackArtPlaceholderStyle style, TrackItem track) {
  final c0 = track.artColors.isNotEmpty ? track.artColors.first.toARGB32() : 0;
  final c1 = track.artColors.length > 1 ? track.artColors[1].toARGB32() : c0;
  return Object.hash(
    'placeholder',
    style.index,
    c0,
    c1,
    NotificationArtThemeBridge.palette().index,
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

/// Deletes cached notification/widget art PNGs for [filePath] (all content hashes).
Future<void> evictNotificationArtCacheForPath(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return;
  final pathKey = canonicalMusicLibraryPathKey(path);
  if (pathKey.isEmpty) return;
  final trackId = pathKey.hashCode.abs();
  final prefix = 'art_${trackId}_';

  try {
    final dir = await _notificationArtCacheDirectory();
    final toDelete = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(prefix) && name.endsWith('.png')) {
        toDelete.add(entity);
      }
    }
    await Future.wait(
      toDelete.map((f) async {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }),
      eagerError: false,
    );
  } catch (e, st) {
    debugPrint('evictNotificationArtCacheForPath($path): $e\n$st');
  }
}

Future<Directory> _notificationArtCacheDirectory() async {
  final root = await getTemporaryDirectory();
  final dir = Directory(p.join(root.path, _notifyArtCacheDirName));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<void> clearAllNotificationArtCache() async {
  try {
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, _notifyArtCacheDirName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e, st) {
    debugPrint('clearAllNotificationArtCache: $e\n$st');
  }
}

/// Returns a `file://` [Uri] for [audio_service] / [MediaItem.artUri] on Android.
///
/// Uses embedded cover when present; otherwise a theme-aligned placeholder PNG
/// (same rules as [TrackAlbumArt] and the home-screen widget).
Future<Uri?> uriForNotificationAlbumArt(TrackItem track) async {
  var bytes = track.albumArtBytes;
  if (bytes == null || bytes.isEmpty) {
    final path = track.filePath?.trim() ?? '';
    if (path.isNotEmpty) {
      bytes = await cachedAlbumArtForPathAnyDimension(
        path,
        targetDimension: 512,
      );
    }
  }

  final Uint8List? forDisk;
  final int contentHash;

  if (bytes != null && bytes.isNotEmpty) {
    forDisk = await _encodeCoverForPlatformNotification(bytes);
    if (forDisk == null || forDisk.isEmpty) return null;
    contentHash = _bytesFingerprint(forDisk);
  } else {
    final style = trackArtPlaceholderStyleFor(
      NotificationArtThemeBridge.palette(),
    );
    forDisk = await rasterizeTrackArtPlaceholder(
      style: style,
      artColors: track.artColors,
    );
    if (forDisk == null || forDisk.isEmpty) return null;
    contentHash = _placeholderFingerprint(style, track);
  }

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
