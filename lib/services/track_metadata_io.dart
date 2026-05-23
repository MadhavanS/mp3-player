import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';

import '../models/track_item.dart';

final Set<String> _metadataWarnedPaths = <String>{};

void _logMetadataSkipOnce(String path, Object error) {
  if (_metadataWarnedPaths.add(path)) {
    debugPrint(
      'readAudioMetadata: skipped unsupported metadata for "$path" ($error)',
    );
  }
}

/// Tag fields read off the UI thread ([compute]).
class EmbeddedFileMetadata {
  const EmbeddedFileMetadata({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.albumArtBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final Uint8List? albumArtBytes;
}

/// Top-level entry for [compute] — synchronous disk + ID3 parse (never on UI thread).
EmbeddedFileMetadata? readEmbeddedFileMetadataIsolate(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;

  try {
    if (path.toLowerCase().endsWith('.mp3')) {
      final raf = file.openSync();
      try {
        if (!MP3Parser.canUserParser(raf)) return null;
        final mp3 = MP3Parser(fetchImage: true).parse(raf);

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
        } else if (mp3.contentType != null &&
            mp3.contentType!.trim().isNotEmpty) {
          genreStr = mp3.contentType!.trim();
        }

        return EmbeddedFileMetadata(
          title: mp3.songName?.trim(),
          artist: primaryArtist,
          album: mp3.album?.trim(),
          genre: genreStr,
          albumArtBytes: art,
        );
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

    return EmbeddedFileMetadata(
      title: meta.title?.trim(),
      artist: artist,
      album: meta.album?.trim(),
      genre: genreStr,
      albumArtBytes: art,
    );
  } catch (_) {
    return null;
  }
}

TrackItem _applyEmbeddedPayload(TrackItem base, EmbeddedFileMetadata payload) {
  return base.withEmbeddedMetadata(
    title: payload.title,
    artist: payload.artist,
    album: payload.album,
    genre: payload.genre,
    albumArtBytes: payload.albumArtBytes,
    replaceGenreFromFile: true,
    replaceAlbumArtFromFile: true,
  );
}

/// Reads embedded ID3 (and similar) tags + cover art using pure Dart (works well on Android).
Future<TrackItem> readAudioMetadata(TrackItem base) async {
  final path = base.filePath?.trim();
  if (path == null || path.isEmpty) return base;

  if (!await File(path).exists()) return base;

  try {
    final payload = await compute(readEmbeddedFileMetadataIsolate, path);
    if (payload == null) {
      _logMetadataSkipOnce(path, 'NoMetadataParserException');
      return base;
    }
    return _applyEmbeddedPayload(base, payload);
  } catch (e) {
    _logMetadataSkipOnce(path, e);
    return base;
  }
}
