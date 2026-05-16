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
///
/// [showDialogIfDenied] controls whether a snackbar with a "Settings" button is
/// shown when permission is denied.  Pass `false` when silently re-checking on
/// app resume so the UI is not interrupted.
Future<bool> ensureCanReadMusicFiles(
  BuildContext context, {
  bool showDialogIfDenied = true,
}) async {
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
  // Only show the system permission prompt when allowed (on initial startup or
  // when the user is actively trying to add a folder).
  if (showDialogIfDenied) {
    final audioReq = await Permission.audio.request();
    if (granted(audioReq)) {
      return true;
    }
  } else {
    // Just check current status — don't prompt.
    return false;
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
        content: const Text(
          'Music access is required to scan your library. Tap Settings to enable it.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }
  return false;
}

/// **Android:** Reading audio (scan) is not enough to **rewrite** files in a user-picked
/// folder. On API 30+ you typically need **All files access** ([`MANAGE_EXTERNAL_STORAGE`]).
/// On API ≤32, [Permission.storage] may be sufficient.
///
/// Call this before saving ID3 tags. Returns false if the user must enable access in Settings.
Future<bool> ensureCanWriteLibraryFiles(BuildContext context) async {
  if (kIsWeb) {
    return true;
  }
  if (defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }

  bool granted(PermissionStatus s) => s.isGranted || s.isLimited;

  if (await Permission.manageExternalStorage.isGranted) {
    return true;
  }
  final manage = await Permission.manageExternalStorage.request();
  if (manage.isGranted) {
    return true;
  }

  if (granted(await Permission.storage.status)) {
    return true;
  }
  final storage = await Permission.storage.request();
  if (granted(storage)) {
    return true;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'To save tags on Android, allow "All files access" (or storage) for this app in system settings.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            openAppSettings();
          },
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
