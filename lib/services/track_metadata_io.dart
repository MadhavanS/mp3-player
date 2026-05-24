import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';

import '../models/track_item.dart';
import 'album_art_cache.dart';
import 'metadata_backend_config.dart';
import 'song_metadata_cache.dart';
import 'metadata_god_init_io.dart';
import 'metadata_god_reader_io.dart';

final Set<String> _metadataWarnedPaths = <String>{};

void _logMetadataSkipOnce(String path, Object error) {
  if (_metadataWarnedPaths.add(path)) {
    debugPrint(
      'readAudioMetadata: skipped unsupported metadata for "$path" ($error)',
    );
  }
}

TrackItem _trackFromMp3Metadata(TrackItem base, Mp3Metadata mp3) {
  Uint8List? art;
  if (mp3.pictures.isNotEmpty) {
    final raw = mp3.pictures.first.bytes;
    if (raw.isNotEmpty) art = raw;
  }

  String? primaryArtist = mp3.leadPerformer?.trim();
  if (primaryArtist == null || primaryArtist.isEmpty) {
    primaryArtist = mp3.bandOrOrchestra?.trim();
  }
  if (primaryArtist == null || primaryArtist.isEmpty) {
    primaryArtist = mp3.originalArtist?.trim();
  }

  String? genreStr;
  if (mp3.genres.isNotEmpty) {
    genreStr = mp3.genres.first;
  } else if (mp3.contentType != null && mp3.contentType!.trim().isNotEmpty) {
    genreStr = mp3.contentType!.trim();
  }

  return base.withEmbeddedMetadata(
    title: mp3.songName?.trim(),
    artist: primaryArtist,
    album: mp3.album?.trim(),
    genre: genreStr,
    albumArtBytes: art,
    replaceGenreFromFile: true,
    replaceAlbumArtFromFile: true,
  );
}

/// Pure-Dart reader (existing path). Kept for fallback and MP3 TPE1 accuracy.
Future<TrackItem> _readAudioMetadataWithDartReader(TrackItem base) async {
  final path = base.filePath;
  if (path == null || path.isEmpty) return base;

  final file = File(path);
  if (!await file.exists()) return base;

  final stopwatch = kMetadataReadTimingLogs ? (Stopwatch()..start()) : null;

  try {
    if (path.toLowerCase().endsWith('.mp3')) {
      final raf = file.openSync();
      try {
        if (MP3Parser.canUserParser(raf)) {
          final mp3 = MP3Parser(fetchImage: true).parse(raf);
          stopwatch?.stop();
          if (kMetadataReadTimingLogs) {
            debugPrint(
              'audio_metadata_reader read ${stopwatch!.elapsedMilliseconds}ms: $path',
            );
          }
          return _trackFromMp3Metadata(base, mp3);
        }
        _logMetadataSkipOnce(path, 'NoMetadataParserException');
        return base;
      } finally {
        try {
          raf.closeSync();
        } catch (_) {}
      }
    }

    final meta = readMetadata(file, getImage: true);

    Uint8List? art;
    if (meta.pictures.isNotEmpty) {
      final raw = meta.pictures.first.bytes;
      if (raw.isNotEmpty) art = raw;
    }

    var artist = meta.artist?.trim();
    if (artist == null || artist.isEmpty) {
      artist = meta.performers.isNotEmpty ? meta.performers.first.trim() : null;
    }

    String? genreStr;
    if (meta.genres.isNotEmpty) {
      genreStr = meta.genres.first;
    }

    stopwatch?.stop();
    if (kMetadataReadTimingLogs) {
      debugPrint(
        'audio_metadata_reader read ${stopwatch!.elapsedMilliseconds}ms: $path',
      );
    }

    return base.withEmbeddedMetadata(
      title: meta.title?.trim(),
      artist: artist,
      album: meta.album?.trim(),
      genre: genreStr,
      albumArtBytes: art,
      replaceGenreFromFile: true,
      replaceAlbumArtFromFile: true,
    );
  } catch (e) {
    _logMetadataSkipOnce(path, e);
    return base;
  }
}

Future<TrackItem> _finalizeMetadataRead(TrackItem result) async {
  final path = result.filePath?.trim();
  final art = result.albumArtBytes;
  if (path != null &&
      path.isNotEmpty &&
      art != null &&
      art.isNotEmpty) {
    await primeAlbumArtDiskCache(path, art);
    await SongMetadataCache.markArtDiskCachedForPath(path);
  }
  return result;
}

/// Cover bytes only (warmup). Still reads the file; skips tag merge overhead.
Future<Uint8List?> readCoverBytesOnly(String filePath) async {
  final path = filePath.trim();
  if (path.isEmpty) return null;

  if (kUseMetadataGod && metadataGodAvailable) {
    final base = TrackItem.fromFilePath(path);
    final fromGod = await tryReadAudioMetadataWithGod(base);
    final art = fromGod?.albumArtBytes;
    if (art != null && art.isNotEmpty) return art;
  }

  return _readCoverBytesWithDartReader(path);
}

Future<Uint8List?> _readCoverBytesWithDartReader(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;

  try {
    if (path.toLowerCase().endsWith('.mp3')) {
      final raf = file.openSync();
      try {
        if (MP3Parser.canUserParser(raf)) {
          final mp3 = MP3Parser(fetchImage: true).parse(raf);
          if (mp3.pictures.isNotEmpty) {
            final raw = mp3.pictures.first.bytes;
            if (raw.isNotEmpty) return raw;
          }
        }
      } finally {
        try {
          raf.closeSync();
        } catch (_) {}
      }
    }

    final meta = readMetadata(file, getImage: true);
    if (meta.pictures.isNotEmpty) {
      final raw = meta.pictures.first.bytes;
      if (raw.isNotEmpty) return raw;
    }
  } catch (e) {
    _logMetadataSkipOnce(path, e);
  }
  return null;
}

/// Reads embedded tags + cover. On this branch tries [metadata_god] first when
/// [kUseMetadataGod] is true, then falls back to [audio_metadata_reader].
Future<TrackItem> readAudioMetadata(TrackItem base) async {
  if (kUseMetadataGod && metadataGodAvailable) {
    final fromGod = await tryReadAudioMetadataWithGod(base);
    if (fromGod != null) return _finalizeMetadataRead(fromGod);
  }
  return _finalizeMetadataRead(await _readAudioMetadataWithDartReader(base));
}
