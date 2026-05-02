import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// **Step B strategy (Android):** ask for audio-library access first (`READ_MEDIA_AUDIO`
/// on API 33+), then legacy storage (`READ_EXTERNAL_STORAGE` on API ≤32). Folder choice
/// uses the system picker ([`file_picker`]), which grants a tree without needing
/// all-files access when the platform returns a readable file path.
///
/// Desktop / iOS: no extra gate here; picking and scanning still run.
Future<bool> ensureCanReadMusicFiles(BuildContext context) async {
  if (kIsWeb) {
    return true;
  }
  if (defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }

  bool granted(PermissionStatus s) => s.isGranted || s.isLimited;

  if (granted(await Permission.audio.status)) {
    return true;
  }
  final audioReq = await Permission.audio.request();
  if (granted(audioReq)) {
    return true;
  }

  if (granted(await Permission.storage.status)) {
    return true;
  }
  final storageReq = await Permission.storage.request();
  if (granted(storageReq)) {
    return true;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Allow music / storage access to scan this folder.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }
  return false;
}

/// Opens a directory picker. On Android this often goes through the Storage Access
/// Framework; the result should be an absolute path when the plug-in can map the tree.
Future<String?> pickMusicDirectory() async {
  return FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose music folder');
}
