import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track_item.dart';
import 'music_library_path_key.dart';

const int _maxMemoryEntries = 80;
const String _cacheDirName = 'album_art_cache';

final _memory = <String, Uint8List>{};
final _inFlight = <String, Future<Uint8List?>>{};
Directory? _cacheDir;

Uint8List? cachedAlbumArtSync(TrackItem track, {int maxDimension = 512}) {
  final raw = track.albumArtBytes;
  if (raw == null || raw.isEmpty) return null;
  return _memory[_cacheKey(track, raw, maxDimension)];
}

Future<Uint8List?> cachedAlbumArt(
  TrackItem track, {
  int maxDimension = 512,
}) async {
  final raw = track.albumArtBytes;
  if (raw == null || raw.isEmpty) return null;

  final normalizedMax = maxDimension.clamp(96, 512).toInt();
  final key = _cacheKey(track, raw, normalizedMax);
  final cached = _memory[key];
  if (cached != null) {
    _touchMemory(key, cached);
    return cached;
  }

  final existing = _inFlight[key];
  if (existing != null) return existing;

  final future = _loadOrCreate(track, raw, normalizedMax, key);
  _inFlight[key] = future;
  try {
    return await future;
  } finally {
    _inFlight.remove(key);
  }
}

void evictCachedAlbumArt(TrackItem track) {
  final raw = track.albumArtBytes;
  if (raw == null || raw.isEmpty) return;
  final prefix = _trackStableId(track);
  _memory.removeWhere((key, _) => key.startsWith(prefix));
}

String _pathDiskKey(String filePath, int maxDimension) {
  final pathKey = canonicalMusicLibraryPathKey(filePath.trim());
  if (pathKey.isEmpty) return '';
  return 'path_${pathKey.hashCode.abs()}_$maxDimension';
}

Uint8List? cachedAlbumArtForPathSync(
  String filePath, {
  int maxDimension = 512,
}) {
  final key = _pathDiskKey(filePath, maxDimension.clamp(96, 512).toInt());
  if (key.isEmpty) return null;
  return _memory[key];
}

Future<Uint8List?> cachedAlbumArtForPath(
  String filePath, {
  int maxDimension = 512,
}) async {
  final normalizedMax = maxDimension.clamp(96, 512).toInt();
  final key = _pathDiskKey(filePath, normalizedMax);
  if (key.isEmpty) return null;

  final cached = _memory[key];
  if (cached != null) {
    _touchMemory(key, cached);
    return cached;
  }

  final existing = _inFlight[key];
  if (existing != null) return existing;

  final future = _loadPathDiskCache(filePath, normalizedMax, key);
  _inFlight[key] = future;
  try {
    return await future;
  } finally {
    _inFlight.remove(key);
  }
}

Future<bool> hasAlbumArtDiskCache(
  String filePath, {
  int maxDimension = 512,
}) async {
  final key = _pathDiskKey(filePath, maxDimension.clamp(96, 512).toInt());
  if (key.isEmpty) return false;
  if (_memory.containsKey(key)) return true;
  final file = await _cacheFile(key);
  return file.existsSync() && file.lengthSync() > 0;
}

Future<void> primeAlbumArtDiskCache(
  String filePath,
  Uint8List raw, {
  int maxDimension = 512,
}) async {
  if (filePath.trim().isEmpty || raw.isEmpty) return;
  final normalizedMax = maxDimension.clamp(96, 512).toInt();
  final key = _pathDiskKey(filePath, normalizedMax);
  if (key.isEmpty) return;

  final resized = await _resizeToPng(raw, normalizedMax);
  final bytes = (resized == null || resized.isEmpty) ? raw : resized;
  try {
    final file = await _cacheFile(key);
    await file.writeAsBytes(bytes, flush: false);
  } catch (e, st) {
    debugPrint('primeAlbumArtDiskCache write failed: $e\n$st');
  }
  _putMemory(key, bytes);
}

Future<Uint8List?> _loadPathDiskCache(
  String filePath,
  int maxDimension,
  String key,
) async {
  final file = await _cacheFile(key);
  try {
    if (await file.exists() && await file.length() > 0) {
      final bytes = await file.readAsBytes();
      _putMemory(key, bytes);
      return bytes;
    }
  } catch (_) {}
  return null;
}

/// Warms path-keyed disk/memory cache for the first screen of a library list.
Future<void> prewarmPathAlbumArtForPaths(
  Iterable<String> filePaths, {
  int maxCount = 15,
  int maxDimension = 192,
}) async {
  final paths = filePaths
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .take(maxCount)
      .toList(growable: false);
  if (paths.isEmpty) return;

  await Future.wait(
    paths.map(
      (path) => cachedAlbumArtForPath(path, maxDimension: maxDimension),
    ),
    eagerError: false,
  );
}

void prewarmAlbumArtCache(
  Iterable<TrackItem> tracks, {
  int maxCount = 50,
  int maxDimension = 512,
}) {
  final selected = tracks
      .where((t) => t.albumArtBytes != null && t.albumArtBytes!.isNotEmpty)
      .take(maxCount)
      .toList(growable: false);
  if (selected.isEmpty) return;

  unawaited(() async {
    for (final track in selected) {
      try {
        await cachedAlbumArt(track, maxDimension: maxDimension);
      } catch (e, st) {
        debugPrint('prewarmAlbumArtCache: $e\n$st');
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }());
}

Future<Uint8List?> _loadOrCreate(
  TrackItem track,
  Uint8List raw,
  int maxDimension,
  String key,
) async {
  final file = await _cacheFile(key);
  try {
    if (await file.exists() && await file.length() > 0) {
      final bytes = await file.readAsBytes();
      _putMemory(key, bytes);
      return bytes;
    }
  } catch (_) {}

  final resized = await _resizeToPng(raw, maxDimension);
  if (resized == null || resized.isEmpty) return raw;

  try {
    await file.writeAsBytes(resized, flush: false);
  } catch (e, st) {
    debugPrint('album art cache write failed: $e\n$st');
  }
  _putMemory(key, resized);
  return resized;
}

Future<Uint8List?> _resizeToPng(Uint8List raw, int maxDimension) async {
  try {
    final codec = await ui.instantiateImageCodec(
      raw,
      targetWidth: maxDimension,
      targetHeight: maxDimension,
    );
    final frame = await codec.getNextFrame();
    try {
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } catch (e, st) {
    debugPrint('album art resize failed: $e\n$st');
    return null;
  }
}

Future<File> _cacheFile(String key) async {
  final dir = await _albumArtCacheDir();
  return File(p.join(dir.path, '$key.png'));
}

Future<Directory> _albumArtCacheDir() async {
  final existing = _cacheDir;
  if (existing != null) return existing;
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, _cacheDirName));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _cacheDir = dir;
  return dir;
}

String _cacheKey(TrackItem track, Uint8List raw, int maxDimension) {
  return '${_trackStableId(track)}_${_bytesFingerprint(raw)}_$maxDimension';
}

String _trackStableId(TrackItem track) {
  final fp = track.filePath?.trim() ?? '';
  final pathKey = fp.isNotEmpty ? canonicalMusicLibraryPathKey(fp) : '';
  final source = pathKey.isNotEmpty ? pathKey : '${track.title}|${track.artist}';
  return source.hashCode.abs().toString();
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

void _putMemory(String key, Uint8List bytes) {
  _memory.remove(key);
  _memory[key] = bytes;
  while (_memory.length > _maxMemoryEntries) {
    _memory.remove(_memory.keys.first);
  }
}

void _touchMemory(String key, Uint8List bytes) {
  _memory.remove(key);
  _memory[key] = bytes;
}

