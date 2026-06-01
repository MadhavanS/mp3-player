import 'package:flutter/foundation.dart';

import '../../../audio/player_controller.dart';
import '../../../models/track_item.dart';
import '../storage/youtube_track_store.dart';
import 'youtube_catalog_merge.dart';

/// Downloaded YouTube tracks — separate from local MP3 [LibraryCatalog].
class YoutubeLibraryCatalog extends ChangeNotifier {
  YoutubeLibraryCatalog._();

  static final instance = YoutubeLibraryCatalog._();

  List<TrackItem> _tracks = const [];
  bool _loading = false;
  int _reloadGeneration = 0;

  List<TrackItem> get tracks => _tracks;
  bool get loading => _loading;

  Future<void> reload() async {
    final generation = ++_reloadGeneration;
    _loading = true;
    notifyListeners();

    final tracks = await YoutubeTrackStore.instance.getAllAsTrackItems();
    if (generation != _reloadGeneration) return;

    _tracks = tracks;
    _loading = false;
    notifyListeners();

    debugPrint('[YoutubeLibraryCatalog] loaded ${_tracks.length} tracks');
  }

  /// When merge-into-Songs is enabled, append downloads to [player]'s catalog.
  Future<void> mergeIntoMainCatalog(PlayerController player) async {
    final merged = await applyYoutubeCatalogMerge(
      stripYoutubeTracksFromCatalog(player.metadataLibrary),
    );
    player.setLibraryCatalog(merged);
  }
}
