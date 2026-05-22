import 'package:flutter/material.dart';

import '../../models/track_item.dart';
import '../../platform/youtube_platform_support.dart';
import '../../models/youtube_channel_ref.dart';
import '../../services/youtube_channel_resolver.dart';
import '../shell/shell_navigation_hub.dart';
import '../../widgets/action_pill_toast.dart';

/// Opens online search scoped to the track's upload channel.
Future<void> openYoutubeChannelTracksFromTrack(
  BuildContext context,
  TrackItem track, {
  bool popNowPlaying = true,
}) async {
  if (!track.isYoutubeStream) return;
  if (!YoutubePlatformSupport.isOnlinePlaybackSupported) {
    if (context.mounted) {
      ActionPillToast.show(
        context,
        'Online search is not available on Windows',
        icon: Icons.info_outline_rounded,
      );
    }
    return;
  }

  YoutubeChannelRef? channel;
  final storedId = track.youtubeChannelId?.trim();
  final artist = track.artist.trim();
  if (storedId != null && storedId.isNotEmpty) {
    channel = YoutubeChannelRef(
      id: storedId,
      title: artist.isEmpty ? 'Channel' : artist,
    );
  } else {
    final videoId = track.youtubeVideoId?.trim();
    if (videoId == null || videoId.isEmpty) return;
    channel = await YoutubeChannelResolver.instance.channelForVideo(videoId);
  }

  if (channel == null) {
    if (context.mounted) {
      ActionPillToast.show(context, 'Could not load channel');
    }
    return;
  }

  if (!context.mounted) return;
  if (popNowPlaying) {
    Navigator.of(context).pop();
  }
  if (!context.mounted) return;

  ShellNavigationHub.navigateToOnlineSearch(initialChannel: channel);
}
