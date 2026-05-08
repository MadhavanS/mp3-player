import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../audio/player_controller.dart';
import '../models/library_tab_id.dart';
import '../models/track_item.dart';
import 'music_library_path_key.dart';

const _playbackKey = 'playback_session_v2';
const _browseKeysKey = 'songs_tab_browse_path_keys_v1';
const _shellPageKey = 'main_shell_visible_page_v1';

/// Persists playback queue, transport state, and library browse filter across restarts.
abstract final class PlaybackSessionStore {
  static Future<void> savePlayer(PlayerController player) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(player.buildPlaybackPersistenceJson());
    await prefs.setString(_playbackKey, encoded);
  }

  static Future<bool> restorePlayer(
    PlayerController player,
    List<TrackItem> catalogTracks, {
    bool resumePlaying = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playbackKey);
    if (raw == null || raw.isEmpty) return false;

    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return false;
    }
    try {
      final restored = _Restore.tryParse(map);
      if (restored == null) return false;
      return await restored.apply(
        player,
        catalogTracks,
        resumePlaying: resumePlaying,
      );
    } catch (_) {
      return false;
    }
  }

  /// Loads persisted queue paths saved by [savePlayer], without restoring playback.
  static Future<List<String>> loadPersistedQueuePaths() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playbackKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final restored = _Restore.tryParse(map);
      if (restored == null) return const <String>[];
      return List<String>.from(restored.playlistPaths);
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> saveBrowsePathKeys(Set<String>? keys) async {
    final prefs = await SharedPreferences.getInstance();
    if (keys == null) {
      await prefs.remove(_browseKeysKey);
      return;
    }
    await prefs.setString(_browseKeysKey, jsonEncode(keys.toList()));
  }

  /// `null`: no Songs-tab folder restriction.
  static Future<Set<String>?> loadBrowsePathKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browseKeysKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final out = decoded
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveShellPageIsSettings(bool settingsVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shellPageKey, settingsVisible);
  }

  /// `true`: Settings tab was visible. `false` or missing defaults to Library.
  static Future<bool> loadShellPageIsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shellPageKey) ?? false;
  }
}

class _Restore {
  _Restore({
    required this.playlistPaths,
    required this.sequentialIndex,
    required this.shuffle,
    required this.shuffleOrder,
    required this.shufflePos,
    required this.repeatWire,
    required this.scopeKeys,
    required this.originTabWire,
    required this.originUserPlaylistId,
    required this.positionMs,
    required this.wasPlaying,
    required this.currentKey,
  });

  final List<String> playlistPaths;
  final int sequentialIndex;
  final bool shuffle;
  final List<int> shuffleOrder;
  final int shufflePos;
  final String repeatWire;
  final List<String>? scopeKeys;
  final String? originTabWire;
  final String? originUserPlaylistId;
  final int positionMs;
  final bool wasPlaying;
  final String currentKey;

