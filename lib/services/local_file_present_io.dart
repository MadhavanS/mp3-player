import 'dart:io';

/// Returns whether [path] looks like a reachable local file.
/// Keeps `content:` URIs (Android) — existence is not verified here.
bool localFileStillPresent(String path) {
  if (path.isEmpty) return false;
  if (path.startsWith('content:')) return true;
  try {
    return File(path).existsSync();
  } catch (_) {
    return true;
  }
}
