import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_track.dart';

/// Saved YouTube search results (bookmarks), keyed by video id.
class YoutubeBookmarkStore {
  YoutubeBookmarkStore._();

  static const _prefsKey = 'youtube_bookmarks_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static void _bumpRevision() => revision.value++;

  static Future<List<YoutubeTrack>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => _trackFromJson(Map<String, dynamic>.from(e as Map)))
          .whereType<YoutubeTrack>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<Set<String>> loadVideoIds() async {
    final tracks = await loadAll();
    return tracks.map((t) => t.videoId).toSet();
  }

  static Future<YoutubeTrack?> findByVideoId(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    final tracks = await loadAll();
    for (final t in tracks) {
      if (t.videoId == id) return t;
    }
    return null;
  }

  static Future<bool> isBookmarked(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return false;
    final ids = await loadVideoIds();
    return ids.contains(id);
  }

  /// Returns true if bookmark was added, false if removed.
  static Future<bool> toggle(YoutubeTrack track) async {
    final id = track.videoId.trim();
    if (id.isEmpty) return false;

    final existing = await loadAll();
    final ix = existing.indexWhere((t) => t.videoId == id);
    final List<YoutubeTrack> next;
    final bool added;
    if (ix >= 0) {
      next = [...existing]..removeAt(ix);
      added = false;
    } else {
      next = [track, ...existing];
      added = true;
    }

    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(
        _prefsKey,
        jsonEncode(next.map(_trackToJson).toList(growable: false)),
      );
    }
    _bumpRevision();
    return added;
  }

  static Map<String, dynamic> _trackToJson(YoutubeTrack t) => {
        'videoId': t.videoId,
        'title': t.title,
        'artist': t.artist,
        if (t.thumbnailUrl != null) 'thumbnailUrl': t.thumbnailUrl,
        if (t.duration != null) 'durationMs': t.duration!.inMilliseconds,
      };

  static YoutubeTrack? _trackFromJson(Map<String, dynamic> j) {
    final videoId = (j['videoId'] as String?)?.trim();
    if (videoId == null || videoId.isEmpty) return null;
    final durationMs = j['durationMs'];
    return YoutubeTrack(
      videoId: videoId,
      title: (j['title'] as String?)?.trim() ?? videoId,
      artist: (j['artist'] as String?)?.trim() ?? 'Unknown artist',
      thumbnailUrl: (j['thumbnailUrl'] as String?)?.trim(),
      duration: durationMs is int && durationMs > 0
          ? Duration(milliseconds: durationMs)
          : null,
    );
  }
}
