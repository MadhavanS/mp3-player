import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track_item.dart';

Future<Uri?> uriForNotificationAlbumArt(TrackItem track) async {
  final bytes = track.albumArtBytes;
  if (bytes == null || bytes.isEmpty) return null;

  final ext =
      bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 ? 'png' : 'jpg';

  final dir = await getTemporaryDirectory();
  final quick = bytes.length < 8
      ? bytes.hashCode
      : Object.hash(
          bytes[0],
          bytes[1],
          bytes[bytes.length ~/ 2],
          bytes[bytes.length - 1],
          bytes.length,
        );
  final key = Object.hash(track.filePath ?? track.title, quick).abs();
  final path = p.join(dir.path, 'media_notify_art_$key.$ext');
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return Uri.file(file.absolute.path);
}
