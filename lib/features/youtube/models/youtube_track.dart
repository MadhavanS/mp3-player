/// YouTube search / queue item before download completes.
class YoutubeTrack {
  const YoutubeTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.duration,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Duration? duration;

  YoutubeTrack copyWith({
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    Duration? duration,
  }) {
    return YoutubeTrack(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
    );
  }
}
