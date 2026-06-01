import 'package:flutter/foundation.dart';

import '../../../audio/player_controller.dart';
import '../../../models/track_item.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_storage_paths.dart';
import 'youtube_catalog_merge.dart';
import 'youtube_storage_scan.dart';

/// Downloaded YouTube tracks — separate from local MP3 [LibraryCatalog].
class YoutubeLibraryCatalog extends ChangeNotifier {
  YoutubeLibraryCatalog._();

  static final instance = YoutubeLibraryCatalog._();

  List<TrackItem> _tracks = const [];
  bool _loading = false;
  int _reloadGeneration = 0;
  String? _storageDirectoryPath;
  String? _scanSummaryLine;

  List<TrackItem> get tracks => _tracks;
  bool get loading => _loading;
  String? get storageDirectoryPath => _storageDirectoryPath;
  String? get scanSummaryLine => _scanSummaryLine;

  /// Scans the configured download folder, then loads [tracks] from disk + index.
  Future<void> reload() async {
    final generation = ++_reloadGeneration;
    _loading = true;
    notifyListeners();

    List<TrackItem> tracks = const [];
    if (!kIsWeb) {
      try {
        final result = await scanYoutubeStorageFolder();
        if (generation != _reloadGeneration) return;
        _storageDirectoryPath = result.directoryPath;
        _scanSummaryLine = result.summaryLine;
        tracks = result.tracks;
      } catch (e, st) {
        debugPrint('[YoutubeLibraryCatalog] scan failed: $e\n$st');
        _storageDirectoryPath = await youtubeAudioStorageDirectoryPath();
        _scanSummaryLine = 'Could not read folder. Pull down to retry.';
      }
    }

    if (tracks.isEmpty) {
      tracks = await YoutubeTrackStore.instance.getAllAsTrackItems();
      if (generation != _reloadGeneration) return;
      if (_scanSummaryLine == null || _scanSummaryLine!.isEmpty) {
        _scanSummaryLine = tracks.isEmpty
            ? 'No playable audio files in folder.'
            : '${tracks.length} track${tracks.length == 1 ? '' : 's'}';
      }
      _storageDirectoryPath ??= await youtubeAudioStorageDirectoryPath();
    }

    if (generation != _reloadGeneration) return;

    _tracks = tracks;
    _loading = false;
    notifyListeners();

    debugPrint(
      '[YoutubeLibraryCatalog] loaded ${_tracks.length} tracks '
      'from ${_storageDirectoryPath ?? "?"}',
    );
  }

  /// When merge-into-Songs is enabled, append downloads to [player]'s catalog.
  Future<void> mergeIntoMainCatalog(PlayerController player) async {
    final merged = await applyYoutubeCatalogMerge(
      stripYoutubeTracksFromCatalog(player.metadataLibrary),
    );
    player.setLibraryCatalog(merged);
  }
}
