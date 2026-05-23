import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/track_item.dart';
import 'album_art_cache.dart';
import 'music_library_path_key.dart';
import 'track_metadata_io.dart';

/// Loads one small cover thumbnail at a time for the library cover picker (avoids ANR).
abstract final class PickerAlbumArtLoader {
  static final _memory = <String, Uint8List?>{};
  static final _queue = Queue<_ThumbRequest>();
  static var _active = false;

  static Future<Uint8List?> thumbForTrack(
    TrackItem track, {
    int maxDimension = 112,
  }) async {
    final path = track.filePath?.trim();
    if (path == null || path.isEmpty) return null;
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return null;
    if (_memory.containsKey(key)) return _memory[key];

    final completer = Completer<Uint8List?>();
    _queue.add(
      _ThumbRequest(
        path: path,
        key: key,
        maxDimension: maxDimension,
        completer: completer,
        existingArt: track.albumArtBytes,
      ),
    );
    _pump();
    return completer.future;
  }

  static void _pump() {
    if (_active || _queue.isEmpty) return;
    _active = true;
    unawaited(() async {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        if (job.completer.isCompleted) continue;
        try {
          if (_memory.containsKey(job.key)) {
            job.completer.complete(_memory[job.key]);
            continue;
          }
          final bytes = await _loadThumb(job);
          _memory[job.key] = bytes;
          job.completer.complete(bytes);
        } catch (e, st) {
          debugPrint('PickerAlbumArtLoader: ${job.path}: $e\n$st');
          _memory[job.key] = null;
          job.completer.complete(null);
        }
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
      _active = false;
    }());
  }

  static Future<Uint8List?> _loadThumb(_ThumbRequest job) async {
    final existing = job.existingArt;
    if (existing != null && existing.isNotEmpty) {
      final track = TrackItem.fromFilePath(job.path).withEmbeddedMetadata(
        albumArtBytes: existing,
        replaceAlbumArtFromFile: true,
      );
      return cachedAlbumArt(track, maxDimension: job.maxDimension);
    }

    final payload = await compute(readEmbeddedFileMetadataIsolate, job.path);
    final raw = payload?.albumArtBytes;
    if (raw == null || raw.isEmpty) return null;

    final track = TrackItem.fromFilePath(job.path).withEmbeddedMetadata(
      albumArtBytes: raw,
      replaceAlbumArtFromFile: true,
    );
    return cachedAlbumArt(track, maxDimension: job.maxDimension);
  }
}

class _ThumbRequest {
  _ThumbRequest({
    required this.path,
    required this.key,
    required this.maxDimension,
    required this.completer,
    this.existingArt,
  });

  final String path;
  final String key;
  final int maxDimension;
  final Completer<Uint8List?> completer;
  final Uint8List? existingArt;
}
