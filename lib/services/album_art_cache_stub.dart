import 'dart:typed_data';

import '../models/track_item.dart';

Uint8List? cachedAlbumArtSync(TrackItem track, {int maxDimension = 512}) =>
    track.albumArtBytes;

Future<Uint8List?> cachedAlbumArt(TrackItem track, {int maxDimension = 512}) {
  return Future<Uint8List?>.value(track.albumArtBytes);
}

void evictCachedAlbumArt(TrackItem track) {}

void prewarmAlbumArtCache(
  Iterable<TrackItem> tracks, {
  int maxCount = 50,
  int maxDimension = 512,
}) {}

