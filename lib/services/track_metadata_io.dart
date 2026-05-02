import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';

import '../models/track_item.dart';

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
  );
}

/// Reads embedded ID3 (and similar) tags + cover art using pure Dart (works well on Android).
Future<TrackItem> readAudioMetadata(TrackItem base) async {
  final path = base.filePath;
  if (path == null || path.isEmpty) return base;

  final file = File(path);
  if (!await file.exists()) return base;

  try {
    // Prefer real ID3 frames for .mp3 so we match what we write. Package
    // `readMetadata` checks APE before MP3 and maps artist as TPE2 before TPE1,
    // which hides edits saved to TPE1 (lead performer).
    if (path.toLowerCase().endsWith('.mp3')) {
      final raf = file.openSync();
      try {
        if (MP3Parser.canUserParser(raf)) {
          final mp3 = MP3Parser(fetchImage: true).parse(raf);
          return _trackFromMp3Metadata(base, mp3);
        }
      } finally {
        // [MP3Parser.parse] closes [raf] when it runs; avoid double-close.
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

    return base.withEmbeddedMetadata(
      title: meta.title?.trim(),
      artist: artist,
      album: meta.album?.trim(),
      genre: genreStr,
      albumArtBytes: art,
      replaceGenreFromFile: true,
    );
  } catch (e, st) {
    debugPrint('readAudioMetadata: $e\n$st');
    return base;
  }
}
