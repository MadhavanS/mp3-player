import 'dart:io';

import 'package:path/path.dart' as p;

import 'song_file_info.dart';

Future<SongFileInfo> readSongFileInfo(String? filePath) async {
  final raw = filePath?.trim() ?? '';
  if (raw.isEmpty) {
    return const SongFileInfo(
      fileName: 'Unknown',
      folderPath: 'Unknown',
      sizeBytes: null,
    );
  }

  int? sizeBytes;
  try {
    final st = await File(raw).stat();
    sizeBytes = st.size;
  } catch (_) {
    sizeBytes = null;
  }

  return SongFileInfo(
    fileName: p.basename(raw),
    folderPath: p.dirname(raw),
    sizeBytes: sizeBytes,
  );
}
