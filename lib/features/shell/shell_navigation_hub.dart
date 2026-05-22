import '../../models/youtube_channel_ref.dart';

/// Shell navigation callbacks registered by [MainShell].
class ShellNavigationHub {
  ShellNavigationHub._();

  static void Function({YoutubeChannelRef? initialChannel})? goOnlineSearch;

  static void navigateToOnlineSearch({YoutubeChannelRef? initialChannel}) {
    goOnlineSearch?.call(initialChannel: initialChannel);
  }
}
