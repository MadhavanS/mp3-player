import 'dart:typed_data';

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
  throw UnsupportedError('Editing audio tags is not supported on this platform.');
}
