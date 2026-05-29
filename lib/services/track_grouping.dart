import '../models/track_item.dart';

enum TrackGroupKind { album, artist }

class TrackGroupRequest {
  const TrackGroupRequest({
    required this.kind,
    required this.value,
  });

  final TrackGroupKind kind;
  final String value;
}

String normalizeTrackGroupValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.toLowerCase();
}

String trackGroupValueFor(TrackItem track, TrackGroupKind kind) {
  return switch (kind) {
    TrackGroupKind.album => track.metaLine.trim(),
    TrackGroupKind.artist => track.artist.trim(),
  };
}

List<String> splitArtistNames(String raw) {
  final compact = raw.trim();
  if (compact.isEmpty) return const <String>[];
  final parts = compact.split(
    RegExp(r'\s*(?:,|/|;|&|\band\b|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*', caseSensitive: false),
  );
  final out = <String>[];
  final seen = <String>{};
  for (final p in parts) {
    final t = p.trim();
    if (t.isEmpty) continue;
    final n = normalizeTrackGroupValue(t);
    if (n.isEmpty || !seen.add(n)) continue;
    out.add(t);
  }
  return out;
}

List<TrackItem> resolveTracksForArtists({
  required Iterable<TrackItem> source,
  required Iterable<String> artistNames,
}) {
  final wanted = artistNames
      .map(normalizeTrackGroupValue)
      .where((v) => v.isNotEmpty)
      .toSet();
  if (wanted.isEmpty) return const <TrackItem>[];
  return source.where((track) {
    final candidates = splitArtistNames(track.artist)
        .map(normalizeTrackGroupValue)
        .where((v) => v.isNotEmpty);
    for (final c in candidates) {
      if (wanted.contains(c)) return true;
    }
    return false;
  }).toList(growable: false);
}

List<TrackItem> resolveTracksForGroup({
  required Iterable<TrackItem> source,
  required TrackGroupRequest request,
}) {
  final wanted = normalizeTrackGroupValue(request.value);
  if (wanted.isEmpty) return const <TrackItem>[];
  return source.where((track) {
    final current = normalizeTrackGroupValue(
      trackGroupValueFor(track, request.kind),
    );
    return current == wanted;
  }).toList(growable: false);
}

String groupLabel(TrackGroupKind kind) {
  return switch (kind) {
    TrackGroupKind.album => 'Album',
    TrackGroupKind.artist => 'Artist',
  };
}
