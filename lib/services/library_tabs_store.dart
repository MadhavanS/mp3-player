import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_tab_id.dart';

/// One row in Settings: tab identity + visibility; list order is tab order.
class LibraryTabRow {
  const LibraryTabRow({
    required this.id,
    required this.enabled,
  });

  final LibraryTabId id;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id.wireValue,
        'enabled': enabled,
      };

  factory LibraryTabRow.fromJson(Map<String, dynamic> j) {
    final id =
        LibraryTabId.parse(j['id'] as String?) ?? LibraryTabId.songs;
    return LibraryTabRow(
      id: id,
      enabled: j['enabled'] as bool? ?? true,
    );
  }
}

/// User-defined Library tab visibility and order (Settings).
class LibraryTabsStore {
  LibraryTabsStore._();

  static const _prefsKey = 'library_tabs_config_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<LibraryTabRow> _defaultRows() => [
        for (final id in LibraryTabId.values)
          LibraryTabRow(id: id, enabled: true),
      ];

  /// Ensures every tab appears exactly once; preserves saved order first.
  static List<LibraryTabRow> normalize(List<LibraryTabRow> saved) {
    final byId = {for (final r in saved) r.id: r};
    final orderedIds = <LibraryTabId>[];
    for (final r in saved) {
      if (!orderedIds.contains(r.id)) orderedIds.add(r.id);
    }
    for (final id in LibraryTabId.values) {
      if (!orderedIds.contains(id)) orderedIds.add(id);
    }
    return orderedIds
        .map((id) => byId[id] ?? LibraryTabRow(id: id, enabled: true))
        .toList();
  }

  static Future<List<LibraryTabRow>> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return _defaultRows();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final rows = decoded
          .map((e) => LibraryTabRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return normalize(rows);
    } catch (_) {
      return _defaultRows();
    }
  }

  /// Visible tabs in UI order.
  static Future<List<LibraryTabId>> loadVisibleOrdered() async {
    final rows = await loadConfig();
    return rows.where((r) => r.enabled).map((r) => r.id).toList();
  }

  static Future<void> saveConfig(List<LibraryTabRow> rows) async {
    final normalized = normalize(rows);
    var out = normalized;
    if (!out.any((r) => r.enabled)) {
      out = [
        for (final r in normalized)
          r.id == LibraryTabId.songs
              ? LibraryTabRow(id: r.id, enabled: true)
              : r,
      ];
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(out.map((r) => r.toJson()).toList()),
    );
    revision.value++;
  }
}
