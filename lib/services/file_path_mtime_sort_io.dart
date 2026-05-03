import 'dart:io';

Future<void> sortPathsByModifiedNewestFirst(List<String> paths) async {
  if (paths.length < 2) return;
  final modified = <String, DateTime>{};
  for (final path in paths) {
    try {
      modified[path] = (await File(path).stat()).modified;
    } catch (_) {
      modified[path] = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
  paths.sort((a, b) => modified[b]!.compareTo(modified[a]!));
}
