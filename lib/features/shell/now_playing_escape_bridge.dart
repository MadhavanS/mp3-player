/// Tracks whether the Now Playing route is mounted (for global Escape routing).
class NowPlayingRouteMark {
  NowPlayingRouteMark._();

  static int _depth = 0;

  static bool get isOpen => _depth > 0;

  static void enter() => _depth++;

  static void leave() {
    _depth = (_depth - 1).clamp(0, 100);
  }
}

/// [MainShell] registers a Windows-only Escape handler to close Now Playing with the correct library tab.
class NowPlayingWindowsEsc {
  NowPlayingWindowsEsc._();

  static Future<void> Function()? handler;
}

/// Blocks [NowPlayingScreen]'s [CallbackShortcuts] from popping again after global Escape already did.
class NowPlayingEscDuplicatePopGuard {
  NowPlayingEscDuplicatePopGuard._();

  static bool blockShortcutCollapse = false;
}
