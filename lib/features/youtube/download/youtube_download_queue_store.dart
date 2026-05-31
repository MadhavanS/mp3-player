import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_track.dart';

/// Persists pending YouTube downloads so they resume after app restart.
class YoutubeDownloadQueueStore {
  YoutubeDownloadQueueStore._();

  static const _prefsKey = 'youtube_download_queue_v1';

  static Future<List<YoutubeTrack>> loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <YoutubeTrack>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final videoId = (map['videoId'] as String?)?.trim() ?? '';
        if (videoId.isEmpty) continue;
        final durationMs = map['durationMs'];
        out.add(
          YoutubeTrack(
            videoId: videoId,
            title: (map['title'] as String?)?.trim().isNotEmpty == true
                ? map['title'] as String
                : videoId,
            artist: (map['artist'] as String?)?.trim().isNotEmpty == true
                ? map['artist'] as String
                : 'Unknown artist',
            thumbnailUrl: map['thumbnailUrl'] as String?,
            duration: durationMs is num && durationMs > 0
                ? Duration(milliseconds: durationMs.round())
                : null,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> savePending(List<YoutubeTrack> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    if (tracks.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }

    final encoded = jsonEncode(
      tracks
          .map(
            (t) => <String, dynamic>{
              'videoId': t.videoId,
              'title': t.title,
              'artist': t.artist,
              'thumbnailUrl': t.thumbnailUrl,
              'durationMs': t.duration?.inMilliseconds,
            },
          )
          .toList(growable: false),
    );
    await prefs.setString(_prefsKey, encoded);
  }

  static Future<void> upsert(YoutubeTrack track) async {
    final pending = await loadPending();
    final next = [
      for (final t in pending)
        if (t.videoId != track.videoId) t,
      track,
    ];
    await savePending(next);
  }

  static Future<void> remove(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return;
    final pending = await loadPending();
    final next = pending.where((t) => t.videoId != id).toList(growable: false);
    await savePending(next);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
