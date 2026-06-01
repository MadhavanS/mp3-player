/// Synthetic playlist paths for streaming a YouTube video id through the player.
const String youtubeStreamPathPrefix = 'ytstream:';

bool isYoutubeStreamPath(String path) =>
    path.startsWith(youtubeStreamPathPrefix);

String youtubeStreamPathForVideoId(String videoId) =>
    '$youtubeStreamPathPrefix${videoId.trim()}';

String? youtubeVideoIdFromStreamPath(String path) {
  if (!isYoutubeStreamPath(path)) return null;
  final id = path.substring(youtubeStreamPathPrefix.length).trim();
  return id.isEmpty ? null : id;
}
