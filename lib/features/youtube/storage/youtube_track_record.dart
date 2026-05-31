import 'package:isar/isar.dart';

part 'youtube_track_record.g.dart';

@collection
class YoutubeTrackRecord {
  YoutubeTrackRecord();

  int id = 0;

  @Index(unique: true)
  late String videoId;

  late String title;
  late String artist;
  String? thumbnailUrl;
  String? localPath;
  int downloadedAtMs = 0;
  int fileSizeBytes = 0;
  int? durationMs;

  bool get isDownloaded => localPath != null && localPath!.trim().isNotEmpty;
}
