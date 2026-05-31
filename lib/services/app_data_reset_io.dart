import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/notification_art_uri.dart';
import '../platform/android_home_widget_bridge.dart';
import 'album_art_cache.dart';
import 'folder_count_cache.dart';
import 'song_metadata_cache.dart';

/// Deletes all on-device MadPlayer data: preferences, metadata DB, art caches,
/// notification art, and Android home-widget state.
Future<void> wipeAllLocalAppData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: SharedPreferences.clear failed: $e\n$st');
  }

  try {
    await SongMetadataCache.clearAll();
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: metadata cache clear failed: $e\n$st');
  }

  try {
    await clearAllAlbumArtDiskCache();
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: album art cache clear failed: $e\n$st');
  }

  try {
    await clearAllNotificationArtCache();
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: notification art clear failed: $e\n$st');
  }

  try {
    final support = await getApplicationSupportDirectory();
    await _deleteDirectoryIfExists(Directory(p.join(support.path, 'isar')));
    await _deleteDirectoryIfExists(
      Directory(p.join(support.path, 'isar_mp3_player_db')),
    );
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: support dir cleanup failed: $e\n$st');
  }

  try {
    final cache = await getApplicationCacheDirectory();
    await _deleteDirectoryContents(cache);
  } catch (e, st) {
    debugPrint('wipeAllLocalAppData: cache dir cleanup failed: $e\n$st');
  }

  FolderCountCache.instance.clear();

  if (Platform.isAndroid) {
    try {
      await AndroidHomeWidgetBridge.clearWidgetData();
    } catch (e, st) {
      debugPrint('wipeAllLocalAppData: widget clear failed: $e\n$st');
    }
  }
}

Future<void> _deleteDirectoryIfExists(Directory dir) async {
  if (!await dir.exists()) return;
  await dir.delete(recursive: true);
}

Future<void> _deleteDirectoryContents(Directory dir) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list()) {
    try {
      await entity.delete(recursive: true);
    } catch (_) {}
  }
}
