import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../models/track_item.dart';
import '../../../widgets/player_adaptive_controls.dart';

Future<bool> confirmDeleteYoutubeDownload(
  BuildContext context,
  TrackItem track,
) async {
  final path = track.filePath?.trim();
  if (path == null || path.isEmpty) return false;
  final basename = p.basename(path);
  final confirmed = await showPlayerConfirmDialog(
    context: context,
    title: 'Delete download?',
    message:
        'This removes the saved YouTube audio from your device.\n'
        '$basename\n\n'
        'This cannot be undone.',
    cancelLabel: 'Cancel',
    confirmLabel: 'Delete',
    destructive: true,
  );
  return confirmed == true;
}
