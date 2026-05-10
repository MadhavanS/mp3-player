import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'windows_window_constants.dart';

Future<void> initWindowsWindowOnLaunchImpl() async {
  if (!Platform.isWindows) return;

  await windowManager.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final alwaysOnTop = prefs.getBool(kWindowsAlwaysOnTopPrefKey) ?? false;

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(420, 896),
      minimumSize: const Size(360, 480),
      center: true,
      title: 'MP3 Player',
      alwaysOnTop: alwaysOnTop,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

Future<void> setWindowsAlwaysOnTopImpl(bool value) async {
  if (!Platform.isWindows) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kWindowsAlwaysOnTopPrefKey, value);
  await windowManager.setAlwaysOnTop(value);
}
