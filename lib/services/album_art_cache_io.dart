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

/// Disk cache dimensions written by [primeAlbumArtDiskCache] (default 512).
const List<int> kPathAlbumArtDiskDimensions = [512, 256, 192, 128];

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

/// Synchronous path art: any cached dimension (no resize; UI scales).
Uint8List? cachedAlbumArtForPathAnyDimensionSync(
  String filePath, {
  int targetDimension = 512,
}) {
  final path = filePath.trim();
  if (path.isEmpty) return null;
  for (final dim in kPathAlbumArtDiskDimensions) {
    final bytes = cachedAlbumArtForPathSync(path, maxDimension: dim);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }
  return null;
}

/// Path-keyed disk art: tries [kPathAlbumArtDiskDimensions] largest-first, then
/// resizes to [targetDimension] when the on-disk size differs (e.g. 512 cached, list asks 192).
Future<Uint8List?> cachedAlbumArtForPathAnyDimension(
  String filePath, {
  int targetDimension = 512,
}) async {
  final path = filePath.trim();
  if (path.isEmpty) return null;
  final target = targetDimension.clamp(96, 512).toInt();

  for (final dim in kPathAlbumArtDiskDimensions) {
    final bytes = await cachedAlbumArtForPath(path, maxDimension: dim);
    if (bytes == null || bytes.isEmpty) continue;
    if (dim == target) return bytes;
    final resized = await _resizeToPng(bytes, target);
    return (resized == null || resized.isEmpty) ? bytes : resized;
  }
  return null;
}

Future<bool> hasAlbumArtDiskCacheAnyDimension(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return false;
  for (final dim in kPathAlbumArtDiskDimensions) {
    if (await hasAlbumArtDiskCache(path, maxDimension: dim)) return true;
  }
  return false;
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

/// Path keys (canonical) that have a non-empty path-keyed disk cache file.
///
/// Scans the cache directory once, then matches [filePaths] by
/// `canonicalMusicLibraryPathKey(path).hashCode.abs()` (any cached dimension).
Future<Set<String>> pathKeysWithDiskAlbumArt(
  Iterable<String> filePaths, {
  int maxDimension = 512,
}) async {
  final dir = await _albumArtCacheDir();
  final cachedHashes = <int>{};
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.png')) continue;
      final stem = name.substring(0, name.length - 4);
      final match = RegExp(r'^path_(\d+)_\d+$').firstMatch(stem);
      if (match == null) continue;
      try {
        if (entity.lengthSync() > 0) {
          cachedHashes.add(int.parse(match.group(1)!));
        }
      } catch (_) {}
    }
  } catch (e, st) {
    debugPrint('pathKeysWithDiskAlbumArt list: $e\n$st');
    return const <String>{};
  }

  final out = <String>{};
  for (final raw in filePaths) {
    final path = raw.trim();
    if (path.isEmpty) continue;
    final pathKey = canonicalMusicLibraryPathKey(path);
    if (pathKey.isEmpty) continue;
    if (cachedHashes.contains(pathKey.hashCode.abs())) {
      out.add(pathKey);
    }
  }
  return out;
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

