import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'windows_window_constants.dart';

bool _windowManagerReady = false;
bool _windowShown = false;

/// Only [windowManager.ensureInitialized] — safe before [runApp].
Future<void> prepareWindowsWindowManagerImpl() async {
  if (!Platform.isWindows) return;
  if (_windowManagerReady) return;
  await windowManager.ensureInitialized();
  _windowManagerReady = true;
}

/// Shows the native window once Flutter has painted at least one frame.
Future<void> showWindowsWindowWhenReadyImpl() async {
  if (!Platform.isWindows || _windowShown) return;
  if (!_windowManagerReady) {
    await prepareWindowsWindowManagerImpl();
  }

  final prefs = await SharedPreferences.getInstance();
  final alwaysOnTop = prefs.getBool(kWindowsAlwaysOnTopPrefKey) ?? false;

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(420, 896),
      minimumSize: const Size(360, 480),
      center: true,
      title: 'MadPlayer',
      alwaysOnTop: alwaysOnTop,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  _windowShown = true;
}

Future<void> setWindowsAlwaysOnTopImpl(bool value) async {
  if (!Platform.isWindows) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kWindowsAlwaysOnTopPrefKey, value);
  await windowManager.setAlwaysOnTop(value);
}
