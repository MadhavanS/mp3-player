import 'dart:typed_data';

import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../services/album_art_dimensions.dart';
import '../services/music_library_path_key.dart';
import 'library_catalog.dart';
import 'player_controller.dart';

/// Resolves cover bytes for list, mini player, notification, and widget.
///
/// Order: hot LRU (thumbnails only) → path disk (any cached dimension) → embedded.
Future<Uint8List?> resolveAlbumArtBytes(
  TrackItem track, {
  PlayerController? player,
  LibraryCatalog? catalog,
  int targetDimension = kAlbumArtPrimeDimension,
}) async {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return null;
  final pathKey = canonicalMusicLibraryPathKey(path);
  final target = clampAlbumArtDimension(targetDimension);
  final useHot = albumArtTargetUsesHotLru(target);

  if (useHot) {
    if (player != null) {
      final hot = player.hotArtBytesForPath(path, minPixelSize: target);
      if (hot != null && hot.isNotEmpty) return hot;
    } else if (catalog != null) {
      final hot = catalog.hotArtBytesForPathKey(pathKey, minPixelSize: target);
      if (hot != null && hot.isNotEmpty) return hot;
    }
  }

  final disk = await cachedAlbumArtForPathAnyDimension(
    path,
    targetDimension: target,
  );
  if (disk != null && disk.isNotEmpty) {
    if (useHot) {
      player?.promoteArtBytesForPath(path, disk, pixelSize: target);
      catalog?.promoteArtBytes(pathKey, disk, pixelSize: target);
    }
    return disk;
  }

  final embedded = track.albumArtBytes;
  if (embedded != null && embedded.isNotEmpty) {
    return cachedAlbumArt(track, maxDimension: target);
  }
  return null;
}

/// Synchronous resolver for build paths (hot LRU + in-memory disk cache).
Uint8List? resolveAlbumArtBytesSync(
  TrackItem track,
  PlayerController player, {
  int targetDimension = kAlbumArtPrimeDimension,
}) {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return null;
  final target = clampAlbumArtDimension(targetDimension);

  if (albumArtTargetUsesHotLru(target)) {
    final hot = player.hotArtBytesForPath(path, minPixelSize: target);
    if (hot != null && hot.isNotEmpty) return hot;
  }

  final disk = cachedAlbumArtForPathAnyDimensionSync(
    path,
    targetDimension: target,
  );
  if (disk != null && disk.isNotEmpty) return disk;

  final embedded = track.albumArtBytes;
  if (embedded != null && embedded.isNotEmpty) {
    return cachedAlbumArtSync(track, maxDimension: target) ?? embedded;
  }
  return null;
}
