import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../audio/album_art_resolver.dart';
import '../audio/player_controller.dart';
import '../models/track_item.dart';
import 'album_art_cache.dart';
import 'music_library_path_key.dart';
import 'track_metadata.dart';

/// Loads small cover thumbnails for the library cover picker (one file at a time).
abstract final class PickerAlbumArtLoader {
  static final _memory = <String, Uint8List?>{};
  static final List<_ThumbRequest> _queue = [];
  static var _active = false;

  /// How many paths are waiting for a thumbnail (for UI feedback).
  static final ValueNotifier<int> queueDepth = ValueNotifier(0);

  static int? _pendingQueueDepth;
  static bool _queueDepthNotifyScheduled = false;

  /// Notifies [queueDepth] after the current frame — safe when called from
  /// [State.didUpdateWidget] while a [ValueListenableBuilder] is building.
  static void _setQueueDepth(int n) {
    _pendingQueueDepth = n;
    if (_queueDepthNotifyScheduled) return;
    _queueDepthNotifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queueDepthNotifyScheduled = false;
      final depth = _pendingQueueDepth;
      if (depth == null) return;
      if (queueDepth.value != depth) queueDepth.value = depth;
    });
  }

  /// Art already in hot LRU / path memory / embedded tags (no disk read).
  static Uint8List? resolveSync(
    TrackItem track,
    PlayerController player, {
    int maxDimension = 112,
  }) {
    final path = track.filePath?.trim();
    if (path == null || path.isEmpty) return null;
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return null;
    if (_memory.containsKey(key)) {
      final cached = _memory[key];
      if (cached != null && cached.isNotEmpty) return cached;
    }
    return resolveAlbumArtBytesSync(
      track,
      player,
      targetDimension: maxDimension,
    );
  }

  /// Queue thumbnails for [tracks] (visible rows first).
  static void preloadTracks(
    Iterable<TrackItem> tracks, {
    PlayerController? player,
    int maxDimension = 112,
  }) {
    for (final track in tracks) {
      final path = track.filePath?.trim();
      if (path == null || path.isEmpty) continue;
      final key = canonicalMusicLibraryPathKey(path);
      if (key.isEmpty || _memory.containsKey(key)) continue;
      if (player != null) {
        final sync = resolveSync(track, player, maxDimension: maxDimension);
        if (sync != null && sync.isNotEmpty) {
          _memory[key] = sync;
          continue;
        }
      }
      unawaited(
        thumbForTrack(track, maxDimension: maxDimension, highPriority: true),
      );
    }
  }

  static Future<Uint8List?> thumbForTrack(
    TrackItem track, {
    int maxDimension = 112,
    bool highPriority = false,
  }) async {
    final path = track.filePath?.trim();
    if (path == null || path.isEmpty) return null;
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return null;
    if (_memory.containsKey(key)) return _memory[key];

    for (final pending in _queue) {
      if (pending.key == key) return pending.completer.future;
    }

    final completer = Completer<Uint8List?>();
    final job = _ThumbRequest(
      path: path,
      key: key,
      maxDimension: maxDimension,
      completer: completer,
      existingArt: track.albumArtBytes,
    );
    if (highPriority) {
      _queue.insert(0, job);
    } else {
      _queue.add(job);
    }
    _setQueueDepth(_queue.length);
    _pump();
    return completer.future;
  }

  static void _pump() {
    if (_active || _queue.isEmpty) return;
    _active = true;
    unawaited(() async {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        _setQueueDepth(_queue.length);
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
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      _active = false;
      _setQueueDepth(0);
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

    final fromDisk = await cachedAlbumArtForPath(
      job.path,
      maxDimension: job.maxDimension,
    );
    if (fromDisk != null && fromDisk.isNotEmpty) return fromDisk;

    final raw = await readCoverBytesOnly(job.path);
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
