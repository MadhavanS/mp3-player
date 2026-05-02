import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
enum AlbumArtEditKind { keep, replace, remove }

Future<void> writeEmbeddedAudioTags({
  required String filePath,
  required String title,
  required String artist,
  required String album,
  required String genre,
  AlbumArtEditKind artEdit = AlbumArtEditKind.keep,
  Uint8List? newCoverBytes,
  String? newCoverMimeType,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw StateError('File not found.');
  }

  updateMetadata(file, (meta) {
    meta.setTitle(title.trim().isEmpty ? null : title.trim());
    meta.setArtist(artist.trim().isEmpty ? null : artist.trim());
    meta.setAlbum(album.trim().isEmpty ? null : album.trim());
    final g = genre.trim();
    if (g.isEmpty) {
      meta.setGenres([]);
    } else {
      final parts = g
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      meta.setGenres(parts);
    }

    switch (artEdit) {
      case AlbumArtEditKind.keep:
        break;
      case AlbumArtEditKind.remove:
        meta.setPictures([]);
        break;
      case AlbumArtEditKind.replace:
        final bytes = newCoverBytes;
        if (bytes == null || bytes.isEmpty) {
          meta.setPictures([]);
        } else {
          final mime = (newCoverMimeType != null && newCoverMimeType.isNotEmpty)
              ? newCoverMimeType
              : 'image/jpeg';
          meta.setPictures([
            Picture(bytes, mime, PictureType.coverFront),
          ]);
        }
        break;
    }
  });
}
