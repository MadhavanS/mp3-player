import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-local folder where downloaded YouTube audio files are stored.
Future<String> youtubeAudioStorageDirectoryPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.normalize(p.join(docs.path, 'youtube_audio'));
}

/// Ensures the YouTube audio directory exists and returns its path.
Future<String> ensureYoutubeAudioStorageDirectory() async {
  final path = await youtubeAudioStorageDirectoryPath();
  await Directory(path).create(recursive: true);
  return path;
}
