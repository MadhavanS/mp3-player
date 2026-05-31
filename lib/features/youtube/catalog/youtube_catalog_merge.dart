import 'package:flutter/foundation.dart';

import '../../../models/track_item.dart';
import '../../../services/music_library_path_key.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_settings_store.dart';

/// Removes YouTube download rows from a library scan list.
List<TrackItem> stripYoutubeTracksFromCatalog(List<TrackItem> tracks) {
  return tracks
      .where((t) => !isYoutubeDownloadStoragePath(t.filePath ?? ''))
      .toList(growable: false);
}

/// Appends downloaded YouTube tracks when the merge setting is enabled.
Future<List<TrackItem>> applyYoutubeCatalogMerge(
  List<TrackItem> baseCatalog,
) async {
  if (kIsWeb) return stripYoutubeTracksFromCatalog(baseCatalog);

  final base = stripYoutubeTracksFromCatalog(baseCatalog);
  if (!await YoutubeSettingsStore.loadMergeIntoSongs()) return base;

  final yt = await YoutubeTrackStore.instance.getAllAsTrackItems();
  if (yt.isEmpty) return base;
  return [...base, ...yt];
}
