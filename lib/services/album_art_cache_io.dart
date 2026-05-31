import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track_item.dart';
import 'album_art_dimensions.dart';
import 'music_library_path_key.dart';

const int _maxMemoryEntries = 40;
const String _cacheDirName = 'album_art_cache';

final _memory = <String, Uint8List>{};
final _inFlight = <String, Future<Uint8List?>>{};
final _inFlightByPathKey = <String, Future<Uint8List?>>{};
Directory? _cacheDir;

/// Drops path-keyed decoded entries from [_memory] (disk files unchanged).
///
/// Called when bytes are promoted into [LibraryCatalog] hot LRU so the same
/// cover is not held in two RAM caches.
void evictPathAlbumArtMemory(String filePath) {
  final path = filePath.trim();
  if (path.isEmpty) return;
  final pathKey = canonicalMusicLibraryPathKey(path);
  if (pathKey.isEmpty) return;
  final prefix = 'path_${pathKey.hashCode.abs()}_';
  _memory.removeWhere((key, _) => key.startsWith(prefix));
}

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

  final normalizedMax = clampAlbumArtDimension(maxDimension);
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

/// Removes path-keyed list thumbnails (all dimensions) and in-memory entries.
Future<void> evictPathAlbumArtCaches(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return;
  final pathKey = canonicalMusicLibraryPathKey(path);
  if (pathKey.isEmpty) return;
  final hash = pathKey.hashCode.abs();
  final diskPrefix = 'path_${hash}_';
  _memory.removeWhere((key, _) => key.startsWith(diskPrefix));

  try {
    final dir = await _albumArtCacheDir();
    final toDelete = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(diskPrefix) && name.endsWith('.png')) {
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
    debugPrint('evictPathAlbumArtCaches($path): $e\n$st');
  }
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
  final key = _pathDiskKey(filePath, clampAlbumArtDimension(maxDimension));
  if (key.isEmpty) return null;
  return _memory[key];
}

/// Synchronous path art: best cached dimension for [targetDimension] (no resize).
Uint8List? cachedAlbumArtForPathAnyDimensionSync(
  String filePath, {
  int targetDimension = 512,
}) {
  final path = filePath.trim();
  if (path.isEmpty) return null;
  final target = clampAlbumArtDimension(targetDimension);

  Uint8List? largest;
  var largestDim = 0;

  for (final dim in kPathAlbumArtDiskDimensions) {
    final bytes = cachedAlbumArtForPathSync(path, maxDimension: dim);
    if (bytes == null || bytes.isEmpty) continue;
    if (dim >= target) return bytes;
    if (dim > largestDim) {
      largestDim = dim;
      largest = bytes;
    }
  }
  return largest;
}

/// Path-keyed disk art: largest cached/on-disk bytes, then resize to [targetDimension].
Future<Uint8List?> cachedAlbumArtForPathAnyDimension(
  String filePath, {
  int targetDimension = 512,
}) async {
  final path = filePath.trim();
  if (path.isEmpty) return null;
  final target = clampAlbumArtDimension(targetDimension);
  final largest = await _loadLargestPathArtBytes(path);
  if (largest == null || largest.isEmpty) return null;
  return _bytesAtTargetDimension(path, largest, target: target);
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
  final normalizedMax = clampAlbumArtDimension(maxDimension);
  final key = _pathDiskKey(filePath, normalizedMax);
  if (key.isEmpty) return null;

  final cached = _memory[key];
  if (cached != null) {
    _touchMemory(key, cached);
    return cached;
  }

  final largest = await _loadLargestPathArtBytes(filePath);
  if (largest == null || largest.isEmpty) return null;
  return _bytesAtTargetDimension(
    filePath,
    largest,
    target: normalizedMax,
    cacheKey: key,
  );
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
  final key = _pathDiskKey(filePath, clampAlbumArtDimension(maxDimension));
  if (key.isEmpty) return false;
  if (_memory.containsKey(key)) return true;
  final file = await _cacheFile(key);
  return file.existsSync() && file.lengthSync() > 0;
}

Future<void> primeAlbumArtDiskCache(
  String filePath,
  Uint8List raw, {
  int maxDimension = kAlbumArtPrimeDimension,
}) async {
  if (filePath.trim().isEmpty || raw.isEmpty) return;
  // Default: write Now Playing + notification + list sizes in parallel.
  final sizes = maxDimension == kAlbumArtPrimeDimension
      ? kAlbumArtPrimeDiskDimensions
      : [clampAlbumArtDimension(maxDimension)];
  await Future.wait(
    sizes.map((dim) => _writePathArtAtSize(filePath, raw, dim)),
    eagerError: false,
  );
}

