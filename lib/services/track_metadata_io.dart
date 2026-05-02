import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';

import '../models/track_item.dart';

/// Reads embedded ID3 (and similar) tags + cover art using pure Dart (works well on Android).
Future<TrackItem> readAudioMetadata(TrackItem base) async {
  final path = base.filePath;
  if (path == null || path.isEmpty) return base;

  final file = File(path);
  if (!await file.exists()) return base;

  try {
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

    final genre = meta.genres.isNotEmpty ? meta.genres.first : null;

    return base.withEmbeddedMetadata(
      title: meta.title?.trim(),
      artist: artist,
      album: meta.album?.trim(),
      genre: genre,
      albumArtBytes: art,
    );
  } catch (e, st) {
    debugPrint('readAudioMetadata: $e\n$st');
    return base;
  }
}
