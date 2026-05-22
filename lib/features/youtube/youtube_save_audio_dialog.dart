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

  if (YoutubeAudioDownloadController.instance.isRunning) {
    ActionPillToast.show(context, 'Another save is already in progress');
    return false;
  }

  final ok = await startYoutubeAudioSave(track);
  if (context.mounted && ok) {
    ActionPillToast.show(context, 'Audio saved');
  }
  return ok;
}
