import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart' show ParserTag;
import 'package:path/path.dart' as p;

import 'ape_tag_writer_io.dart';
import 'track_metadata.dart';

enum AlbumArtEditKind { keep, replace, remove }

String _coverMimeFromBytes(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  return 'image/jpeg';
}

bool _parserTagHasPictures(ParserTag metadata) {
  return switch (metadata) {
    Mp3Metadata m => m.pictures.isNotEmpty,
    VorbisMetadata m => m.pictures.isNotEmpty,
    ApeMetadata m => m.pictures.isNotEmpty,
    Mp4Metadata m => m.picture != null,
    RiffMetadata m => m.pictures.isNotEmpty,
  };
}

/// [MP3Parser.parse] always closes [reader] before returning — never close again.
Future<Mp3Metadata?> _tryParseMp3File(
  File file, {
  required bool fetchImage,
}) async {
  final raf = await file.open();
  if (!MP3Parser.canUserParser(raf)) {
    try {
      await raf.close();
    } catch (_) {}
    return null;
  }
  return MP3Parser(fetchImage: fetchImage).parse(raf);
}

/// Matches [readAudioMetadata] parser choice so tag writes do not fail when
/// library reads used [metadata_god] or skipped broken embedded art.
Future<ParserTag> _readParserTagForWrite(
  File file, {
  required bool fetchImages,
}) async {
  Future<ParserTag> attempt(bool images) async {
    if (await fileHasApeFooter(file)) {
      return readAllMetadata(file, getImage: images);
    }

    if (p.extension(file.path).toLowerCase() == '.mp3') {
      final mp3 = await _tryParseMp3File(file, fetchImage: images);
      if (mp3 != null) return mp3;
    }

    return readAllMetadata(file, getImage: images);
  }

  try {
    return await attempt(fetchImages);
  } on MetadataParserException {
    if (fetchImages) {
      return await attempt(false);
    }
    rethrow;
  }
}

Future<ParserTag> _readParserTagForWriteWithFallback(
  File file, {
  required bool fetchImages,
}) async {
  try {
    return await _readParserTagForWrite(file, fetchImages: fetchImages);
  } on MetadataParserException {
    final hasApe = await fileHasApeFooter(file);
    if (!hasApe && p.extension(file.path).toLowerCase() == '.mp3') {
      return Mp3Metadata();
    }
    rethrow;
  }
}

Future<void> _attachExistingCoverIfNeeded(
  ParserTag metadata,
  String filePath,
) async {
  if (_parserTagHasPictures(metadata)) return;

  final art = await readCoverBytesOnly(filePath);
  if (art == null || art.isEmpty) return;

  metadata.setPictures([
    Picture(art, _coverMimeFromBytes(art), PictureType.coverFront),
  ]);
}

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
    final writtenLen = await original.length();
    if (writtenLen != out.length) {
      throw StateError(
        'Write verification failed (file size $writtenLen vs $out). '
        'On Android, grant "All files access" in Settings → Apps → MadPlayer → Permissions.',
      );
    }
    if (out.length >= 3 &&
        String.fromCharCodes(out.sublist(0, 3)) != 'ID3') {
      throw StateError('Write verification failed: missing ID3 header.');
    }
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
  String composer = '',
  AlbumArtEditKind artEdit = AlbumArtEditKind.keep,
  Uint8List? newCoverBytes,
  String? newCoverMimeType,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw StateError('File not found.');
  }

  final needExistingArt = artEdit == AlbumArtEditKind.keep;
  final metadata = await _readParserTagForWriteWithFallback(
    file,
    fetchImages: needExistingArt,
  );

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

  final c = composer.trim();
  switch (metadata) {
    case Mp3Metadata m:
      m.composer = c.isEmpty ? null : c;
    case VorbisMetadata m:
      m.composer = c.isEmpty ? [] : [c];
    case ApeMetadata m:
      m.composer = c.isEmpty ? null : c;
    case Mp4Metadata():
    case RiffMetadata():
      break;
  }

  switch (artEdit) {
    case AlbumArtEditKind.keep:
      await _attachExistingCoverIfNeeded(metadata, filePath);
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

  if (metadata is Mp3Metadata) {
    final m = metadata;
    // [readMetadata] prefers TPE2 (album artist) over TPE1; stale TPE2 would mask edits.
    m.bandOrOrchestra = null;
    // Writer uses [contentType] as TCON when [genres] is empty — clear stale genre.
    m.contentType = null;
  }

  if (metadata is ApeMetadata) {
    await ApeTagWriter.write(file, metadata);
    await _syncId3v2AfterApeWrite(file, metadata);
    return;
  }

  if (metadata is Mp3Metadata) {
    await _writeMp3Id3v2Safe(file, metadata);
    return;
  }

  writeMetadata(file, metadata);
}

/// MP3+APE files often keep a parallel ID3v2 block at the front. After an APE
/// rewrite, mirror the same values into ID3v2 so players and [metadata_god] agree.
Future<void> _syncId3v2AfterApeWrite(File file, ApeMetadata ape) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    if (!MP3Parser.hasID3v2Tag(raf)) return;
  } catch (_) {
    return;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }

  Mp3Metadata mp3;
  try {
    final parsed = await _tryParseMp3File(
      file,
      fetchImage: ape.pictures.isNotEmpty,
    );
    if (parsed == null) return;
    mp3 = parsed;
  } catch (_) {
    return;
  }

  mp3.setTitle(ape.title);
  mp3.setArtist(ape.artist);
  mp3.setAlbum(ape.album);
  mp3.setGenres(List<String>.from(ape.genres));
  final comp = ape.composer?.trim() ?? '';
  mp3.composer = comp.isEmpty ? null : comp;
  mp3.setPictures(List<Picture>.from(ape.pictures));
  mp3.bandOrOrchestra = null;
  mp3.contentType = null;

  await _writeMp3Id3v2Safe(file, mp3);
}
