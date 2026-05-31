import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../audio/replay_gain.dart';

Future<ReplayGainAdjustment> readReplayGainTags(String? filePath) async {
  final raw = filePath?.trim() ?? '';
  if (raw.isEmpty) return const ReplayGainAdjustment();
  try {
    final tag = readAllMetadata(File(raw), getImage: false);
    return replayGainFromParserTag(tag);
  } catch (_) {
    return const ReplayGainAdjustment();
  }
}

ReplayGainAdjustment replayGainFromParserTag(Object tag) {
  if (tag is Mp3Metadata) {
    return _fromCustomMap(tag.customMetadata);
  }
  if (tag is VorbisMetadata) {
    return ReplayGainAdjustment(
      trackDb: _firstDb(tag.replayGainTrackGain),
      albumDb: _firstDb(tag.replayGainAlbumGain),
    );
  }
  if (tag is ApeMetadata) {
    // APE tags rarely carry ReplayGain; custom keys may appear later.
    return const ReplayGainAdjustment();
  }
  return const ReplayGainAdjustment();
}

ReplayGainAdjustment _fromCustomMap(Map<String, String> custom) {
  double? lookup(Iterable<String> keys) {
    for (final key in keys) {
      for (final entry in custom.entries) {
        if (entry.key.toUpperCase() == key.toUpperCase()) {
          final db = parseReplayGainDb(entry.value);
          if (db != null) return db;
        }
      }
    }
    return null;
  }

  return ReplayGainAdjustment(
    trackDb: lookup(const [
      'REPLAYGAIN_TRACK_GAIN',
      'TXXX:REPLAYGAIN_TRACK_GAIN',
    ]),
    albumDb: lookup(const [
      'REPLAYGAIN_ALBUM_GAIN',
      'TXXX:REPLAYGAIN_ALBUM_GAIN',
    ]),
  );
}

double? _firstDb(List<String> values) {
  for (final raw in values) {
    final db = parseReplayGainDb(raw);
    if (db != null) return db;
  }
  return null;
}
