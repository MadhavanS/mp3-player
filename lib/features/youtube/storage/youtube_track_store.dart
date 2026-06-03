import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/track_item.dart';
import '../../../services/metadata_backend_config.dart';
import '../../../services/metadata_god_reader_io.dart';
import '../../../services/track_metadata.dart';
import '../../../services/music_library_path_key.dart';
import '../youtube_storage_paths.dart';
import '../youtube_video_id.dart';
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
      final rows = await _getAllRecords();
      rows.sort((a, b) => b.downloadedAtMs.compareTo(a.downloadedAtMs));
      return rows.where((r) => r.isDownloaded).toList(growable: false);
    } catch (e, st) {
      debugPrint('YoutubeTrackStore.getAllDownloaded: $e\n$st');
      return const [];
    }
  }

  Future<List<YoutubeTrackRecord>> _getAllRecords() async {
    final db = await openYoutubeTrackIsar();
    return db.youtubeTrackRecords.where().findAll();
  }

  Future<Set<String>> downloadedVideoIds() async {
    final rows = await getAllDownloaded();
    return rows.map((r) => r.videoId).toSet();
  }

  Future<YoutubeTrackRecord?> findByLocalPath(String filePath) async {
    final key = canonicalMusicLibraryPathKey(filePath);
    if (key.isEmpty) return null;
    for (final row in await _getAllRecords()) {
      final path = row.localPath?.trim();
      if (path == null || path.isEmpty) continue;
      if (canonicalMusicLibraryPathKey(path) == key) return row;
    }
    return null;
  }

  /// Local audio path when the file exists, else null.
  Future<String?> filePathForVideoId(String videoId) async {
    final row = await get(videoId);
    final path = row?.localPath?.trim();
    if (path == null || path.isEmpty) return null;
    if (!await _youtubeAudioFileExists(path)) return null;
    return path;
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
    final videoId = record.videoId.trim();
    if (videoId.isEmpty) return;

    final path = record.localPath?.trim();
    if (path != null && path.isNotEmpty) {
      if (await File(path).exists()) {
        record.localPath = p.normalize(path);
      } else {
        try {
          record.localPath = p.normalize(File(path).absolute.path);
        } catch (_) {
          record.localPath = p.normalize(path);
        }
      }
    }

    final existing = await get(videoId);
    if (existing != null) {
      record.id = existing.id;
    }

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
    final dirPath = await youtubeAudioStorageDirectoryPath();
    final out = <TrackItem>[];
    final seenKeys = <String>{};

    final paths = await listAudioPathsInStorageFolder(dirPath);
    for (final path in paths) {
      final key = canonicalMusicLibraryPathKey(path);
      if (key.isEmpty || !seenKeys.add(key)) continue;

      final record = await registerStorageFile(path);
      if (record == null) continue;
      out.add(trackItemFromYoutubeRecord(record));
    }

    for (final r in await getAllDownloaded()) {
      final path = r.localPath?.trim();
      if (path == null || path.isEmpty) continue;
      final key = canonicalMusicLibraryPathKey(path);
      if (key.isEmpty || seenKeys.contains(key)) continue;
      if (!await _youtubeAudioFileExists(path)) continue;
      seenKeys.add(key);
      out.add(trackItemFromYoutubeRecord(r));
    }

    out.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return out;
  }

  /// All playable audio files under [dirPath] (recursive).
  Future<List<String>> listAudioPathsInStorageFolder(String dirPath) async {
    final dir = Directory(p.normalize(dirPath));
    if (!await dir.exists()) return const [];

    try {
      final paths = <String>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!isYoutubeStorageAudioExtension(entity.path)) continue;
        paths.add(await stableYoutubeStoragePath(entity.path));
      }
      return paths;
    } catch (e, st) {
      debugPrint('YoutubeTrackStore.list (async): $e\n$st');
      return _listAudioPathsSyncRecursive(dir);
    }
  }

  Future<List<String>> _listAudioPathsSyncRecursive(Directory root) async {
    final raw = <String>[];
    void walk(Directory dir) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (e, st) {
        debugPrint('YoutubeTrackStore.listSync ${dir.path}: $e\n$st');
        return;
      }
      for (final entity in entries) {
        if (entity is File) {
          if (isYoutubeStorageAudioExtension(entity.path)) {
            raw.add(entity.path);
          }
        } else if (entity is Directory) {
          walk(entity);
        }
      }
    }

    walk(root);
    final out = <String>[];
    for (final path in raw) {
      out.add(await stableYoutubeStoragePath(path));
    }
    return out;
  }

  /// Registers or updates one on-disk file from the active YouTube folder.
  Future<YoutubeTrackRecord?> registerStorageFile(String rawPath) async {
    if (!isYoutubeStorageAudioExtension(rawPath)) return null;

    final path = await stableYoutubeStoragePath(rawPath);
    if (!await _youtubeAudioFileExists(path)) return null;

    final pathKey = canonicalMusicLibraryPathKey(path);
    if (pathKey.isEmpty) return null;

    final stat = await File(path).stat();

    final existingByPath = await findByLocalPath(path);
    if (existingByPath != null) {
      if (existingByPath.fileSizeBytes != stat.size) {
        existingByPath.fileSizeBytes = stat.size;
        await save(existingByPath);
      }
      return existingByPath;
    }

    final parsed = await _trackAndDurationFromFile(path);
    final track = parsed.track;
    final durationMs = parsed.durationMs;

    var videoId = videoIdForStorageFile(path);
    var record = await get(videoId);
    if (record != null) {
      final existingKey = canonicalMusicLibraryPathKey(record.localPath ?? '');
      if (existingKey.isNotEmpty && existingKey != pathKey) {
        videoId = pathBasedVideoId(path);
        record = await get(videoId);
      }
    }

    if (record != null) {
      record
        ..localPath = path
        ..title = track.title.trim().isNotEmpty ? track.title : record.title
        ..artist = track.artist.trim().isNotEmpty &&
                track.artist != 'Unknown artist'
            ? track.artist
            : record.artist
        ..fileSizeBytes = stat.size
        ..downloadedAtMs = stat.modified.millisecondsSinceEpoch;
      if (durationMs != null) record.durationMs = durationMs;
    } else {
      record = YoutubeTrackRecord()
        ..videoId = videoId
        ..title = track.title.trim().isNotEmpty ? track.title : videoId
        ..artist = track.artist.trim().isNotEmpty &&
                track.artist != 'Unknown artist'
            ? track.artist
            : 'Unknown artist'
        ..localPath = path
        ..downloadedAtMs = stat.modified.millisecondsSinceEpoch
        ..fileSizeBytes = stat.size
        ..durationMs = durationMs;
    }

    await save(record);
    return record;
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

bool isYoutubeStorageAudioExtension(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.m4a':
    case '.webm':
    case '.mp3':
    case '.opus':
    case '.ogg':
      return true;
    default:
      return false;
  }
}

