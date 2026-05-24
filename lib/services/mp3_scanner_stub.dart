import 'mp3_scanner_types.dart';

Future<List<String>> scanMp3Files(
  String rootDir, {
  bool recursive = true,
}) async {
  return [];
}

Future<List<ScannedMp3File>> scanMp3FilesWithStats(
  String rootDir, {
  bool recursive = true,
}) async {
  return const <ScannedMp3File>[];
}

Future<List<ScannedMp3File>> collectMp3FilesMerged(List<String> roots) async =>
    const <ScannedMp3File>[];
