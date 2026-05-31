import 'package:isar/isar.dart';

part 'song_metadata_cache_row.g.dart';

@collection
class SongMetadataCacheRow {
  SongMetadataCacheRow();

  int id = 0;

  @Index(unique: true)
  late String path;

  String title = '';
  String artist = '';
  String album = '';
  String genres = '';
  List<int> artColorValues = const <int>[];

  /// Embedded cover art is not cached here — storing bytes as `List<int>` mapped Isar
  /// to longList (one long per byte) and crashed on large images; art loads on enrich.
  int fileSizeBytes = 0;
  int updatedAtMs = 0;

  /// Path-keyed album-art PNG exists under [album_art_cache] for current fingerprint.
  bool hasArtDiskCache = false;

  /// File mtime/size when [hasArtDiskCache] was set (must match [updatedAtMs]/[fileSizeBytes]).
  int artCachedForModifiedMs = 0;
  int artCachedForSizeBytes = 0;

  /// True when disk art flag matches the on-disk file fingerprint.
  bool get isArtCacheValid =>
      hasArtDiskCache &&
      artCachedForModifiedMs == updatedAtMs &&
      artCachedForSizeBytes == fileSizeBytes;

  bool hasReplayGainTrack = false;
  double replayGainTrackDb = 0;
  bool hasReplayGainAlbum = false;
  double replayGainAlbumDb = 0;
}
