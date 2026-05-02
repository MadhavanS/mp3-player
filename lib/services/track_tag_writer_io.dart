import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

enum AlbumArtEditKind { keep, replace, remove }

Uint8List _stripLeadingId3v2(Uint8List raw) {
  if (raw.length < 10) return raw;
  final tag = String.fromCharCodes(raw.sublist(0, 3));
  if (tag != 'ID3') return raw;
  final sizeBytes = raw.sublist(6, 10);
  final tagSize = (sizeBytes[3] & 0x7F) |
      ((sizeBytes[2] & 0x7F) << 7) |
      ((sizeBytes[1] & 0x7F) << 14) |
      ((sizeBytes[0] & 0x7F) << 21);
  final total = 10 + tagSize;
  if (total > raw.length) return raw;
  return Uint8List.sublistView(raw, total);
}

/// [Id3v4Writer] prepends a tag to the file as-is. If the file still starts with
/// an old ID3v2 block, the result would contain two headers and breaks tags /
/// playback. Strip v2 first, write into a temp file, then replace the original.
Future<void> _writeMp3Id3v2Safe(File original, Mp3Metadata metadata) async {
  final raw = await original.readAsBytes();
  final body = _stripLeadingId3v2(raw);
  final tmp = File(
    p.join(
      Directory.systemTemp.path,
      'mp3tag_${DateTime.now().microsecondsSinceEpoch}.mp3',
    ),
  );

  try {
    await tmp.writeAsBytes(body);
    Id3v4Writer().write(tmp, metadata);
    final out = await tmp.readAsBytes();
    await original.writeAsBytes(out, flush: true);
  } finally {
    try {
      if (tmp.existsSync()) {
        tmp.deleteSync();
      }
    } catch (_) {}
  }
}

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

  final metadata = readAllMetadata(file);

  metadata.setTitle(title.trim().isEmpty ? null : title.trim());
  metadata.setArtist(artist.trim().isEmpty ? null : artist.trim());
  metadata.setAlbum(album.trim().isEmpty ? null : album.trim());
  final g = genre.trim();
  if (g.isEmpty) {
    metadata.setGenres([]);
  } else {
    final parts = g
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    metadata.setGenres(parts);
  }

  switch (artEdit) {
    case AlbumArtEditKind.keep:
      break;
    case AlbumArtEditKind.remove:
      metadata.setPictures([]);
      break;
    case AlbumArtEditKind.replace:
      final bytes = newCoverBytes;
      if (bytes == null || bytes.isEmpty) {
        metadata.setPictures([]);
      } else {
        final mime = (newCoverMimeType != null && newCoverMimeType.isNotEmpty)
            ? newCoverMimeType
            : 'image/jpeg';
        metadata.setPictures([
          Picture(bytes, mime, PictureType.coverFront),
        ]);
      }
      break;
  }

  if (metadata is ApeMetadata) {
    throw UnsupportedError(
      'This file uses APE tags. Saving from this app is not supported yet.',
    );
  }

  if (metadata is Mp3Metadata) {
    await _writeMp3Id3v2Safe(file, metadata);
    return;
  }

  writeMetadata(file, metadata);
}
