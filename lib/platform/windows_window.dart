import 'windows_window_impl_stub.dart'
    if (dart.library.io) 'windows_window_impl_io.dart' as impl;

export 'windows_window_constants.dart';

/// Initializes desktop window chrome on Windows before [runApp].
/// No-op on web and non-Windows [dart:io] platforms.
Future<void> initWindowsWindowOnLaunch() => impl.initWindowsWindowOnLaunchImpl();

/// Persists and applies always-on-top (Windows only).
Future<void> setWindowsAlwaysOnTop(bool value) =>
    impl.setWindowsAlwaysOnTopImpl(value);
