import 'dart:typed_data';

import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../services/music_library_path_key.dart';
import 'library_catalog.dart';
import 'player_controller.dart';

/// Resolves cover bytes for list, mini player, notification, and widget.
///
/// Order: hot LRU → path disk (any cached dimension) → [TrackItem.albumArtBytes].
Future<Uint8List?> resolveAlbumArtBytes(
  TrackItem track, {
  PlayerController? player,
  LibraryCatalog? catalog,
  int targetDimension = 512,
}) async {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return null;
  final pathKey = canonicalMusicLibraryPathKey(path);

  if (player != null) {
    final hot = player.hotArtBytesForPath(path);
    if (hot != null && hot.isNotEmpty) return hot;
  } else if (catalog != null) {
    final hot = catalog.hotArtBytesForPathKey(pathKey);
    if (hot != null && hot.isNotEmpty) return hot;
  }

  final disk = await cachedAlbumArtForPathAnyDimension(
    path,
    targetDimension: targetDimension,
  );
  if (disk != null && disk.isNotEmpty) {
    player?.promoteArtBytesForPath(path, disk);
    catalog?.promoteArtBytes(pathKey, disk);
    return disk;
  }

  final embedded = track.albumArtBytes;
  if (embedded != null && embedded.isNotEmpty) return embedded;
  return null;
}

/// Synchronous resolver for build paths (hot LRU + in-memory disk cache).
Uint8List? resolveAlbumArtBytesSync(
  TrackItem track,
  PlayerController player, {
  int targetDimension = 512,
}) {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return null;

  final hot = player.hotArtBytesForPath(path);
  if (hot != null && hot.isNotEmpty) return hot;

  final disk = cachedAlbumArtForPathAnyDimensionSync(
    path,
    targetDimension: targetDimension,
  );
  if (disk != null && disk.isNotEmpty) return disk;

  final embedded = track.albumArtBytes;
  if (embedded != null && embedded.isNotEmpty) return embedded;
  return null;
}
