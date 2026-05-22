import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Shared [YoutubeExplode] instance for online search and streaming.
final YoutubeExplode ytClient = YoutubeExplode();

void closeYoutubeClient() {
  try {
    ytClient.close();
  } catch (_) {}
}
