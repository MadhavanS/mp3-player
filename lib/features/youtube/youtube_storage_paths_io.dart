import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'youtube_settings_store.dart';

/// Default app-local folder: Documents/youtube_audio.
Future<String> defaultYoutubeAudioStorageDirectoryPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.normalize(p.join(docs.path, 'youtube_audio'));
}

/// Active folder for new YouTube downloads (custom or default).
Future<String> youtubeAudioStorageDirectoryPath() async {
  final custom = await YoutubeSettingsStore.loadCustomStoragePath();
  if (custom != null && custom.isNotEmpty) {
    return p.normalize(custom);
  }
  return defaultYoutubeAudioStorageDirectoryPath();
}

Future<bool> usesDefaultYoutubeAudioStoragePath() async {
  final custom = await YoutubeSettingsStore.loadCustomStoragePath();
  return custom == null || custom.isEmpty;
}

/// Ensures the active YouTube audio directory exists and returns its path.
Future<String> ensureYoutubeAudioStorageDirectory() async {
  final path = await youtubeAudioStorageDirectoryPath();
  await Directory(path).create(recursive: true);
  return path;
}

Future<bool> isYoutubeStoragePathInAppSandbox(String path) async {
  final norm = p.normalize(path);
  final roots = await Future.wait([
    getApplicationDocumentsDirectory(),
    getApplicationSupportDirectory(),
    getTemporaryDirectory(),
  ]);
  for (final root in roots) {
    final base = p.normalize(root.path);
    if (norm == base || p.isWithin(base, norm)) {
      return true;
    }
  }
  return false;
}

Future<bool> probeYoutubeStorageDirectoryWritable(String path) async {
  try {
    final dir = Directory(path);
    await dir.create(recursive: true);
    final probe = File(p.join(path, '.madplayer_youtube_write_probe'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}
