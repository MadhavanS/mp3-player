import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/track_item.dart';
import '../../services/youtube_audio_download_controller.dart';
import '../../widgets/action_pill_toast.dart';

/// Starts saving YouTube audio; progress is shown on Now Playing (no modal).
Future<bool> showYoutubeSaveAudioDialog(
  BuildContext context,
  TrackItem track,
) async {
  if (kIsWeb) {
    ActionPillToast.show(
      context,
      'Saving audio is not supported on web',
    );
    return false;
  }

  final id = track.youtubeVideoId?.trim() ?? '';
  if (id.isNotEmpty &&
      (YoutubeAudioDownloadController.instance.isDownloading(id) ||
          YoutubeAudioDownloadController.instance.isQueued(id))) {
    reportYoutubeAudioDownloadEnqueue(context, track, enqueued: false);
    return false;
  }

  final ok = await startYoutubeAudioSave(track);
  if (context.mounted) {
    reportYoutubeAudioDownloadEnqueue(context, track, enqueued: ok);
  }
  return ok;
}

/// Pill feedback after tapping save/download (queue only — not saved yet).
void reportYoutubeAudioDownloadEnqueue(
  BuildContext context,
  TrackItem track, {
  required bool enqueued,
}) {
  if (!context.mounted) return;
  if (enqueued) {
    ActionPillToast.show(
      context,
      'Download started — see Downloads tab',
      icon: Icons.download_rounded,
    );
    return;
  }
  final id = track.youtubeVideoId?.trim() ?? '';
  final dl = YoutubeAudioDownloadController.instance;
  if (id.isNotEmpty && (dl.isDownloading(id) || dl.isQueued(id))) {
    ActionPillToast.show(context, 'Already in download queue');
    return;
  }
  ActionPillToast.show(
    context,
    'Could not start download',
    icon: Icons.cloud_off_outlined,
  );
}
