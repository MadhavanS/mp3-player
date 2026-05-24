import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../audio/album_art_resolver.dart';
import '../audio/art_availability_notifier.dart';
import '../audio/player_controller.dart';
import '../models/track_item.dart';
import '../services/music_library_path_key.dart';

/// Loads list-row album art once per tile; avoids [FutureBuilder] on parent rebuilds.
///
/// Subscribes to [ArtAvailabilityNotifier] so rows retry after play/warmup fills cache.
class TrackArtNotifier extends ChangeNotifier {
  Uint8List? _art;
  bool _loading = false;
  bool _disposed = false;

  ArtAvailabilityNotifier? _availability;
  String? _subscribedPathKey;
  VoidCallback? _availabilityListener;

  TrackItem? _trackForRetry;
  PlayerController? _playerForRetry;
  int _maxDimensionForRetry = 192;

  Uint8List? get art => _art;
  bool get isLoading => _loading;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Synchronous art already available (hot LRU, any-dimension disk memory).
  Uint8List? resolveSyncArt(
    TrackItem track,
    PlayerController player,
    int maxDimension,
  ) {
    return resolveAlbumArtBytesSync(
      track,
      player,
      targetDimension: maxDimension,
    );
  }

  Future<void> load(
    TrackItem track,
    PlayerController player, {
    int maxDimension = 192,
  }) async {
    if (_disposed) return;
    _trackForRetry = track;
    _playerForRetry = player;
    _maxDimensionForRetry = maxDimension;

    final pathKey = trackArtPathKey(track);
    _bindArtAvailability(player.artAvailability, pathKey);

    if (_art != null) return;

    final sync = resolveSyncArt(track, player, maxDimension);
    if (sync != null && sync.isNotEmpty) {
      _art = sync;
      _safeNotify();
      return;
    }

    await _doLoad(track, player, maxDimension: maxDimension);
  }

  void _bindArtAvailability(
    ArtAvailabilityNotifier availability,
    String pathKey,
  ) {
    if (pathKey.isEmpty) {
      unbindArtAvailability();
      return;
    }
    if (_availability == availability && _subscribedPathKey == pathKey) {
      return;
    }
    unbindArtAvailability();
    _availability = availability;
    _subscribedPathKey = pathKey;
    _availabilityListener = () => _onArtBecameAvailable();
    availability.addListener(_availabilityListener!);
  }

  void _onArtBecameAvailable() {
    final pathKey = _subscribedPathKey;
    final availability = _availability;
    if (pathKey == null || availability == null) return;
    if (_art != null) {
      unbindArtAvailability();
      return;
    }
    if (!availability.hasArt(pathKey)) return;

    if (_loading) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        _onArtBecameAvailable();
      });
      return;
    }

    final track = _trackForRetry;
    final player = _playerForRetry;
    if (track == null || player == null) return;
    unawaited(_doLoad(track, player, maxDimension: _maxDimensionForRetry));
  }

  Future<void> _doLoad(
    TrackItem track,
    PlayerController player, {
    required int maxDimension,
  }) async {
    if (_disposed || _art != null || _loading) return;

    final sync = resolveSyncArt(track, player, maxDimension);
    if (sync != null && sync.isNotEmpty) {
      if (_disposed) return;
      _art = sync;
      _safeNotify();
      unbindArtAvailability();
      return;
    }

    final path = track.filePath?.trim() ?? '';
    if (path.isEmpty) return;

    _loading = true;
    try {
      final bytes = await resolveAlbumArtBytes(
        track,
        player: player,
        targetDimension: maxDimension,
      );
      if (_disposed) return;
      if (bytes != null && bytes.isNotEmpty) {
        _art = bytes;
        unbindArtAvailability();
      }
    } finally {
      if (_disposed) return;
      _loading = false;
      _safeNotify();
    }
  }

  void unbindArtAvailability() {
    final listener = _availabilityListener;
    final availability = _availability;
    if (listener != null && availability != null) {
      availability.removeListener(listener);
    }
    _availabilityListener = null;
    _availability = null;
    _subscribedPathKey = null;
  }

  void clear() {
    _art = null;
    _loading = false;
    _trackForRetry = null;
    _playerForRetry = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unbindArtAvailability();
    clear();
    super.dispose();
  }
}

String trackArtPathKey(TrackItem track) {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return '';
  return canonicalMusicLibraryPathKey(path);
}
