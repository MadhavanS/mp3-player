import '../../../models/track_item.dart';

/// Result of scanning the configured YouTube download folder on disk.
class YoutubeStorageScanResult {
  const YoutubeStorageScanResult({
    required this.directoryPath,
    required this.tracks,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.alreadyRegisteredCount = 0,
  });

  final String directoryPath;
  final List<TrackItem> tracks;
  final int importedCount;
  final int updatedCount;
  final int alreadyRegisteredCount;

  int get totalOnDisk => tracks.length;

  String get summaryLine {
    if (totalOnDisk == 0) {
      return 'No playable audio files found in this folder yet.';
    }
    final parts = <String>['$totalOnDisk track${totalOnDisk == 1 ? '' : 's'} in folder'];
    if (importedCount > 0) {
      parts.add('$importedCount newly added to library');
    }
    if (updatedCount > 0) {
      parts.add('$updatedCount updated');
    }
    return parts.join(' · ');
  }
}

Future<YoutubeStorageScanResult> scanYoutubeStorageFolder({
  String? directoryPath,
}) async =>
    YoutubeStorageScanResult(directoryPath: '', tracks: const []);
