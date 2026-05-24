import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

Future<String?> deleteMusicFileOrError(String path) async {
  final normalized = p.normalize(path.trim());
  if (normalized.isEmpty) {
    return 'Invalid file path.';
  }

  try {
    final f = File(normalized);
    if (!await f.exists()) return null;
    await f.delete();
    return null;
  } on FileSystemException catch (e) {
    debugPrint('deleteMusicFileOrError($normalized): $e');
    final code = e.osError?.errorCode;
    if (code == 13 || code == 1) {
      return 'Permission denied. On Android, allow "All files access" for this app in Settings, then try again.';
    }
    if (code == 16) {
      return 'File is in use. Stop playback and try again.';
    }
    final msg = e.message.trim();
    if (msg.isNotEmpty) {
      if (msg.toLowerCase().contains('permission')) {
        return 'Permission denied. On Android, allow "All files access" for this app in Settings, then try again.';
      }
      return msg;
    }
    return 'Could not delete file.';
  } catch (e, st) {
    debugPrint('deleteMusicFileOrError($normalized): $e\n$st');
    return e.toString();
  }
}
