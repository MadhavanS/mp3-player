import 'dart:io';

import 'package:flutter/foundation.dart';

import 'catalog/youtube_library_catalog.dart';
import 'catalog/youtube_storage_scan.dart';
import 'download/youtube_download_manager.dart';
import 'download/youtube_download_notifications.dart';
import 'download/youtube_download_queue_store.dart';
import 'storage/youtube_track_store.dart';
import 'thumbnail/youtube_thumbnail_cache.dart';
import 'youtube_settings_store.dart';
import 'youtube_storage_paths.dart';

/// Initializes YouTube storage and reloads the downloaded library catalog.
Future<void> initYoutubeFeature() async {
  if (kIsWeb) return;
  await YoutubeTrackStore.instance.init();
  await YoutubeDownloadNotifications.init();
  await YoutubeLibraryCatalog.instance.reload();
  await YoutubeDownloadManager.instance.resumePendingDownloads();
}

/// Deletes YouTube downloads, thumbnails, and Isar index (factory reset).
Future<void> wipeYoutubeLocalData() async {
  if (kIsWeb) return;

  List<String> filePaths = const [];
  try {
    final rows = await YoutubeTrackStore.instance.getAllDownloaded();
    filePaths = [
      for (final row in rows)
        if (row.localPath != null && row.localPath!.trim().isNotEmpty)
          row.localPath!.trim(),
    ];
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData list: $e\n$st');
  }

  try {
    await YoutubeDownloadQueueStore.clear();
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData queue: $e\n$st');
  }

  for (final path in filePaths) {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      debugPrint('wipeYoutubeLocalData file $path: $e\n$st');
    }
  }

  try {
    await YoutubeTrackStore.instance.clearAll();
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData store: $e\n$st');
  }
  try {
    await YoutubeThumbnailCache.instance.clearAll();
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData thumbs: $e\n$st');
  }
  try {
    final ytDir = Directory(await youtubeAudioStorageDirectoryPath());
    if (await ytDir.exists()) {
      await ytDir.delete(recursive: true);
    }
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData active dir: $e\n$st');
  }
  try {
    final defaultDir = Directory(await defaultYoutubeAudioStorageDirectoryPath());
    if (await defaultDir.exists()) {
      await defaultDir.delete(recursive: true);
    }
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData default dir: $e\n$st');
  }
  try {
    await YoutubeSettingsStore.clearCustomStoragePath();
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData settings: $e\n$st');
  }
  await YoutubeLibraryCatalog.instance.reload();
}