Future<void> _writePathArtAtSize(
  String filePath,
  Uint8List raw,
  int targetSize,
) async {
  final normalized = clampAlbumArtDimension(targetSize);
  final key = _pathDiskKey(filePath, normalized);
  if (key.isEmpty) return;

  try {
    final sourceMax = await _decodeSourceMaxSide(raw);
    final effective = sourceMax > 0
        ? math.min(sourceMax, normalized)
        : normalized;
    if (sourceMax > 0 && sourceMax < normalized && kDebugMode) {
      debugPrint(
        '[artCache] source ${sourceMax}px < target ${normalized}px '
        '— writing at ${effective}px (no upscale)',
      );
    }

    final resized = await _resizeToPng(raw, normalized);
    final bytes = (resized == null || resized.isEmpty) ? raw : resized;
    final file = await _cacheFile(key);
    await file.writeAsBytes(bytes, flush: false);
    _putMemory(key, bytes);
    if (kDebugMode) {
      debugPrint('[artCache] wrote ${normalized}px for $key');
    }
  } catch (e, st) {
    debugPrint('[artCache] write ${normalized}px failed: $e\n$st');
  }
}

Future<int> _decodeSourceMaxSide(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    try {
      return math.max(frame.image.width, frame.image.height);
    } finally {
      frame.image.dispose();
    }
  } catch (_) {
    return 0;
  }
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

/// Largest path art in RAM or on disk; one in-flight load per canonical path key.
Future<Uint8List?> _loadLargestPathArtBytes(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return null;
  final pathKey = canonicalMusicLibraryPathKey(path);
  if (pathKey.isEmpty) return null;

  for (final dim in kPathAlbumArtDiskDimensions) {
    final bytes = cachedAlbumArtForPathSync(path, maxDimension: dim);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }

  final existing = _inFlightByPathKey[pathKey];
  if (existing != null) return existing;

  final future = _loadLargestPathArtFromDisk(path);
  _inFlightByPathKey[pathKey] = future;
  try {
    return await future;
  } finally {
    _inFlightByPathKey.remove(pathKey);
  }
}

Future<Uint8List?> _loadLargestPathArtFromDisk(String filePath) async {
  final path = filePath.trim();
  for (final dim in kPathAlbumArtDiskDimensions) {
    final key = _pathDiskKey(path, dim);
    if (key.isEmpty) continue;
    final bytes = await _loadPathDiskCache(path, dim, key);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }
  return null;
}

int? _memoryDimensionForPath(String filePath) {
  final path = filePath.trim();
  for (final dim in kPathAlbumArtDiskDimensions) {
    final key = _pathDiskKey(path, dim);
    if (key.isNotEmpty && _memory.containsKey(key)) return dim;
  }
  return null;
}

Future<Uint8List?> _bytesAtTargetDimension(
  String filePath,
  Uint8List source, {
  required int target,
  String? cacheKey,
}) async {
  if (source.isEmpty) return null;

  if (cacheKey != null) {
    final exact = _memory[cacheKey];
    if (exact != null && exact.isNotEmpty) {
      _touchMemory(cacheKey, exact);
      return exact;
    }
  }

  if (_memoryDimensionForPath(filePath) == target) {
    final key = _pathDiskKey(filePath, target);
    if (key.isNotEmpty) return _memory[key];
  }

  final resized = await _resizeToPng(source, target);
  final out = (resized == null || resized.isEmpty) ? source : resized;
  if (cacheKey != null && out.isNotEmpty) _putMemory(cacheKey, out);
  return out;
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
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    try {
      final w = frame.image.width;
      final h = frame.image.height;
      if (w <= maxDimension && h <= maxDimension) {
        return raw;
      }
    } finally {
      frame.image.dispose();
    }

    final codec2 = await ui.instantiateImageCodec(
      raw,
      targetWidth: maxDimension,
      targetHeight: maxDimension,
    );
    final frame2 = await codec2.getNextFrame();
    try {
      final byteData =
          await frame2.image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      frame2.image.dispose();
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

/// Removes path-keyed album-art disk files and in-memory decode cache.
Future<void> clearAllAlbumArtDiskCache() async {
  _memory.clear();
  _inFlight.clear();
  _inFlightByPathKey.clear();
  final cachedDir = _cacheDir;
  _cacheDir = null;
  try {
    if (cachedDir != null && await cachedDir.exists()) {
      await cachedDir.delete(recursive: true);
      return;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _cacheDirName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e, st) {
    debugPrint('clearAllAlbumArtDiskCache: $e\n$st');
  }
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

