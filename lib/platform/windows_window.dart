import 'windows_window_impl_stub.dart'
    if (dart.library.io) 'windows_window_impl_io.dart' as impl;

export 'windows_window_constants.dart';

/// Fast sync setup before [runApp] (does not wait to show the window).
Future<void> prepareWindowsWindowManager() =>
    impl.prepareWindowsWindowManagerImpl();

/// Shows the window after the first frame (call from a post-frame callback).
Future<void> showWindowsWindowWhenReady() =>
    impl.showWindowsWindowWhenReadyImpl();

/// Persists and applies always-on-top (Windows only).
Future<void> setWindowsAlwaysOnTop(bool value) =>
    impl.setWindowsAlwaysOnTopImpl(value);
