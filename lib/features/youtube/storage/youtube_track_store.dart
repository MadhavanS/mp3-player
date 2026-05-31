import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/track_item.dart';
import '../youtube_duration_format.dart';
import 'youtube_track_record.dart';

Isar? _isar;

Future<String> _ensureIsarDatabaseDirectory(String applicationSupportPath) async {
  final primary = p.join(applicationSupportPath, 'isar_youtube');
  switch (FileSystemEntity.typeSync(primary)) {
    case FileSystemEntityType.notFound:
      await Directory(primary).create(recursive: true);
      return primary;
    case FileSystemEntityType.directory:
      return primary;
    default:
      final fallback = p.join(applicationSupportPath, 'isar_youtube_db');
      await Directory(fallback).create(recursive: true);
      return fallback;
  }
}

Future<Isar> openYoutubeTrackIsar() async {
  final existing = _isar;
  if (existing != null && existing.isOpen) return existing;
  final dir = await getApplicationSupportDirectory();
  final dbPath = await _ensureIsarDatabaseDirectory(dir.path);
  final db = await Isar.openAsync(
    schemas: [YoutubeTrackRecordSchema],
    directory: dbPath,
    name: 'youtube_tracks_v1',
  );
  _isar = db;
  return db;
}

/// Persists downloaded YouTube tracks (local file paths + metadata).
class YoutubeTrackStore {
  YoutubeTrackStore._();

  static final instance = YoutubeTrackStore._();

  Future<void> init() async {
    await openYoutubeTrackIsar();
  }

  Future<List<YoutubeTrackRecord>> getAllDownloaded() async {
    try {
      final db = await openYoutubeTrackIsar();
      final rows = db.youtubeTrackRecords.where().findAll();
      rows.sort((a, b) => b.downloadedAtMs.compareTo(a.downloadedAtMs));
      return rows.where((r) => r.isDownloaded).toList(growable: false);
    } catch (e, st) {
      debugPrint('YoutubeTrackStore.getAllDownloaded: $e\n$st');
      return const [];
    }
  }

  Future<YoutubeTrackRecord?> get(String videoId) async {
    if (videoId.trim().isEmpty) return null;
    try {
      final db = await openYoutubeTrackIsar();
      return db.youtubeTrackRecords
          .where()
          .videoIdEqualTo(videoId.trim())
          .findFirst();
    } catch (e, st) {
      debugPrint('YoutubeTrackStore.get: $e\n$st');
      return null;
    }
  }

  Future<void> save(YoutubeTrackRecord record) async {
    final db = await openYoutubeTrackIsar();
    await db.writeAsync((isar) {
      isar.youtubeTrackRecords.put(record);
    });
  }

  Future<void> delete(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return;
    final record = await get(id);
    if (record == null) return;

    final path = record.localPath?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e, st) {
        debugPrint('YoutubeTrackStore.delete file: $e\n$st');
      }
    }

    final db = await openYoutubeTrackIsar();
    await db.writeAsync((isar) {
      isar.youtubeTrackRecords
          .where()
          .videoIdEqualTo(id)
          .deleteAll();
    });
  }

  Future<List<TrackItem>> getAllAsTrackItems() async {
    final records = await getAllDownloaded();
    final out = <TrackItem>[];
    for (final r in records) {
      final path = r.localPath?.trim();
      if (path == null || path.isEmpty) continue;
      if (!await File(path).exists()) continue;
      out.add(trackItemFromYoutubeRecord(r));
    }
    return out;
  }

  /// Wipes the YouTube Isar database (factory reset).
  Future<void> clearAll() async {
    final db = _isar;
    _isar = null;
    if (db != null && db.isOpen) {
      try {
        db.close();
      } catch (e, st) {
        debugPrint('YoutubeTrackStore.clearAll close: $e\n$st');
      }
    }
    try {
      final support = await getApplicationSupportDirectory();
      for (final name in ['isar_youtube', 'isar_youtube_db']) {
        final dir = Directory(p.join(support.path, name));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e, st) {
      debugPrint('YoutubeTrackStore.clearAll delete: $e\n$st');
    }
  }
}

TrackItem trackItemFromYoutubeRecord(YoutubeTrackRecord r) {
  final path = r.localPath!.trim();
  final durationLabel = formatYoutubeDurationMs(r.durationMs);
  final metaLine = durationLabel.isEmpty
      ? 'YouTube'
      : 'YouTube · $durationLabel';
  return TrackItem(
    title: r.title.trim().isNotEmpty ? r.title : r.videoId,
    artist: r.artist.trim().isNotEmpty ? r.artist : 'Unknown artist',
    metaLine: metaLine,
    genres: '',
    artColors: TrackItem.fromFilePath(path).artColors,
    filePath: path,
  );
}
