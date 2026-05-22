import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One row in Online search history (newest first in storage).
class YoutubeSearchHistoryEntry {
  const YoutubeSearchHistoryEntry({
    required this.query,
    this.channelId,
    this.channelTitle,
    required this.searchedAtMs,
  });

  final String query;
  final String? channelId;
  final String? channelTitle;
  final int searchedAtMs;

  String get displayLabel {
    final q = query.trim();
    final ch = channelTitle?.trim() ?? '';
    if (ch.isNotEmpty && q.isEmpty) return ch;
    if (ch.isNotEmpty) return '$q · $ch';
    return q.isEmpty ? 'Search' : q;
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        if (channelId != null && channelId!.isNotEmpty) 'channelId': channelId,
        if (channelTitle != null && channelTitle!.isNotEmpty)
          'channelTitle': channelTitle,
        'searchedAtMs': searchedAtMs,
      };

  factory YoutubeSearchHistoryEntry.fromJson(Map<String, dynamic> j) {
    return YoutubeSearchHistoryEntry(
      query: j['query'] as String? ?? '',
      channelId: (j['channelId'] as String?)?.trim(),
      channelTitle: (j['channelTitle'] as String?)?.trim(),
      searchedAtMs: j['searchedAtMs'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Persisted Online search queries (Settings limit + Search tab chips).
class YoutubeSearchHistoryStore {
  YoutubeSearchHistoryStore._();

  static const defaultLimit = 25;
  static const _maxLimit = 200;
  static const _historyKey = 'youtube_search_history_v1';
  static const _limitKey = 'youtube_search_history_limit_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static int _sanitizeLimit(int? raw) {
    if (raw == null || raw < 1) return defaultLimit;
    if (raw > _maxLimit) return _maxLimit;
    return raw;
  }

  static Future<int> loadLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return _sanitizeLimit(prefs.getInt(_limitKey));
  }

  static Future<void> saveLimit(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_limitKey, _sanitizeLimit(value));
    await _trimToLimit(_sanitizeLimit(value));
    revision.value++;
  }

  static Future<List<YoutubeSearchHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map)
            YoutubeSearchHistoryEntry.fromJson(
              Map<String, dynamic>.from(e),
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> recordSearch({
    required String query,
    String? channelId,
    String? channelTitle,
  }) async {
    final q = query.trim();
    final cid = channelId?.trim() ?? '';
    final ctitle = channelTitle?.trim() ?? '';
    if (q.isEmpty && cid.isEmpty) return;

    final limit = await loadLimit();
    var items = await load();

    items.removeWhere((e) {
      final sameQuery = e.query.trim() == q;
      final a = e.channelId?.trim() ?? '';
      final b = cid;
      return sameQuery && a == b;
    });

    items.insert(
      0,
      YoutubeSearchHistoryEntry(
        query: q,
        channelId: cid.isEmpty ? null : cid,
        channelTitle: ctitle.isEmpty ? null : ctitle,
        searchedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    if (items.length > limit) {
      items = items.sublist(0, limit);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    revision.value++;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    revision.value++;
  }

  static Future<void> _trimToLimit(int limit) async {
    final items = await load();
    if (items.length <= limit) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(items.take(limit).map((e) => e.toJson()).toList()),
    );
  }
}
