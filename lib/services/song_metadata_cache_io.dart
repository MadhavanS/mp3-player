import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_metadata_cache_row.dart';
import '../models/track_item.dart';
import 'album_art_cache.dart';
import 'music_library_path_key.dart';
import 'song_metadata_cache_types.dart';

Isar? _isar;
const _backfillArtFlagKey = 'song_metadata_art_disk_flag_backfill_v1';

/// Isar refuses to open when [directory] is missing or names an existing file.
Future<String> _ensureIsarDatabaseDirectory(
  String applicationSupportPath,
) async {
  final primary = p.join(applicationSupportPath, 'isar');
  switch (FileSystemEntity.typeSync(primary)) {
    case FileSystemEntityType.notFound:
      await Directory(primary).create(recursive: true);
      return primary;
    case FileSystemEntityType.directory:
      return primary;
    default:
      final fallback = p.join(applicationSupportPath, 'isar_mp3_player_db');
      await Directory(fallback).create(recursive: true);
      return fallback;
  }
}

Future<Isar> _openIsar() async {
  final existing = _isar;
  if (existing != null && existing.isOpen) return existing;
  final dir = await getApplicationSupportDirectory();
  final dbPath = await _ensureIsarDatabaseDirectory(dir.path);
  final db = await Isar.openAsync(
    schemas: [SongMetadataCacheRowSchema],
    directory: dbPath,
    name: 'mp3_player_metadata_v4',
  );
  _isar = db;
  await _maybeBackfillArtDiskCacheFlags(db);
  return db;
}

/// Closes the metadata database and deletes on-disk Isar files.
Future<void> clearAllSongMetadataCache() async {
  final db = _isar;
  _isar = null;
  if (db != null && db.isOpen) {
    try {
      await db.close();
    } catch (e, st) {
      debugPrint('clearAllSongMetadataCache close: $e\n$st');
    }
  }
  try {
    final support = await getApplicationSupportDirectory();
    for (final name in ['isar', 'isar_mp3_player_db']) {
      final dir = Directory(p.join(support.path, name));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  } catch (e, st) {
    debugPrint('clearAllSongMetadataCache delete: $e\n$st');
  }
}

void _copyArtDiskFlags({
  required SongMetadataCacheRow row,
  required SongMetadataCacheRow? prev,
  required bool fingerprintMatchesPrev,
}) {
  if (prev == null || !fingerprintMatchesPrev) {
    row.hasArtDiskCache = false;
    row.artCachedForModifiedMs = 0;
    row.artCachedForSizeBytes = 0;
    return;
  }
  row.hasArtDiskCache = prev.hasArtDiskCache;
  row.artCachedForModifiedMs = prev.artCachedForModifiedMs;
  row.artCachedForSizeBytes = prev.artCachedForSizeBytes;
}

Future<void> _maybeBackfillArtDiskCacheFlags(Isar db) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backfillArtFlagKey) == true) return;

    final all = db.songMetadataCacheRows.where().findAll();
    if (all.isEmpty) {
      await prefs.setBool(_backfillArtFlagKey, true);
      return;
    }

    final paths = all.map((r) => r.path).toList(growable: false);
    final keysWithDisk = await pathKeysWithDiskAlbumArt(paths);

    if (keysWithDisk.isNotEmpty) {
      await db.writeAsync((isar) {
        for (final row in all) {
          final key = canonicalMusicLibraryPathKey(row.path);
          if (!keysWithDisk.contains(key)) continue;
          row.hasArtDiskCache = true;
          row.artCachedForModifiedMs = row.updatedAtMs;
          row.artCachedForSizeBytes = row.fileSizeBytes;
        }
        isar.songMetadataCacheRows.putAll(all);
      });
    }

    await prefs.setBool(_backfillArtFlagKey, true);
  } catch (e, st) {
    debugPrint('SongMetadataCache._maybeBackfillArtDiskCacheFlags: $e\n$st');
  }
}

Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) async {
  if (paths.isEmpty) return const <String, TrackItem>{};
  try {
    final db = await _openIsar();
    final rows = db.songMetadataCacheRows
        .where()
        .anyOf(paths, (q, path) => q.pathEqualTo(path))
        .findAll();
    final out = <String, TrackItem>{};
    for (final row in rows) {
      out[row.path] = TrackItem(
        title: row.title.trim().isNotEmpty
            ? row.title
            : p.basenameWithoutExtension(row.path),
        artist: row.artist.trim().isNotEmpty ? row.artist : 'Unknown artist',
        metaLine: row.album.trim().isNotEmpty ? row.album : 'mp3',
        genres: row.genres,
        artColors: row.artColorValues
            .map((v) => Color(v))
            .toList(growable: false),
        filePath: row.path,
        albumArtBytes: null,
        replayGainTrackDb: row.hasReplayGainTrack ? row.replayGainTrackDb : null,
        replayGainAlbumDb: row.hasReplayGainAlbum ? row.replayGainAlbumDb : null,
      );
    }
    return out;
  } catch (e, st) {
    debugPrint('SongMetadataCache.loadTracksByPaths: $e\n$st');
    return const <String, TrackItem>{};
  }
}

