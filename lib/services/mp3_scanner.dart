import 'mp3_scanner_stub.dart'
    if (dart.library.io) 'mp3_scanner_io.dart'
    as impl;
import 'mp3_scanner_types.dart';

/// Lists `.mp3` paths under [rootDir]. On web, returns an empty list (no `dart:io`).
Future<List<String>> scanMp3Files(String rootDir, {bool recursive = true}) =>
    impl.scanMp3Files(rootDir, recursive: recursive);

/// Lists `.mp3` files with last-modified timestamps for diff-based background sync.
Future<List<ScannedMp3File>> scanMp3FilesWithStats(
  String rootDir, {
  bool recursive = true,
}) => impl.scanMp3FilesWithStats(rootDir, recursive: recursive);
