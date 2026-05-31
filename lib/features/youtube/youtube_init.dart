import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog/youtube_library_catalog.dart';
import 'storage/youtube_track_store.dart';
import 'thumbnail/youtube_thumbnail_cache.dart';

/// Initializes YouTube storage and reloads the downloaded library catalog.
Future<void> initYoutubeFeature() async {
  if (kIsWeb) return;
  await YoutubeTrackStore.instance.init();
  await YoutubeLibraryCatalog.instance.reload();
}

/// Deletes YouTube downloads, thumbnails, and Isar index (factory reset).
Future<void> wipeYoutubeLocalData() async {
  if (kIsWeb) return;
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
    final docs = await getApplicationDocumentsDirectory();
    final ytDir = Directory('${docs.path}/youtube_audio');
    if (await ytDir.exists()) {
      await ytDir.delete(recursive: true);
    }
  } catch (e, st) {
    debugPrint('wipeYoutubeLocalData files: $e\n$st');
  }
  await YoutubeLibraryCatalog.instance.reload();
}
