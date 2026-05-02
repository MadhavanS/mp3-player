import 'mp3_scanner_stub.dart' if (dart.library.io) 'mp3_scanner_io.dart' as impl;

/// Lists `.mp3` paths under [rootDir]. On web, returns an empty list (no `dart:io`).
Future<List<String>> scanMp3Files(String rootDir, {bool recursive = true}) =>
    impl.scanMp3Files(rootDir, recursive: recursive);
