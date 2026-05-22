import 'track_item.dart';

enum YoutubeDownloadJobState {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// One YouTube audio save in the download queue.
class YoutubeDownloadJob {
  YoutubeDownloadJob({
    required this.track,
    required this.videoId,
  });

  final TrackItem track;
  final String videoId;
  YoutubeDownloadJobState state = YoutubeDownloadJobState.queued;
  double? progress;
  String status = 'Queued';
  bool cancelled = false;
  bool paused = false;

  bool get isActive =>
      state == YoutubeDownloadJobState.queued ||
      state == YoutubeDownloadJobState.downloading ||
      state == YoutubeDownloadJobState.paused;
}
