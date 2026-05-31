import 'dart:math' as math;

/// ReplayGain tag pair in decibels (negative = attenuate, positive = boost).
class ReplayGainAdjustment {
  const ReplayGainAdjustment({this.trackDb, this.albumDb});

  final double? trackDb;
  final double? albumDb;

  bool get hasTags => trackDb != null || albumDb != null;

  ReplayGainAdjustment copyWith({double? trackDb, double? albumDb}) {
    return ReplayGainAdjustment(
      trackDb: trackDb ?? this.trackDb,
      albumDb: albumDb ?? this.albumDb,
    );
  }
}

enum ReplayGainMode {
  off('Off', 'No ReplayGain adjustment'),
  track('Track', 'Prefer track gain, fall back to album'),
  album('Album', 'Prefer album gain, fall back to track'),
  dynamic('Dynamic', 'Album gain when playing an album, else track');

  const ReplayGainMode(this.label, this.description);

  final String label;
  final String description;

  static ReplayGainMode fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return ReplayGainMode.track;
    for (final mode in ReplayGainMode.values) {
      if (mode.name == raw) return mode;
    }
    return ReplayGainMode.track;
  }
}

/// Parse strings like "-3.5 dB", "+2.0", "0.0 dB" into dB. Returns null for 0 or invalid.
double? parseReplayGainDb(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final cleaned = trimmed.replaceAll(RegExp(r'[^\d.+-]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value == 0) return null;
  return value;
}

/// Linear gain multiplier from a decibel adjustment.
double replayGainLinearFromDb(double db) => math.pow(10, db / 20).toDouble();

/// Resolve the dB adjustment from embedded tags, before pre-amp.
double? resolveReplayGainTagDb({
  required ReplayGainMode mode,
  required ReplayGainAdjustment tags,
  required bool albumPlaybackContext,
}) {
  if (mode == ReplayGainMode.off) return null;

  return switch (mode) {
    ReplayGainMode.off => null,
    ReplayGainMode.track => tags.trackDb ?? tags.albumDb,
    ReplayGainMode.album => tags.albumDb ?? tags.trackDb,
    ReplayGainMode.dynamic =>
      albumPlaybackContext ? (tags.albumDb ?? tags.trackDb) : tags.trackDb,
  };
}

/// Final dB sent to [AndroidLoudnessEnhancer] (tag gain + pre-amp).
double resolveReplayGainOutputDb({
  required ReplayGainMode mode,
  required ReplayGainAdjustment tags,
  required bool albumPlaybackContext,
  required double preAmpWithTagsDb,
  required double preAmpWithoutTagsDb,
}) {
  final tagDb = resolveReplayGainTagDb(
    mode: mode,
    tags: tags,
    albumPlaybackContext: albumPlaybackContext,
  );
  if (tagDb != null) {
    return tagDb + preAmpWithTagsDb;
  }
  return preAmpWithoutTagsDb;
}
