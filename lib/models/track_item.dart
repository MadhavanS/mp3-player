import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Row in the library / mini-player / now-playing. [filePath] is set for local scans.
class TrackItem {
  const TrackItem({
    required this.title,
    required this.artist,
    required this.metaLine,
    required this.genres,
    required this.artColors,
    this.filePath,
    this.albumArtBytes,
    this.youtubeVideoId,
    this.youtubeChannelId,
    this.thumbnailUrl,
  });

  final String title;
  final String artist;
  final String metaLine;
  final String genres;
  final List<Color> artColors;

  /// Absolute path when this track came from device storage.
  final String? filePath;

  /// Embedded cover art from tags (JPEG/PNG), if any.
  final Uint8List? albumArtBytes;

  /// YouTube video id when this row came from online search (no local [filePath]).
  final String? youtubeVideoId;

  /// Upload channel id (`UC…`) for [youtubeVideoId] streams.
  final String? youtubeChannelId;

  /// Remote cover URL (e.g. YouTube thumbnail).
  final String? thumbnailUrl;

  bool get isYoutubeStream =>
      youtubeVideoId != null && youtubeVideoId!.trim().isNotEmpty;

  bool get isPlayable =>
      (filePath != null && filePath!.trim().isNotEmpty) || isYoutubeStream;

  static const Color _pink = Color(0xFFFF6B9D);
  static const Color _blue = Color(0xFF4FACFE);
  static const Color _purple = Color(0xFFA18CD1);
  static const Color _orange = Color(0xFFFFAB73);
  static const Color _teal = Color(0xFF30CFD0);

  static const List<Color> _palette = [
    _purple,
    _pink,
    _orange,
    _teal,
    _blue,
  ];

  static List<Color> _gradientForKey(String key) {
    final h = key.hashCode;
    final a = _palette[h.abs() % _palette.length];
    final b = _palette[(h.abs() ~/ 3 + 1) % _palette.length];
    return [a, b];
  }

  factory TrackItem.fromFilePath(String path) {
    final base = p.basename(path);
    final title = p.basenameWithoutExtension(base);
    return TrackItem(
      title: title.isEmpty ? base : title,
      artist: 'Unknown artist',
      metaLine: 'mp3',
      genres: '',
      artColors: _gradientForKey(path),
      filePath: path,
    );
  }

  /// Maps a YouTube [Video] from [ytClient.search] into a queue-ready row.
  factory TrackItem.fromYoutubeVideo(Video video) {
    final id = video.id.value;
    final duration = video.duration;
    final meta = duration != null
        ? _formatDurationLabel(duration)
        : (video.isLive ? 'Live' : 'YouTube');
    return TrackItem(
      title: video.title,
      artist: video.author,
      metaLine: meta,
      genres: '',
      artColors: _gradientForKey(id),
      youtubeVideoId: id,
      youtubeChannelId: video.channelId.value,
      thumbnailUrl: video.thumbnails.mediumResUrl,
    );
  }

  static String _formatDurationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Merge ID3 (or similar) tags; keeps filename fallbacks when fields are empty.
  ///
  /// When [replaceGenreFromFile] is true (reading a fresh snapshot from disk),
  /// an empty or missing [genre] clears [genres] to '' instead of keeping the
  /// previous value.
  ///
  /// When [replaceAlbumArtFromFile] is true (same: fresh read from disk),
  /// embedded art follows [albumArtBytes] exactly — `null` or empty clears
  /// [albumArtBytes] instead of preserving the prior image.
  TrackItem withEmbeddedMetadata({
    String? title,
    String? artist,
    String? album,
    String? genre,
    Uint8List? albumArtBytes,
    bool replaceGenreFromFile = false,
    bool replaceAlbumArtFromFile = false,
  }) {
    final t = title?.trim();
    final a = artist?.trim();
    final alb = album?.trim();
    final g = genre?.trim();
    final newGenres = () {
      if (g != null && g.isNotEmpty) {
        return '#${g.replaceAll(RegExp(r'\s+'), '')}';
      }
      if (replaceGenreFromFile) {
        return '';
      }
      return genres;
    }();
    final mergedArt = () {
      if (replaceAlbumArtFromFile) {
        final b = albumArtBytes;
        if (b != null && b.isNotEmpty) return b;
        return null;
      }
      return albumArtBytes ?? this.albumArtBytes;
    }();

    return TrackItem(
      title: (t != null && t.isNotEmpty) ? t : this.title,
      artist: (a != null && a.isNotEmpty) ? a : this.artist,
      metaLine: (alb != null && alb.isNotEmpty) ? alb : metaLine,
      genres: newGenres,
      artColors: artColors,
      filePath: filePath,
      albumArtBytes: mergedArt,
      youtubeVideoId: youtubeVideoId,
      youtubeChannelId: youtubeChannelId,
      thumbnailUrl: thumbnailUrl,
    );
  }

  /// Keeps loaded cover bytes when [incoming] came from disk/cache without art.
  static TrackItem mergePreservedAlbumArt(
    TrackItem incoming,
    TrackItem? previous,
  ) {
    if (previous == null) return incoming;
    final incomingArt = incoming.albumArtBytes;
    if (incomingArt != null && incomingArt.isNotEmpty) return incoming;
    final previousArt = previous.albumArtBytes;
    if (previousArt == null || previousArt.isEmpty) return incoming;
    return TrackItem(
      title: incoming.title,
      artist: incoming.artist,
      metaLine: incoming.metaLine,
      genres: incoming.genres,
      artColors: previous.artColors,
      filePath: incoming.filePath,
      albumArtBytes: previousArt,
      youtubeVideoId: incoming.youtubeVideoId,
      youtubeChannelId: incoming.youtubeChannelId ?? previous.youtubeChannelId,
      thumbnailUrl: incoming.thumbnailUrl ?? previous.thumbnailUrl,
    );
  }

  /// Built-in samples when no folder is selected (UI dev / empty device).
  static final List<TrackItem> demoSamples = [
    TrackItem(
      title: 'Bag (feat. Yung Bans)',
      artist: 'Chance the Rapper',
      metaLine: '19d',
      genres: '#hiphop #rap',
      artColors: [_purple, _pink],
    ),
    TrackItem(
      title: 'Sunset Boulevard',
      artist: 'Local Artist',
      metaLine: '3d',
      genres: '#indie #pop',
      artColors: [_orange, _teal],
    ),
    TrackItem(
      title: 'Midnight Drive',
      artist: 'Demo Band',
      metaLine: '1d',
      genres: '#electronic',
      artColors: [_blue, _purple],
    ),
  ];
}
