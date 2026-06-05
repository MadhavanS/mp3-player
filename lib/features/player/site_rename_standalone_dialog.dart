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

String _composerPlain(TrackItem t) => (t.composer ?? '').trim();

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

  final ctx = siteRenameContextFromTrack(snap);
  final suggestion = computeSiteRename(
    filePath: path,
    albumFromTags: ctx.album,
    artistFromTags: ctx.artist,
    titleFromTags: ctx.title,
    genreFromTags: ctx.genre,
    composerFromTags: ctx.composer,
  );

  if (!suggestion.hasSuggestion) {
    ActionPillToast.showUsingRootNavigator(
      'No cleanup rule matched',
      icon: Icons.auto_fix_high_outlined,
      uppercaseLabel: true,
    );
    return;
  }

  if (suggestion.matchesCurrent(
    title: ctx.title,
    artist: ctx.artist,
    album: ctx.album ?? '',
    genre: ctx.genre,
    composer: ctx.composer,
  )) {
    ActionPillToast.showUsingRootNavigator(
      'Already clean',
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
              '(removed)',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Composer (tag)', style: Theme.of(ctx).textTheme.labelSmall),
            Text(
              '(removed)',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
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
  final resumePos = player.position;
  var stoppedForEdit = false;
  var saveSucceeded = false;

  try {
    var isCurrent = player.isCurrentTrackFilePath(originalPath);
    if (isCurrent) {
      await player.stopForExternalFileEdit();
      stoppedForEdit = true;
    }

    var newPath = originalPath;
    if (suggestion.filenameChanged) {
      newPath = await renameMp3File(
        originalPath,
        suggestion.newBasenameWithoutExt,
      );
      player.registerLibraryPathRename(originalPath, newPath);
    }
    if (!isCurrent && newPath != originalPath) {
      isCurrent = await player.shouldRewirePlaybackForRenamedFile(
        originalPath,
        newPath,
      );
      if (isCurrent && !stoppedForEdit) {
        await player.stopForExternalFileEdit();
        stoppedForEdit = true;
      }
    }

    final snapBeforeWrite = await readAudioMetadata(
      TrackItem.fromFilePath(newPath),
    );
    final albumBefore =
        snapBeforeWrite.metaLine == 'mp3' ? '' : snapBeforeWrite.metaLine;
    final artistBefore = snapBeforeWrite.artist == 'Unknown artist'
        ? ''
        : snapBeforeWrite.artist.trim();
    final tags = resolveTagsForWrite(
      filePath: newPath,
      editorTitle: suggestion.suggestedTitle,
      editorArtist: suggestion.suggestedArtist,
      editorAlbum: suggestion.suggestedAlbum,
      editorGenre: suggestion.suggestedGenre,
      editorComposer: suggestion.suggestedComposer,
      initialTitle: '',
      initialArtist: '',
      initialAlbum: '',
      initialGenre: '',
      initialComposer: '',
      embeddedTitle: snapBeforeWrite.title,
      embeddedArtist: artistBefore,
      embeddedAlbum: albumBefore,
      embeddedGenre: snapBeforeWrite.genres
          .replaceAll('#', ' ')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' '),
      embeddedComposer: _composerPlain(snapBeforeWrite),
      clearGenre: true,
      clearComposer: true,
    );
    await writeEmbeddedAudioTags(
      filePath: newPath,
      title: tags.title,
      album: tags.album,
      artist: tags.artist,
      genre: tags.genre,
      composer: tags.composer,
      artEdit: AlbumArtEditKind.keep,
    );

    final base = TrackItem.fromFilePath(newPath);
    final refreshed = await readAudioMetadata(base);
    if (suggestion.filenameChanged) {
      await player.replaceTrackPath(
        originalPath,
        refreshed,
        resumePosition: isCurrent ? resumePos : null,
        resumePlaying: isCurrent ? wasPlaying : null,
      );
      // Await DB writes so a concurrent background sync doesn't read stale
      // data and overwrite the in-memory update with the old metadata.
      unawaited(() async {
        await SongMetadataCache.deletePaths([originalPath]);
        await SongMetadataCache.saveTracks([refreshed]);
      }());
    } else {
      player.updateTrackByPath(
        originalPath,
        refreshed,
        refreshNotificationArt: false,
      );
      if (isCurrent) {
        player.reloadCurrentSourceAfterTagWriteUnawaited(
          resumePosition: resumePos,
          resumePlaying: wasPlaying,
        );
      }
    }
    if (!suggestion.filenameChanged) {
      unawaited(SongMetadataCache.saveTracks([refreshed]));
    }

    saveSucceeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ActionPillToast.showUsingRootNavigator(
        'File updated',
        uppercaseLabel: true,
      );
    });
  } on StateError catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    final alreadyExists = msg.toLowerCase().contains('target already exists');
    if (alreadyExists) {
      ActionPillToast.showUsingRootNavigator(
        renameTargetExistsUserMessage(e),
        uppercaseLabel: false,
      );
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
    }
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
    if (stoppedForEdit && !saveSucceeded) {
      player.reloadCurrentSourceAfterTagWriteUnawaited(
        resumePosition: resumePos,
        resumePlaying: wasPlaying,
      );
    }
  }
}
