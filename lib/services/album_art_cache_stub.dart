import 'dart:typed_data';

import '../models/track_item.dart';

Uint8List? cachedAlbumArtSync(TrackItem track, {int maxDimension = 512}) =>
    track.albumArtBytes;

Future<Uint8List?> cachedAlbumArt(TrackItem track, {int maxDimension = 512}) {
  return Future<Uint8List?>.value(track.albumArtBytes);
}

void evictCachedAlbumArt(TrackItem track) {}

Future<void> evictPathAlbumArtCaches(String filePath) async {}

void evictPathAlbumArtMemory(String filePath) {}

Future<void> prewarmPathAlbumArtForPaths(
  Iterable<String> filePaths, {
  int maxCount = 15,
  int maxDimension = 192,
}) async {}

void prewarmAlbumArtCache(
  Iterable<TrackItem> tracks, {
  int maxCount = 50,
  int maxDimension = 512,
}) {}

Uint8List? cachedAlbumArtForPathSync(
  String filePath, {
  int maxDimension = 512,
}) =>
    null;

Uint8List? cachedAlbumArtForPathAnyDimensionSync(
  String filePath, {
  int targetDimension = 512,
}) =>
    null;

Future<Uint8List?> cachedAlbumArtForPathAnyDimension(
  String filePath, {
  int targetDimension = 512,
}) =>
    Future<Uint8List?>.value(null);

Future<bool> hasAlbumArtDiskCacheAnyDimension(String filePath) async =>
    false;

Future<Uint8List?> cachedAlbumArtForPath(
  String filePath, {
  int maxDimension = 512,
}) =>
    Future<Uint8List?>.value(null);

Future<bool> hasAlbumArtDiskCache(
  String filePath, {
  int maxDimension = 512,
}) async =>
    false;

Future<Set<String>> pathKeysWithDiskAlbumArt(
  Iterable<String> filePaths, {
  int maxDimension = 512,
}) async =>
    const <String>{};

Future<void> primeAlbumArtDiskCache(
  String filePath,
  Uint8List raw, {
  int maxDimension = 512,
}) async {}

