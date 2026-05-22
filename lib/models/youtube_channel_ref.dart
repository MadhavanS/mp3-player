/// Resolved YouTube channel for scoped online search.
class YoutubeChannelRef {
  const YoutubeChannelRef({
    required this.id,
    required this.title,
    this.thumbnailUrl,
  });

  /// Channel id (typically `UC…`).
  final String id;
  final String title;
  final String? thumbnailUrl;
}
