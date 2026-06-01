import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/track_item.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_storage_paths.dart';
import 'youtube_library_catalog.dart';
import 'youtube_storage_scan_stub.dart';

/// Scans the active download folder and registers playable files missing from Isar.
Future<YoutubeStorageScanResult> scanYoutubeStorageFolder({
  String? directoryPath,
}) async {
  final dirPath = p.normalize(
    directoryPath ?? await youtubeAudioStorageDirectoryPath(),
  );
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    return YoutubeStorageScanResult(directoryPath: dirPath, tracks: const []);
  }

  final store = YoutubeTrackStore.instance;
  var imported = 0;
  var alreadyRegistered = 0;
  final outTracks = <TrackItem>[];

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!isYoutubeStorageAudioExtension(entity.path)) continue;

    final path = await stableYoutubeStoragePath(entity.path);
    final hadRecord = await store.findByLocalPath(path);
    final record = await store.registerStorageFile(path);
    if (record == null) continue;

    if (hadRecord != null) {
      alreadyRegistered++;
    } else {
      imported++;
    }
    outTracks.add(trackItemFromYoutubeRecord(record));
  }

  outTracks.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );

  return YoutubeStorageScanResult(
    directoryPath: dirPath,
    tracks: outTracks,
    importedCount: imported,
    updatedCount: 0,
    alreadyRegisteredCount: alreadyRegistered,
  );
}
