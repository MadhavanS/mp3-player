import 'song_file_info_stub.dart'
    if (dart.library.io) 'song_file_info_io.dart' as impl;

class SongFileInfo {
  const SongFileInfo({
    required this.fileName,
    required this.folderPath,
    required this.sizeBytes,
    required this.durationMs,
    required this.bitrateKbps,
    this.composer,
  });

  final String fileName;
  final String folderPath;
  final int? sizeBytes;
  final int? durationMs;
  final int? bitrateKbps;

  /// Embedded TCOM / COMPOSER tag, when present.
  final String? composer;
}

Future<SongFileInfo> readSongFileInfo(String? filePath) =>
    impl.readSongFileInfo(filePath);
