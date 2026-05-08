import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/site_audio_rename.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/storage_access.dart';
import '../../services/track_metadata.dart';
import '../../services/track_tag_writer.dart';
import '../../widgets/action_pill_toast.dart';

String _genrePlain(TrackItem t) {
  return t.genres.replaceAll('#', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
}

Future<void> _resumePlaybackAfterExternalWrite(
  PlayerController player,
  bool resume,
  Duration resumePosition,
) async {
  try {
    await player.reloadCurrentSource().timeout(const Duration(seconds: 20));
    var target = resumePosition;
    final dur = player.audioPlayer.duration;
    if (dur != null && target > dur) {
      target = dur;
    }
    if (target.isNegative) {
      target = Duration.zero;
    }
    await player.seek(target);
    if (resume) {
      await player.play();
    }
  } catch (e, st) {
    debugPrint('Playback reload after rename: $e\n$st');
  }
}

/// Shows only the “Clean site-style filename” confirmation (no tag editor sheet).
Future<void> showStandaloneSiteRenameDialog(
  BuildContext context,
  TrackItem track,
) async {
  if (kIsWeb) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This tool needs local files.')),
    );
    return;
  }
  final path = track.filePath;
  if (path == null || path.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This track has no file path.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);

  TrackItem snap;
  try {
    snap = await readAudioMetadata(track);
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Could not analyze file: $e')),
    );
    return;
  }

  if (!context.mounted) return;

  final albumTag = snap.metaLine == 'mp3' ? null : snap.metaLine;
  final artistTag = snap.artist == 'Unknown artist' ? '' : snap.artist;
  final suggestion = computeSiteRename(
    filePath: path,
    albumFromTags: albumTag,
    artistFromTags: artistTag,
    titleFromTags: snap.title,
    genreFromTags: _genrePlain(snap),
  );

  if (!suggestion.hasSuggestion) {
    ActionPillToast.showUsingRootNavigator(
      'No Auto Rename',
      icon: Icons.auto_fix_high_outlined,
      uppercaseLabel: true,
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clean site-style filename'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Uses the same rules as your tag-editor project (filename + tags). '
              'Review before updating the file.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Filename', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              '${suggestion.originalBasenameWithoutExt}.mp3'
              '\n→ ${suggestion.newBasenameWithoutExt}.mp3',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text('Album (tag)', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              suggestion.suggestedAlbum,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Artist (tag)', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              suggestion.suggestedArtist,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Title (tag)', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              suggestion.suggestedTitle,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Genre (tag)', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              suggestion.suggestedGenre,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            unawaited(
              _applySiteRenameStandalone(
                context,
                path,
                suggestion,
                snapBefore: snap,
              ),
            );
          },
          child: const Text('Rename & save'),
        ),
      ],
    ),
  );
}

Future<void> _applySiteRenameStandalone(
  BuildContext context,
  String originalPath,
  SiteRenameSuggestion suggestion, {
  required TrackItem snapBefore,
}) async {
  if (!await ensureCanWriteLibraryFiles(context)) return;
  if (!context.mounted) return;

  final player = PlayerController.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final wasPlaying = player.isPlaying;
  final resumePosition = player.position;
  var updateSucceeded = false;

  await player.stopForExternalFileEdit();

  try {
    var newPath = originalPath;
    if (suggestion.filenameChanged) {
      newPath = await renameMp3File(
        originalPath,
        suggestion.newBasenameWithoutExt,
      );
    }

    await writeEmbeddedAudioTags(
      filePath: newPath,
      title: suggestion.suggestedTitle,
      album: suggestion.suggestedAlbum,
      artist: suggestion.suggestedArtist,
      genre: suggestion.suggestedGenre,
      artEdit: AlbumArtEditKind.keep,
    );

    final base = TrackItem.fromFilePath(newPath);
    final refreshed = await readAudioMetadata(base);
    if (suggestion.filenameChanged) {
      player.replaceTrackPath(originalPath, refreshed);
      unawaited(SongMetadataCache.deletePaths([originalPath]));
    } else {
      player.updateTrackByPath(originalPath, refreshed);
    }
    unawaited(SongMetadataCache.saveTracks([refreshed]));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ActionPillToast.showUsingRootNavigator(
        'File updated',
        uppercaseLabel: true,
      );
    });
    updateSucceeded = true;
    unawaited(
      _resumePlaybackAfterExternalWrite(player, wasPlaying, resumePosition),
    );
  } on StateError catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    final alreadyExists = msg.toLowerCase().contains('target already exists');
    messenger?.showSnackBar(
      SnackBar(content: Text(alreadyExists ? 'Already exists' : msg)),
    );
  } on UnsupportedError catch (e) {
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text(e.message ?? 'Not supported.')),
    );
  } on FileSystemException catch (e) {
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not update file. (${e.message})')),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text('Error: $e')));
  } finally {
    if (!updateSucceeded) {
      unawaited(
        _resumePlaybackAfterExternalWrite(player, wasPlaying, resumePosition),
      );
    }
  }
}
