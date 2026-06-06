/// Canonical YouTube watch URL for a video id.
String youtubeWatchUrlForVideoId(String videoId) {
  final id = videoId.trim();
  if (id.isEmpty) return '';
  return 'https://www.youtube.com/watch?v=$id';
}

/// Default thumbnail when no bookmark/download record exists.
String youtubeDefaultThumbnailUrlForVideoId(String videoId) {
  final id = videoId.trim();
  if (id.isEmpty) return '';
  return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}