  static PlaylistRepeatMode? _parseRepeat(String raw) {
    try {
      return PlaylistRepeatMode.values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  static _Restore? tryParse(Map<String, dynamic> m) {
    final v = m['v'];
    if (v is! num || v.toInt() != 2) return null;
    final pathsRaw = m['paths'];
    if (pathsRaw is! List || pathsRaw.isEmpty) return null;

    final paths = pathsRaw
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (paths.isEmpty) return null;

    final soRaw = m['shuffleOrder'];
    List<int> order = const [];
    if (soRaw is List) {
      final built = <int>[];
      for (final e in soRaw) {
        if (e is int) {
          built.add(e);
        } else if (e is num) {
          built.add(e.toInt());
        }
      }
      order = built;
    }

    final rw = (m['repeat'] as String?) ?? 'off';

    return _Restore(
      playlistPaths: paths,
      sequentialIndex: (m['index'] as num?)?.toInt() ?? 0,
      shuffle: m['shuffle'] == true,
      shuffleOrder: order,
      shufflePos: (m['shufflePos'] as num?)?.toInt() ?? 0,
      repeatWire: PlaylistRepeatMode.values.any((x) => x.name == rw)
          ? rw
          : 'off',
      scopeKeys: switch (m['scopeKeys']) {
        final List l =>
          l.map((e) => e.toString()).where((s) => s.isNotEmpty).toList(),
        _ => null,
      },
      originTabWire: m['originTab'] as String?,
      originUserPlaylistId: m['originPlaylistId'] as String?,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      wasPlaying: m['wasPlaying'] == true,
      currentKey: (m['currentKey'] as String?) ?? '',
    );
  }

  Future<bool> apply(
    PlayerController player,
    List<TrackItem> catalogTracks, {
    required bool resumePlaying,
  }) async {
    final effectiveResumePlaying = resumePlaying && wasPlaying;

    final rebuilt = _rebuildQueue(playlistPaths, catalogTracks);
    if (rebuilt.tracks.isEmpty) return false;

    final repeat = _parseRepeat(repeatWire) ?? PlaylistRepeatMode.off;
    final originTab = LibraryTabId.parse(originTabWire);

    final scopeStrings = scopeKeys?.toSet();

    Set<String>? filterKeysToCatalog(Set<String>? keys, List<TrackItem> cats) {
      if (keys == null || keys.isEmpty) return null;
      final have = <String>{};
      for (final t in cats) {
        final fp = t.filePath?.trim();
        if (fp == null || fp.isEmpty) continue;
        final k = canonicalMusicLibraryPathKey(fp);
        if (k.isNotEmpty) have.add(k);
      }
      final keep = keys.where(have.contains).toSet();
      return keep.isEmpty ? null : keep;
    }

    final filteredScope = filterKeysToCatalog(scopeStrings, catalogTracks);

    var useShuffle = shuffle;
    var order = shuffleOrder;
    final n = rebuilt.tracks.length;

    if (useShuffle &&
        order.length == playlistPaths.length &&
        _isPermutation(order, playlistPaths.length)) {
      final newOrder = remapShuffle(order, playlistPaths, rebuilt.paths);
      if (newOrder == null || !_isPermutation(newOrder, n)) {
        useShuffle = false;
        order = const [];
      } else {
        order = newOrder;
      }
    } else if (useShuffle) {
      useShuffle = false;
      order = const [];
    }

    var seqIx =
        remapIndexAfterFilter(playlistPaths, rebuilt.paths, sequentialIndex) ??
        0;

    final curKeyEffective = currentKey.isNotEmpty
        ? currentKey
        : (seqIx >= 0 && seqIx < rebuilt.paths.length
              ? canonicalMusicLibraryPathKey(rebuilt.paths[seqIx])
              : '');

    int resolveCurrentIndex(List<TrackItem> items) {
      if (curKeyEffective.isEmpty) return seqIx.clamp(0, items.length - 1);
      for (var i = 0; i < items.length; i++) {
        final fp = items[i].filePath;
        if (fp != null && canonicalMusicLibraryPathKey(fp) == curKeyEffective) {
          return i;
        }
      }
      return seqIx.clamp(0, items.length - 1);
    }

    var curIx = resolveCurrentIndex(rebuilt.tracks);

    final posMs = positionMs.clamp(0, 864000000);
    final pos = Duration(milliseconds: posMs);

    if (useShuffle && order.isNotEmpty) {
      curIx = curIx.clamp(0, n - 1);
      var shufflePosition = order.indexWhere((ix) => ix == curIx);
      if (shufflePosition < 0) {
        shufflePosition = 0;
        curIx = order[shufflePosition].clamp(0, n - 1);
      }

      await player.applyRestoredPlayback(
        queue: rebuilt.tracks,
        sequentialIndex: curIx.clamp(0, n - 1),
        shuffle: true,
        shuffleOrder: order,
        shufflePos: shufflePosition.clamp(
          0,
          order.isEmpty ? 0 : order.length - 1,
        ),
        repeat: repeat,
        pathScopeKeys: filteredScope,
        originTab: originTab,
        originUserPlaylistId: originUserPlaylistId,
        position: pos,
        resumePlaying: effectiveResumePlaying,
      );
      return true;
    }

    await player.applyRestoredPlayback(
      queue: rebuilt.tracks,
      sequentialIndex: curIx.clamp(0, n - 1),
      shuffle: false,
      shuffleOrder: const [],
      shufflePos: 0,
      repeat: repeat,
      pathScopeKeys: filteredScope,
      originTab: originTab,
      originUserPlaylistId: originUserPlaylistId,
      position: pos,
      resumePlaying: effectiveResumePlaying,
    );
    return true;
  }
}

typedef _Rebuild = ({List<TrackItem> tracks, List<String> paths});

_Rebuild _rebuildQueue(
  List<String> savedOrderedPaths,
  List<TrackItem> catalogTracks,
) {
  final catalogByKey = <String, TrackItem>{};
  for (final t in catalogTracks) {
    final fp = t.filePath?.trim();
    if (fp == null || fp.isEmpty) continue;
    final k = canonicalMusicLibraryPathKey(fp);
    if (k.isNotEmpty) catalogByKey[k] = t;
  }

  final tracks = <TrackItem>[];
  final pathsOut = <String>[];
  for (final raw in savedOrderedPaths) {
    if (raw.isEmpty) continue;
    final k = canonicalMusicLibraryPathKey(raw);
    TrackItem? t;
    if (k.isNotEmpty) t = catalogByKey[k];

    final use = t ?? TrackItem.fromFilePath(raw);
    final fp = use.filePath;
    if (fp == null || fp.isEmpty) continue;
    tracks.add(use);
    pathsOut.add(fp);
  }

  return (tracks: tracks, paths: pathsOut);
}

int? remapIndexAfterFilter(
  List<String> oldPaths,
  List<String> newPaths,
  int oldIx,
) {
  if (oldIx < 0 || oldIx >= oldPaths.length) return null;
  final want = canonicalMusicLibraryPathKey(oldPaths[oldIx]);
  if (want.isEmpty) return null;
  for (var ni = 0; ni < newPaths.length; ni++) {
    if (canonicalMusicLibraryPathKey(newPaths[ni]) == want) return ni;
  }
  return null;
}

List<int>? remapShuffle(
  List<int> oldShuffleOrder,
  List<String> oldPaths,
  List<String> newPaths,
) {
  final shuffledPaths = <String>[];
  for (final oi in oldShuffleOrder) {
    if (oi < 0 || oi >= oldPaths.length) return null;
    shuffledPaths.add(oldPaths[oi]);
  }

  final have = <String>{
    for (final p in newPaths) canonicalMusicLibraryPathKey(p),
  };
  final filteredPaths = shuffledPaths
      .where(
        (p) => p.isNotEmpty && have.contains(canonicalMusicLibraryPathKey(p)),
      )
      .toList();

  final idxByPathKey = <String, int>{};
  for (var i = 0; i < newPaths.length; i++) {
    final k = canonicalMusicLibraryPathKey(newPaths[i]);
    if (k.isEmpty) continue;
    idxByPathKey.putIfAbsent(k, () => i);
  }

  final newOrder = <int>[];
  for (final p in filteredPaths) {
    final k = canonicalMusicLibraryPathKey(p);
    final ix = idxByPathKey[k];
    if (ix == null) return null;
    newOrder.add(ix);
  }

  if (newOrder.length != newPaths.length) return null;
  return newOrder;
}

bool _isPermutation(List<int> order, int n) {
  if (order.length != n) return false;
  final seen = List<bool>.filled(n, false);
  for (final x in order) {
    if (x < 0 || x >= n) return false;
    if (seen[x]) return false;
    seen[x] = true;
  }
  return true;
}
