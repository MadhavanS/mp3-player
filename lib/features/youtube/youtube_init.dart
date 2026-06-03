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

/// Opens YouTube persistence only (fast; safe during app bootstrap).
Future<void> initYoutubeStorage() async {
  if (kIsWeb) return;
  await YoutubeTrackStore.instance.init();
}

/// Notifications, folder scan, and pending downloads (defer until after first UI).
Future<void> initYoutubeFeatureHeavy() async {
  if (kIsWeb) return;
  await YoutubeDownloadNotifications.init();
  await YoutubeLibraryCatalog.instance.reload();
  await YoutubeDownloadManager.instance.resumePendingDownloads();
}

/// Full YouTube init (storage + heavy). Prefer [initYoutubeStorage] at boot.
Future<void> initYoutubeFeature() async {
  await initYoutubeStorage();
  await initYoutubeFeatureHeavy();
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
