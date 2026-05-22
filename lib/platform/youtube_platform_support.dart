import 'package:flutter/foundation.dart';

import '../models/library_tab_id.dart';
import '../services/library_tabs_store.dart';

/// Whether YouTube online search / streaming is offered on this platform.
///
/// Android (and other mobile targets) use ExoPlayer with HTTP headers for
/// YouTube CDN URLs. The Windows desktop build uses [just_audio_windows], which
/// is unreliable for those streams (threading warnings, manifest timeouts).
abstract final class YoutubePlatformSupport {
  YoutubePlatformSupport._();

  static bool get isOnlinePlaybackSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform != TargetPlatform.windows;
  }

  static bool isYoutubeLibraryTab(LibraryTabId id) =>
      id == LibraryTabId.savedYoutubeAudio ||
      id == LibraryTabId.savedYoutubeLinks ||
      id == LibraryTabId.youtubeDownloads;

  static bool isYoutubeOnlyTab(LibraryTabId id) =>
      isYoutubeLibraryTab(id) || id == LibraryTabId.onlineSearch;

  static bool includeLibraryTab(LibraryTabId id) =>
      isOnlinePlaybackSupported || !isYoutubeOnlyTab(id);

  static List<LibraryTabId> filterLibraryTabIds(Iterable<LibraryTabId> ids) =>
      ids.where(includeLibraryTab).toList(growable: false);

  static List<LibraryTabRow> filterLibraryTabRows(List<LibraryTabRow> rows) =>
      rows.where((r) => includeLibraryTab(r.id)).toList(growable: false);
}
