import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song_metadata_cache_row.dart';
import '../models/track_item.dart';

Isar? _isar;

Future<Isar> _openIsar() async {
  final existing = _isar;
  if (existing != null && existing.isOpen) return existing;
  final dir = await getApplicationSupportDirectory();
  final db = await Isar.openAsync(
    schemas: [SongMetadataCacheRowSchema],
    directory: p.join(dir.path, 'isar'),
    name: 'mp3_player_metadata',
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
        albumArtBytes: row.albumArtBytes == null
            ? null
            : Uint8List.fromList(row.albumArtBytes!),
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
      ..albumArtBytes = t.albumArtBytes?.toList(growable: false)
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
