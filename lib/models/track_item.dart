import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Row in the library / mini-player / now-playing. [filePath] is set for local scans.
class TrackItem {
  const TrackItem({
    required this.title,
    required this.artist,
    required this.metaLine,
    required this.genres,
    required this.artColors,
    this.filePath,
  });

  final String title;
  final String artist;
  final String metaLine;
  final String genres;
  final List<Color> artColors;

  /// Absolute path when this track came from device storage.
  final String? filePath;

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
      genres: '#local',
      artColors: _gradientForKey(path),
      filePath: path,
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
