import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import '../models/track_item.dart';
import 'metadata_backend_config.dart';

TrackItem trackFromMetadataGod(TrackItem base, Metadata meta) {
  Uint8List? art;
  final pic = meta.picture;
  if (pic != null && pic.data.isNotEmpty) {
    art = pic.data;
  }

  var artist = meta.artist?.trim();
  if (artist == null || artist.isEmpty) {
    artist = meta.albumArtist?.trim();
  }

  return base.withEmbeddedMetadata(
    title: meta.title?.trim(),
    artist: artist,
    album: meta.album?.trim(),
    genre: meta.genre?.trim(),
    albumArtBytes: art,
    replaceGenreFromFile: true,
    replaceAlbumArtFromFile: true,
  );
}

Future<TrackItem?> tryReadAudioMetadataWithGod(TrackItem base) async {
  final path = base.filePath?.trim();
  if (path == null || path.isEmpty) return null;
  if (!pathUsesMetadataGodReader(path)) return null;

  final stopwatch = kMetadataReadTimingLogs ? (Stopwatch()..start()) : null;
  try {
    final meta = await MetadataGod.readMetadata(file: path);
    stopwatch?.stop();
    if (kMetadataReadTimingLogs) {
      debugPrint(
        'metadata_god read ${stopwatch!.elapsedMilliseconds}ms: $path',
      );
    }
    return trackFromMetadataGod(base, meta);
  } catch (e, st) {
    stopwatch?.stop();
    if (kMetadataReadTimingLogs) {
      debugPrint('metadata_god failed ($path): $e\n$st');
    }
    return null;
  }
}
