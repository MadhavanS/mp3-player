import 'song_file_info_stub.dart'
    if (dart.library.io) 'song_file_info_io.dart' as impl;

class SongFileInfo {
  const SongFileInfo({
    required this.fileName,
    required this.folderPath,
    required this.sizeBytes,
  });

  final String fileName;
  final String folderPath;
  final int? sizeBytes;
}

Future<SongFileInfo> readSongFileInfo(String? filePath) =>
    impl.readSongFileInfo(filePath);
