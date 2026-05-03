import 'track_file_delete_stub.dart' if (dart.library.io) 'track_file_delete_io.dart' as impl;

/// Deletes [path] from disk. Returns `null` if successful or missing file; otherwise an error hint.
Future<String?> deleteMusicFileOrError(String path) => impl.deleteMusicFileOrError(path);
