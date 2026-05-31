import '../download/youtube_download_job.dart';

abstract final class YoutubeDownloadNotifications {
  static Future<void> init() async {}

  static Future<void> showActive(YoutubeDownloadJob job) async {}

  static Future<void> showComplete(String title) async {}

  static Future<void> showFailed(String title, String? error) async {}

  static Future<void> dismiss() async {}
}
