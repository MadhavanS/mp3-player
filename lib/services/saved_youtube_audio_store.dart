import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_item.dart';

/// Locally downloaded YouTube audio files (offline replay).
class SavedYoutubeAudioStore {
  SavedYoutubeAudioStore._();

  static const _key = 'saved_youtube_audio_v1';

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
      final parsed = <TrackItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final t = _trackFromJson(Map<String, dynamic>.from(e));
        final fp = t.filePath?.trim();
        if (fp == null || fp.isEmpty) continue;
        if (!kIsWeb && !await File(fp).exists()) continue;
        parsed.add(t);
      }
      _items = parsed;
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

  static String? filePathForVideoId(String? videoId) {
    final id = videoId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final t in _items) {
      if (t.youtubeVideoId == id) return t.filePath;
    }
    return null;
  }

  static Future<bool> add(TrackItem track) async {
    final id = track.youtubeVideoId?.trim();
    final fp = track.filePath?.trim();
    if (id == null || id.isEmpty || fp == null || fp.isEmpty) return false;
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
    final existing = _items.where((t) => t.youtubeVideoId == id).toList();
    if (existing.isEmpty) return false;
    _items.removeWhere((t) => t.youtubeVideoId == id);
    if (!kIsWeb) {
      for (final t in existing) {
        final fp = t.filePath?.trim();
        if (fp == null || fp.isEmpty) continue;
        try {
          final f = File(fp);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
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
        'filePath': t.filePath,
      };

  static TrackItem _trackFromJson(Map<String, dynamic> m) {
    final id = (m['youtubeVideoId'] as String? ?? '').trim();
    final fp = (m['filePath'] as String? ?? '').trim();
    return TrackItem(
      title: m['title'] as String? ?? 'YouTube',
      artist: m['artist'] as String? ?? '',
      metaLine: m['metaLine'] as String? ?? 'Saved',
      genres: '',
      artColors: _artColorsForYoutubeId(id),
      filePath: fp.isEmpty ? null : p.normalize(fp),
      youtubeVideoId: id.isEmpty ? null : id,
      youtubeChannelId: (m['youtubeChannelId'] as String?)?.trim(),
      thumbnailUrl: m['thumbnailUrl'] as String?,
    );
  }

  static List<Color> _artColorsForYoutubeId(String id) {
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
