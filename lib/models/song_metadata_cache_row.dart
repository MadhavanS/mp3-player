class SongMetadataCacheRow {
  SongMetadataCacheRow({
    required this.path,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.genres = '',
    this.artColorValues = const <int>[],
    this.fileSizeBytes = 0,
    this.updatedAtMs = 0,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final String genres;
  final List<int> artColorValues;
  final int fileSizeBytes;
  final int updatedAtMs;

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'genres': genres,
    'artColorValues': artColorValues,
    'fileSizeBytes': fileSizeBytes,
    'updatedAtMs': updatedAtMs,
  };

  factory SongMetadataCacheRow.fromJson(Map<String, Object?> json) {
    final colors = json['artColorValues'];
    return SongMetadataCacheRow(
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      genres: json['genres'] as String? ?? '',
      artColorValues: colors is List
          ? colors.map((v) => (v as num).toInt()).toList(growable: false)
          : const <int>[],
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