Future<void> saveTracks(Iterable<TrackItem> tracks) async {
  final items = tracks
      .where((t) {
        final path = t.filePath?.trim();
        return path != null && path.isNotEmpty;
      })
      .toList(growable: false);
  if (items.isEmpty) return;

  try {
    final db = await _openIsar();
    final paths = items.map((t) => t.filePath!.trim()).toList(growable: false);
    final existingRows = db.songMetadataCacheRows
        .where()
        .anyOf(paths, (q, path) => q.pathEqualTo(path))
        .findAll();
    final existingByPath = {for (final r in existingRows) r.path: r};
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <SongMetadataCacheRow>[];
    for (final t in items) {
      final path = t.filePath!.trim();
      final prev = existingByPath[path];
      final row = SongMetadataCacheRow()
        ..id = _stablePathId(path)
        ..path = path
        ..title = t.title
        ..artist = t.artist
        ..album = t.metaLine
        ..genres = t.genres
        ..artColorValues = t.artColors
            .map((c) => c.toARGB32())
            .toList(growable: false)
        // Preserve disk-sync fingerprint so background sync does not re-read
        // every file after art-only warmup or tag edits.
        ..fileSizeBytes = prev?.fileSizeBytes ?? 0
        ..updatedAtMs = prev?.updatedAtMs ?? now
        ..hasReplayGainTrack = t.replayGainTrackDb != null
        ..replayGainTrackDb = t.replayGainTrackDb ?? 0
        ..hasReplayGainAlbum = t.replayGainAlbumDb != null
        ..replayGainAlbumDb = t.replayGainAlbumDb ?? 0;
      _copyArtDiskFlags(
        row: row,
        prev: prev,
        fingerprintMatchesPrev: prev != null,
      );
      rows.add(row);
    }
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.putAll(rows);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.saveTracks: $e\n$st');
  }
}

Future<Map<String, CachedTrackSnapshot>> loadSnapshotsForRoots(
  List<String> roots,
) async {
  if (roots.isEmpty) return const <String, CachedTrackSnapshot>{};
  try {
    final db = await _openIsar();
    final rows = db.songMetadataCacheRows.where().findAll();
    final out = <String, CachedTrackSnapshot>{};
    for (final row in rows) {
      if (!_isPathUnderRoots(row.path, roots)) continue;
      final track = TrackItem(
        title: row.title.trim().isNotEmpty
            ? row.title
            : p.basenameWithoutExtension(row.path),
        artist: row.artist.trim().isNotEmpty ? row.artist : 'Unknown artist',
        metaLine: row.album.trim().isNotEmpty ? row.album : 'mp3',
        genres: row.genres,
        artColors: row.artColorValues
            .map((v) => Color(v))
            .toList(growable: false),
        filePath: row.path,
        albumArtBytes: null,
        replayGainTrackDb: row.hasReplayGainTrack ? row.replayGainTrackDb : null,
        replayGainAlbumDb: row.hasReplayGainAlbum ? row.replayGainAlbumDb : null,
      );
      out[row.path] = CachedTrackSnapshot(
        track: track,
        fileModifiedMs: row.updatedAtMs,
        fileSizeBytes: row.fileSizeBytes,
      );
    }
    return out;
  } catch (e, st) {
    debugPrint('SongMetadataCache.loadSnapshotsForRoots: $e\n$st');
    return const <String, CachedTrackSnapshot>{};
  }
}

Future<void> saveTrackSnapshots(Iterable<CachedTrackSnapshot> tracks) async {
  final snapshots = tracks.toList(growable: false);
  if (snapshots.isEmpty) return;

  try {
    final db = await _openIsar();
    final paths = snapshots
        .map((s) => s.track.filePath?.trim())
        .whereType<String>()
        .where((p0) => p0.isNotEmpty)
        .toList(growable: false);
    final existingByPath = <String, SongMetadataCacheRow>{};
    if (paths.isNotEmpty) {
      final existingRows = db.songMetadataCacheRows
          .where()
          .anyOf(paths, (q, path) => q.pathEqualTo(path))
          .findAll();
      for (final r in existingRows) {
        existingByPath[r.path] = r;
      }
    }

    final rows = <SongMetadataCacheRow>[];
    for (final s in snapshots) {
      final path = s.track.filePath?.trim();
      if (path == null || path.isEmpty) continue;
      final prev = existingByPath[path];
      final fingerprintMatchesPrev = prev != null &&
          prev.updatedAtMs == s.fileModifiedMs &&
          prev.fileSizeBytes == s.fileSizeBytes;
      final row = SongMetadataCacheRow()
        ..id = _stablePathId(path)
        ..path = path
        ..title = s.track.title
        ..artist = s.track.artist
        ..album = s.track.metaLine
        ..genres = s.track.genres
        ..artColorValues = s.track.artColors
            .map((c) => c.toARGB32())
            .toList(growable: false)
        ..fileSizeBytes = s.fileSizeBytes
        ..updatedAtMs = s.fileModifiedMs
        ..hasReplayGainTrack = s.track.replayGainTrackDb != null
        ..replayGainTrackDb = s.track.replayGainTrackDb ?? 0
        ..hasReplayGainAlbum = s.track.replayGainAlbumDb != null
        ..replayGainAlbumDb = s.track.replayGainAlbumDb ?? 0;
      _copyArtDiskFlags(
        row: row,
        prev: prev,
        fingerprintMatchesPrev: fingerprintMatchesPrev,
      );
      rows.add(row);
    }
    if (rows.isEmpty) return;
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.putAll(rows);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.saveTrackSnapshots: $e\n$st');
  }
}

