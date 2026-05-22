import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where Online search “Save audio” files are written.
class YoutubeDownloadSettingsStore {
  YoutubeDownloadSettingsStore._();

  static const _customDirKey = 'youtube_download_dir_v1';
  static const defaultSubdir = 'youtube_audio';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// User override, or null when using the app default folder.
  static Future<String?> loadCustomDirectory() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customDirKey)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> saveCustomDirectory(String path) async {
    if (kIsWeb) return;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customDirKey, trimmed);
    revision.value++;
  }

  static Future<void> clearCustomDirectory() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customDirKey);
    revision.value++;
  }

  /// App documents / [defaultSubdir] when no custom path is set.
  static Future<String> defaultDirectoryPath() async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, defaultSubdir);
  }

  /// Resolved folder used for new downloads (creates it if missing).
  static Future<Directory> resolveDownloadsDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('YouTube downloads are not supported on web');
    }
    final custom = await loadCustomDirectory();
    final path = (custom != null && custom.isNotEmpty)
        ? custom
        : await defaultDirectoryPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> loadEffectivePathLabel() async {
    if (kIsWeb) return 'Not available on web';
    final custom = await loadCustomDirectory();
    if (custom != null && custom.isNotEmpty) return custom;
    return await defaultDirectoryPath();
  }

  static Future<bool> usesDefaultDirectory() async {
    final custom = await loadCustomDirectory();
    return custom == null || custom.isEmpty;
  }
}
