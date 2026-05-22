import 'package:flutter/material.dart';

import '../../services/saved_youtube_audio_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';

/// Renames a saved YouTube audio entry (display title and file on disk).
Future<bool> showRenameSavedYoutubeAudioDialog(
  BuildContext context, {
  required String videoId,
  required String currentTitle,
}) async {
  final controller = TextEditingController(text: currentTitle);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final pal = ctx.palette;
      return AlertDialog(
        title: const Text('Rename saved audio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Song title',
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: pal.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.controlAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
  if (result != true) return false;

  final newTitle = controller.text.trim();
  controller.dispose();
  if (newTitle.isEmpty) return false;

  final ok = await SavedYoutubeAudioStore.renameSaved(
    videoId: videoId,
    newTitle: newTitle,
  );
  if (context.mounted) {
    ActionPillToast.show(
      context,
      ok ? 'Renamed' : 'Could not rename',
      icon: ok ? Icons.check_rounded : Icons.error_outline_rounded,
    );
  }
  return ok;
}
