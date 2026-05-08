import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song_metadata_cache_row.dart';
import '../models/track_item.dart';
import 'song_metadata_cache_types.dart';

Isar? _isar;

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
    // Bump after schema change so installs don't reuse incompatible Isar files.
    name: 'mp3_player_metadata_v3',
  );
  _isar = db;
  return db;
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
      );
    }
    return out;
  } catch (e, st) {
    debugPrint('SongMetadataCache.loadTracksByPaths: $e\n$st');
    return const <String, TrackItem>{};
  }
}

Future<void> saveTracks(Iterable<TrackItem> tracks) async {
  final rows = <SongMetadataCacheRow>[];
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final t in tracks) {
    final path = t.filePath?.trim();
    if (path == null || path.isEmpty) continue;
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
      ..fileSizeBytes = 0
      ..updatedAtMs = now;
    rows.add(row);
  }
  if (rows.isEmpty) return;
  try {
    final db = await _openIsar();
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
    final rows = await db.songMetadataCacheRows.where().findAll();
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
  final rows = <SongMetadataCacheRow>[];
  for (final s in tracks) {
    final path = s.track.filePath?.trim();
    if (path == null || path.isEmpty) continue;
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
      ..updatedAtMs = s.fileModifiedMs;
    rows.add(row);
  }
  if (rows.isEmpty) return;
  try {
    final db = await _openIsar();
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
