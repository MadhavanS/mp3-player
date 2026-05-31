/// Parses a YouTube video id from a downloaded file name (`{videoId}_{title}.m4a`).
String? parseYoutubeVideoIdFromPath(String filePath) {
  final base = filePath.split(RegExp(r'[/\\]')).last;
  final underscore = base.indexOf('_');
  if (underscore <= 0) return null;
  final id = base.substring(0, underscore).trim();
  return id.isEmpty ? null : id;
}
