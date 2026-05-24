import 'dart:typed_data';

import '../models/track_item.dart';
import '../services/music_library_path_key.dart';

/// In-memory library index: ordered paths + tag fields without embedded cover bytes.
///
/// List thumbnails load from the path-keyed album-art disk cache (see
/// [primeAlbumArtDiskCache]); a small in-memory LRU holds recently read covers
/// for fast [TrackItem] merges. [SongMetadataCache] stores tags only, not art.
class LibraryCatalog {
  List<String> _paths = const [];
  final Map<String, TrackItem> _byKey = {};
  final Map<String, TrackItem> _artHot = {};
  static const int _artHotMax = 512;

  bool get isEmpty => _paths.isEmpty;

  bool get isNotEmpty => _paths.isNotEmpty;

  int get length => _paths.length;

  /// Canonical path keys for every catalog row (playlist validation, etc.).
  Set<String> get canonicalPathKeys {
    final out = <String>{};
    for (final p in _paths) {
      final k = canonicalMusicLibraryPathKey(p);
      if (k.isNotEmpty) out.add(k);
    }
    return out;
  }

  List<TrackItem> get tracks => List<TrackItem>.unmodifiable(
    _paths.map(_resolve).toList(growable: false),
  );

  void setAll(List<TrackItem> tracks) {
    final paths = <String>[];
    final byKey = <String, TrackItem>{};
    final newKeys = <String>{};

    for (final t in tracks) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      final key = canonicalMusicLibraryPathKey(fp);
      if (key.isEmpty) continue;
      newKeys.add(key);
      paths.add(fp);
      byKey[key] = t.withoutAlbumArt();
      final art = t.albumArtBytes;
      if (art != null && art.isNotEmpty) {
        _putArtHot(key, t);
      }
    }

    _paths = paths;
    _byKey
      ..clear()
      ..addAll(byKey);
    _artHot.removeWhere((k, _) => !newKeys.contains(k));
  }

  TrackItem? trackForPath(String path) {
    final raw = path.trim();
    if (raw.isEmpty) return null;
    final key = canonicalMusicLibraryPathKey(raw);
    if (key.isEmpty) return null;
    final base = _byKey[key];
    if (base == null) return null;
    return _resolve(base.filePath ?? raw);
  }

  /// Updates metadata for [path]; returns whether the path exists in the catalog.
  bool updateAtPath(String path, TrackItem updated) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty || !_byKey.containsKey(key)) return false;
    final art = updated.albumArtBytes;
    if (art != null && art.isNotEmpty) {
      _putArtHot(key, updated);
    }
    _byKey[key] = updated.withoutAlbumArt();
    return true;
  }

  bool removeAtPath(String path) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return false;
    final before = _paths.length;
    _paths = _paths
        .where((p) => canonicalMusicLibraryPathKey(p) != key)
        .toList(growable: false);
    _byKey.remove(key);
    _artHot.remove(key);
    return _paths.length != before;
  }

  /// Drops in-memory cover bytes for [path] (rename/delete).
  void evictArtHotAtPath(String path) {
    final key = canonicalMusicLibraryPathKey(path.trim());
    if (key.isEmpty) return;
    _artHot.remove(key);
  }

  TrackItem _resolve(String path) {
    final key = canonicalMusicLibraryPathKey(path);
    final base = _byKey[key] ?? TrackItem.fromFilePath(path);
    final hot = _artHot[key];
    final hotArt = hot?.albumArtBytes;
    if (hotArt != null &&
        hotArt.isNotEmpty &&
        (base.albumArtBytes == null || base.albumArtBytes!.isEmpty)) {
      return base.withEmbeddedMetadata(
        albumArtBytes: hotArt,
        replaceAlbumArtFromFile: true,
      );
    }
    return base;
  }

  void _putArtHot(String key, TrackItem withArt) {
    _artHot.remove(key);
    _artHot[key] = withArt;
    while (_artHot.length > _artHotMax) {
      _artHot.remove(_artHot.keys.first);
    }
  }

  /// Recently displayed list art (PNG bytes), keyed by canonical path key.
  Uint8List? hotArtBytesForPathKey(String pathKey) {
    if (pathKey.isEmpty) return null;
    final art = _artHot[pathKey]?.albumArtBytes;
    if (art == null || art.isEmpty) return null;
    return art;
  }

  /// Promotes decoded list art into the catalog hot LRU for instant re-display.
  void promoteArtBytes(String pathKey, Uint8List art) {
    if (pathKey.isEmpty || art.isEmpty) return;
    final base = _byKey[pathKey];
    if (base == null) return;
    _putArtHot(
      pathKey,
      base.withEmbeddedMetadata(
        albumArtBytes: art,
        replaceAlbumArtFromFile: true,
      ),
    );
  }
}