String pathBasedVideoId(String filePath) {
  final key = canonicalMusicLibraryPathKey(filePath);
  if (key.isEmpty) return 'local_file';
  return 'path_${key.hashCode.abs().toRadixString(36)}';
}

Future<String> stableYoutubeStoragePath(String rawPath) async {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return trimmed;
  if (await File(trimmed).exists()) return p.normalize(trimmed);
  try {
    final absolute = p.normalize(File(trimmed).absolute.path);
    if (await File(absolute).exists()) return absolute;
  } catch (_) {}
  return p.normalize(trimmed);
}

Future<({TrackItem track, int? durationMs})> _trackAndDurationFromFile(
  String path,
) async {
  final base = TrackItem.fromFilePath(path);
  try {
    if (pathUsesMetadataGodReader(path)) {
      final meta = await MetadataGod.readMetadata(file: path);
      final track = trackFromMetadataGod(base, meta);
      final ms = meta.durationMs;
      return (
        track: track,
        durationMs: ms != null && ms > 0 ? ms.round() : null,
      );
    }
    final track = await readAudioMetadata(base);
    return (track: track, durationMs: null);
  } catch (_) {
    return (track: base, durationMs: null);
  }
}

Future<bool> _youtubeAudioFileExists(String rawPath) async {
  if (await File(rawPath).exists()) return true;
  try {
    return await File(p.normalize(File(rawPath).absolute.path)).exists();
  } catch (_) {
    return false;
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
