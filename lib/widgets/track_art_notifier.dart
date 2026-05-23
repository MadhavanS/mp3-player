import 'package:flutter/foundation.dart';

import '../audio/player_controller.dart';
import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../services/music_library_path_key.dart';

/// Loads list-row album art once per tile; avoids [FutureBuilder] on parent rebuilds.
class TrackArtNotifier extends ChangeNotifier {
  Uint8List? _art;
  bool _loading = false;

  Uint8List? get art => _art;
  bool get isLoading => _loading;

  /// Synchronous art already available (embedded tags, hot LRU, memory cache).
  Uint8List? resolveSyncArt(TrackItem track, PlayerController player, int maxDimension) {
    final embedded = track.albumArtBytes;
    if (embedded != null && embedded.isNotEmpty) {
      return cachedAlbumArtSync(track, maxDimension: maxDimension) ?? embedded;
    }
    final path = track.filePath?.trim() ?? '';
    if (path.isEmpty) return null;
    final hot = player.hotArtBytesForPath(path);
    if (hot != null && hot.isNotEmpty) return hot;
    return cachedAlbumArtForPathSync(path, maxDimension: maxDimension);
  }

  Future<void> load(
    TrackItem track,
    PlayerController player, {
    int maxDimension = 192,
  }) async {
    if (_art != null || _loading) return;

    final sync = resolveSyncArt(track, player, maxDimension);
    if (sync != null && sync.isNotEmpty) {
      _art = sync;
      notifyListeners();
      return;
    }

    final path = track.filePath?.trim() ?? '';
    if (path.isEmpty) return;

    _loading = true;
    try {
      Uint8List? bytes;
      final embedded = track.albumArtBytes;
      if (embedded != null && embedded.isNotEmpty) {
        bytes = await cachedAlbumArt(track, maxDimension: maxDimension);
      } else {
        bytes = await cachedAlbumArtForPath(path, maxDimension: maxDimension);
      }
      if (bytes != null && bytes.isNotEmpty) {
        player.promoteArtBytesForPath(path, bytes);
        _art = bytes;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _art = null;
    _loading = false;
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}

String trackArtPathKey(TrackItem track) {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return '';
  return canonicalMusicLibraryPathKey(path);
}
