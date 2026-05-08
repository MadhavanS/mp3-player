class ScannedMp3File {
  const ScannedMp3File({
    required this.path,
    required this.lastModifiedMs,
    required this.fileSizeBytes,
  });

  final String path;
  final int lastModifiedMs;
  final int fileSizeBytes;
}
