import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_item.dart';

/// User-saved YouTube tracks for quick replay without searching again.
class SavedYoutubeLinksStore {
  SavedYoutubeLinksStore._();

  static const _key = 'saved_youtube_links_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<TrackItem> _items = [];
  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() async {
    _loadFuture ??= _readFromPrefs();
    await _loadFuture;
  }

  static Future<void> _readFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _items = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items = [
        for (final e in list)
          if (e is Map) _trackFromJson(Map<String, dynamic>.from(e)),
      ].where((t) => t.isYoutubeStream).toList();
    } catch (_) {
      _items = [];
    }
  }

  static Future<List<TrackItem>> load() async {
    await ensureLoaded();
    return List.unmodifiable(_items);
  }

  static bool isSaved(String? videoId) {
    final id = videoId?.trim();
    if (id == null || id.isEmpty) return false;
    return _items.any((t) => t.youtubeVideoId == id);
  }

  static Future<bool> add(TrackItem track) async {
    final id = track.youtubeVideoId?.trim();
    if (id == null || id.isEmpty) return false;
    await ensureLoaded();
    _items.removeWhere((t) => t.youtubeVideoId == id);
    _items.insert(0, track);
    await _persist();
    return true;
  }

  static Future<bool> remove(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return false;
    await ensureLoaded();
    final before = _items.length;
    _items.removeWhere((t) => t.youtubeVideoId == id);
    if (_items.length == before) return false;
    await _persist();
    return true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map(_trackToJson).toList());
    await prefs.setString(_key, encoded);
    revision.value++;
  }

  static Map<String, dynamic> _trackToJson(TrackItem t) => {
        'youtubeVideoId': t.youtubeVideoId,
        'youtubeChannelId': t.youtubeChannelId,
        'title': t.title,
        'artist': t.artist,
        'metaLine': t.metaLine,
        'thumbnailUrl': t.thumbnailUrl,
      };

  static TrackItem _trackFromJson(Map<String, dynamic> m) {
    final id = (m['youtubeVideoId'] as String? ?? '').trim();
    return TrackItem(
      title: m['title'] as String? ?? 'YouTube',
      artist: m['artist'] as String? ?? '',
      metaLine: m['metaLine'] as String? ?? 'YouTube',
      genres: '',
      artColors: _artColorsForYoutubeId(id),
      youtubeVideoId: id.isEmpty ? null : id,
      youtubeChannelId: (m['youtubeChannelId'] as String?)?.trim(),
      thumbnailUrl: m['thumbnailUrl'] as String?,
    );
  }

  static List<Color> _artColorsForYoutubeId(String id) {
    // Mirror [TrackItem] palette keyed by video id.
    const palette = [
      Color(0xFFA18CD1),
      Color(0xFFFF6B9D),
      Color(0xFFFFAB73),
      Color(0xFF30CFD0),
      Color(0xFF4FACFE),
    ];
    final h = id.hashCode;
    return [
      palette[h.abs() % palette.length],
      palette[(h.abs() ~/ 3 + 1) % palette.length],
    ];
  }
}
