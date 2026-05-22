import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../models/song_metadata_cache_row.dart';
import '../models/track_item.dart';
import 'song_metadata_cache_types.dart';

Database? _db;
final _store = stringMapStoreFactory.store('metadata');

Future<String> _ensureDatabaseDirectory(String applicationSupportPath) async {
  final primary = p.join(applicationSupportPath, 'metadata_cache');
  switch (FileSystemEntity.typeSync(primary)) {
    case FileSystemEntityType.notFound:
      await Directory(primary).create(recursive: true);
      return primary;
    case FileSystemEntityType.directory:
      return primary;
    default:
      final fallback = p.join(applicationSupportPath, 'metadata_cache_db');
      await Directory(fallback).create(recursive: true);
      return fallback;
  }
}

Future<Database> _openDatabase() async {
  final existing = _db;
  if (existing != null) return existing;
  final dir = await getApplicationSupportDirectory();
  final dbPath = await _ensureDatabaseDirectory(dir.path);
  final db = await databaseFactoryIo.openDatabase(
    p.join(dbPath, 'mp3_player_metadata_v4.sembast'),
  );
  _db = db;
  return db;
}

Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) async {
  if (paths.isEmpty) return const <String, TrackItem>{};
  try {
    final db = await _openDatabase();
    final out = <String, TrackItem>{};
    for (final path in paths) {
      final record = await _store.record(path).get(db);
      if (record == null) continue;
      final row = SongMetadataCacheRow.fromJson(record);
      out[row.path] = _trackFromRow(row);
    }
    return out;
  } catch (e, st) {
    debugPrint('SongMetadataCache.loadTracksByPaths: $e\n$st');
    return const <String, TrackItem>{};
  }
}

Future<void> saveTracks(Iterable<TrackItem> tracks) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rows = <SongMetadataCacheRow>[];
  for (final t in tracks) {
    final path = t.filePath?.trim();
    if (path == null || path.isEmpty) continue;
    rows.add(
      SongMetadataCacheRow(
        path: path,
        title: t.title,
        artist: t.artist,
        album: t.metaLine,
        genres: t.genres,
        artColorValues: t.artColors
            .map((c) => c.toARGB32())
            .toList(growable: false),
        fileSizeBytes: 0,
        updatedAtMs: now,
      ),
    );
  }
  if (rows.isEmpty) return;
  try {
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final row in rows) {
        await _store.record(row.path).put(txn, row.toJson());
      }
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
    final db = await _openDatabase();
    final records = await _store.find(db);
    final out = <String, CachedTrackSnapshot>{};
    for (final record in records) {
      final row = SongMetadataCacheRow.fromJson(record.value);
      if (!_isPathUnderRoots(row.path, roots)) continue;
      out[row.path] = CachedTrackSnapshot(
        track: _trackFromRow(row),
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
    rows.add(
      SongMetadataCacheRow(
        path: path,
        title: s.track.title,
        artist: s.track.artist,
        album: s.track.metaLine,
        genres: s.track.genres,
        artColorValues: s.track.artColors
            .map((c) => c.toARGB32())
            .toList(growable: false),
        fileSizeBytes: s.fileSizeBytes,
        updatedAtMs: s.fileModifiedMs,
      ),
    );
  }
  if (rows.isEmpty) return;
  try {
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final row in rows) {
        await _store.record(row.path).put(txn, row.toJson());
      }
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.saveTrackSnapshots: $e\n$st');
  }
}

Future<void> deleteMissingPaths(Set<String> existingPaths) async {
  try {
    final db = await _openDatabase();
    final records = await _store.find(db);
    final staleKeys = <String>[];
    for (final record in records) {
      final path = record.key;
      if (!existingPaths.contains(path)) {
        staleKeys.add(path);
      }
    }
    if (staleKeys.isEmpty) return;
    await db.transaction((txn) async {
      for (final key in staleKeys) {
        await _store.record(key).delete(txn);
      }
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
    final db = await _openDatabase();
    await db.transaction((txn) async {
      for (final path in normalized) {
        await _store.record(path).delete(txn);
      }
    });
  } catch (e, st) {
    debugPrint('SongMetadataCache.deletePaths: $e\n$st');
  }
}

TrackItem _trackFromRow(SongMetadataCacheRow row) {
  return TrackItem(
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
