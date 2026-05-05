import 'file_path_mtime_sort_stub.dart'
    if (dart.library.io) 'file_path_mtime_sort_io.dart' as impl;

/// Sort [paths] in place by filesystem last-modified time, newest first.
/// No-op on web / non-IO platforms.
Future<void> sortPathsByModifiedNewestFirst(List<String> paths) =>
    impl.sortPathsByModifiedNewestFirst(paths);
