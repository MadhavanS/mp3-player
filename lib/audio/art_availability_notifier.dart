import 'package:flutter/foundation.dart';

/// Broadcasts when album art for a library path key is known to exist (hot LRU,
/// disk cache, or fresh metadata read). List-row [TrackArtNotifier]s subscribe
/// to retry disk/hot loads after a prior miss.
class ArtAvailabilityNotifier extends ChangeNotifier {
  final Set<String> _available = <String>{};
  var _batching = false;

  bool hasArt(String pathKey) =>
      pathKey.isNotEmpty && _available.contains(pathKey);

  /// Marks one path; notifies listeners unless a batch is open.
  void markAvailable(String pathKey) {
    if (pathKey.isEmpty) return;
    if (!_available.add(pathKey)) return;
    if (!_batching) notifyListeners();
  }

  void beginBatch() => _batching = true;

  /// Marks many paths and notifies once.
  void markAvailableAll(Iterable<String> pathKeys) {
    var added = false;
    for (final key in pathKeys) {
      if (key.isEmpty) continue;
      if (_available.add(key)) added = true;
    }
    if (added && !_batching) notifyListeners();
  }

  void endBatch() {
    if (!_batching) return;
    _batching = false;
    notifyListeners();
  }
}
