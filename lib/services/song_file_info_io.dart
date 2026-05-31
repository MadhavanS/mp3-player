import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;

import 'song_file_info.dart';

Future<SongFileInfo> readSongFileInfo(String? filePath) async {
  final raw = filePath?.trim() ?? '';
  if (raw.isEmpty) {
    return const SongFileInfo(
      fileName: 'Unknown',
      folderPath: 'Unknown',
      sizeBytes: null,
      durationMs: null,
      bitrateKbps: null,
      composer: null,
    );
  }

  int? sizeBytes;
  int? durationMs;
  int? bitrateKbps;
  try {
    final st = await File(raw).stat();
    sizeBytes = st.size;
  } catch (_) {
    sizeBytes = null;
  }

  final fromGod = await _readWithMetadataGod(raw);
  durationMs = fromGod.durationMs;
  bitrateKbps = fromGod.bitrateKbps;
  if (durationMs == null || bitrateKbps == null) {
    final fromReader = _readWithAudioMetadataReader(raw);
    durationMs ??= fromReader.durationMs;
    bitrateKbps ??= fromReader.bitrateKbps;
  }

  final composer = _readComposerTag(raw);

  return SongFileInfo(
    fileName: p.basename(raw),
    folderPath: p.dirname(raw),
    sizeBytes: sizeBytes,
    durationMs: durationMs,
    bitrateKbps: bitrateKbps,
    composer: composer,
  );
}

String? _readComposerTag(String path) {
  try {
    final tag = readAllMetadata(File(path), getImage: false);
    if (tag is Mp3Metadata) {
      return _nonEmptyTag(tag.composer);
    }
    if (tag is ApeMetadata) {
      return _nonEmptyTag(tag.composer);
    }
    if (tag is VorbisMetadata) {
      if (tag.composer.isEmpty) return null;
      return _nonEmptyTag(tag.composer.join(', '));
    }
  } catch (_) {}
  return null;
}

String? _nonEmptyTag(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

({int? durationMs, int? bitrateKbps}) _readWithAudioMetadataReader(String path) {
  try {
    final meta = readMetadata(File(path), getImage: false);
    final d = meta as dynamic;
    final durationMs = _toDurationMs(
      _readInt(() => d.trackDuration),
      _readInt(() => d.durationMs),
      _readInt(() => d.duration),
    );
    final bitrateKbps = _toBitrateKbps(
      _readInt(() => d.bitrate),
      _readInt(() => d.bitRate),
      _readInt(() => d.audioBitrate),
      _readInt(() => d.audioBitRate),
    );
    return (durationMs: durationMs, bitrateKbps: bitrateKbps);
  } catch (_) {
    return (durationMs: null, bitrateKbps: null);
  }
}

Future<({int? durationMs, int? bitrateKbps})> _readWithMetadataGod(
  String path,
) async {
  try {
    final meta = await MetadataGod.readMetadata(file: path);
    final d = meta as dynamic;
    final durationMs = _toDurationMs(
      _readInt(() => d.durationMs),
      _readInt(() => d.duration),
      _readInt(() => d.trackDuration),
    );
    final bitrateKbps = _toBitrateKbps(
      _readInt(() => d.bitrate),
      _readInt(() => d.bitRate),
      _readInt(() => d.audioBitrate),
      _readInt(() => d.audioBitRate),
    );
    return (durationMs: durationMs, bitrateKbps: bitrateKbps);
  } catch (_) {
    return (durationMs: null, bitrateKbps: null);
  }
}

int? _readInt(Object? Function() getter) {
  try {
    final value = getter();
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
  } catch (_) {}
  return null;
}

int? _toDurationMs(int? a, int? b, int? c) {
  final raw = a ?? b ?? c;
  if (raw == null || raw <= 0) return null;
  // Heuristic: treat tiny values as seconds.
  if (raw < 2000) return raw * 1000;
  return raw;
}

int? _toBitrateKbps(int? a, int? b, int? c, int? d) {
  final raw = a ?? b ?? c ?? d;
  if (raw == null || raw <= 0) return null;
  // Heuristic: if value looks like bps, convert to kbps.
  if (raw > 3200) return (raw / 1000).round();
  return raw;
}