Future<void> deleteMissingPaths(Set<String> existingPaths) async {
  try {
    final db = await _openIsar();
    final all = db.songMetadataCacheRows.where().findAll();
    final staleIds = <int>[];
    for (final row in all) {
      if (!existingPaths.contains(row.path)) {
        staleIds.add(row.id);
      }
    }
    if (staleIds.isEmpty) return;
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.deleteAll(staleIds);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.deleteMissingPaths: $e\n$st');
  }
}

Future<void> deletePaths(Iterable<String> paths) async {
  final normalized = paths
      .map((p0) => p0.trim())
      .where((p0) => p0.isNotEmpty)
      .toSet();
  if (normalized.isEmpty) return;
  try {
    final db = await _openIsar();
    final rows = db.songMetadataCacheRows
        .where()
        .anyOf(normalized.toList(), (q, path) => q.pathEqualTo(path))
        .findAll();
    if (rows.isEmpty) return;
    final ids = rows.map((r) => r.id).toList(growable: false);
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.deleteAll(ids);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.deletePaths: $e\n$st');
  }
}

/// Marks path-keyed disk art as present for the row's current file fingerprint.
Future<void> markArtDiskCachedForPath(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return;
  try {
    final db = await _openIsar();
    final row = db.songMetadataCacheRows
        .where()
        .pathEqualTo(path)
        .findFirst();
    if (row == null) return;
    row.hasArtDiskCache = true;
    row.artCachedForModifiedMs = row.updatedAtMs;
    row.artCachedForSizeBytes = row.fileSizeBytes;
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.put(row);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.markArtDiskCachedForPath: $e\n$st');
  }
}

Future<void> clearArtDiskCacheFlagForPath(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return;
  try {
    final db = await _openIsar();
    final row = db.songMetadataCacheRows
        .where()
        .pathEqualTo(path)
        .findFirst();
    if (row == null) return;
    row.hasArtDiskCache = false;
    row.artCachedForModifiedMs = 0;
    row.artCachedForSizeBytes = 0;
    await db.writeAsync((isar) {
      isar.songMetadataCacheRows.put(row);
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.clearArtDiskCacheFlagForPath: $e\n$st');
  }
}

Future<bool> hasValidArtDiskCacheForPath(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return false;
  try {
    final db = await _openIsar();
    final row = db.songMetadataCacheRows
        .where()
        .pathEqualTo(path)
        .findFirst();
    return row != null && row.isArtCacheValid;
  } catch (e, st) {
    debugPrint('SongMetadataCache.hasValidArtDiskCacheForPath: $e\n$st');
    return false;
  }
}

/// Canonical path keys with a valid Isar art-disk flag (no filesystem probe).
Future<Set<String>> pathKeysWithValidArtDiskCache(
  Iterable<String> filePaths,
) async {
  final paths = filePaths
      .map((p0) => p0.trim())
      .where((p0) => p0.isNotEmpty)
      .toList(growable: false);
  if (paths.isEmpty) return const <String>{};

  try {
    final db = await _openIsar();
    final rows = db.songMetadataCacheRows
        .where()
        .anyOf(paths, (q, path) => q.pathEqualTo(path))
        .findAll();
    final out = <String>{};
    for (final row in rows) {
      if (!row.isArtCacheValid) continue;
      final key = canonicalMusicLibraryPathKey(row.path);
      if (key.isNotEmpty) out.add(key);
    }
    return out;
  } catch (e, st) {
    debugPrint('SongMetadataCache.pathKeysWithValidArtDiskCache: $e\n$st');
    return const <String>{};
  }
}

int _stablePathId(String value) {
  var hash = 0x811C9DC5;
  for (final c in value.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

bool _isPathUnderRoots(String path, List<String> roots) {
  final normPath = p.normalize(path).toLowerCase();
  final sep = p.separator;
  for (final root in roots) {
    final normRoot = p.normalize(root).toLowerCase();
    final rootNoTrail = normRoot.endsWith(sep)
        ? normRoot.substring(0, normRoot.length - 1)
        : normRoot;
    if (normPath == rootNoTrail || normPath.startsWith('$rootNoTrail$sep')) {
      return true;
    }
  }
  return false;
}
