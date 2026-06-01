import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../audio/player_controller.dart';
import '../../../models/track_item.dart';
import '../../../services/library_path_migration.dart';
import '../../../services/site_audio_rename.dart';
import '../../../services/song_metadata_cache.dart';
import '../../../services/storage_access.dart';
import '../../../services/track_metadata.dart';
import '../../../services/track_tag_writer.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/action_pill_toast.dart';
import '../catalog/youtube_library_catalog.dart';
import '../storage/youtube_track_store.dart';

String _genrePlain(TrackItem t) {
  return t.genres.replaceAll('#', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _sanitizeBasename(String raw) {
  return raw
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<String> _renameKeepingExtension(
  String oldPath,
  String newBasenameWithoutExt,
) async {
  final old = File(oldPath);
  if (!await old.exists()) {
    throw StateError('File not found.');
  }
  final ext = p.extension(oldPath);
  final base = _sanitizeBasename(newBasenameWithoutExt);
  if (base.isEmpty) {
    throw StateError('Filename cannot be empty.');
  }
  final newPath = p.normalize(p.join(old.parent.path, '$base$ext'));
  final normOld = p.normalize(oldPath);
  if (normOld == newPath) return normOld;
  if (await File(newPath).exists()) {
    throw StateError('Target already exists: ${p.basename(newPath)}');
  }
  await old.rename(newPath);
  return newPath;
}

/// Simple rename: track title tag + filename (YouTube Library only).
Future<void> showYoutubeLibraryRenameDialog(
  BuildContext context,
  TrackItem track,
) async {
  if (kIsWeb) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rename needs local files.')),
    );
    return;
  }

  final path = track.filePath?.trim();
  if (path == null || path.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This track has no file path.')),
    );
    return;
  }

  final ext = p.extension(path);
  final initialBasename = p.basenameWithoutExtension(path);
  final initialTitle = track.title.trim();

  final result = await showDialog<({String title, String basename})?>(
    context: context,
    builder: (ctx) => _YoutubeLibraryRenameDialog(
      ext: ext,
      initialTitle: initialTitle,
      initialBasename: initialBasename,
    ),
  );

  if (result == null || !context.mounted) return;

  final newTitle = result.title.trim();
  final newBasename = _sanitizeBasename(result.basename);

  if (newTitle.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Track name cannot be empty.')),
    );
    return;
  }
  if (newBasename.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File name cannot be empty.')),
    );
    return;
  }

  await _applyYoutubeLibraryRename(
    context,
    track: track,
    originalPath: path,
    newTitle: newTitle,
    newBasenameWithoutExt: newBasename,
  );
}

class _YoutubeLibraryRenameDialog extends StatefulWidget {
  const _YoutubeLibraryRenameDialog({
    required this.ext,
    required this.initialTitle,
    required this.initialBasename,
  });

  final String ext;
  final String initialTitle;
  final String initialBasename;

  @override
  State<_YoutubeLibraryRenameDialog> createState() =>
      _YoutubeLibraryRenameDialogState();
}

class _YoutubeLibraryRenameDialogState extends State<_YoutubeLibraryRenameDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _filenameController;
  late bool _sameName;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _filenameController = TextEditingController(text: widget.initialBasename);
    _sameName = widget.initialTitle == widget.initialBasename ||
        _sanitizeBasename(widget.initialTitle) == widget.initialBasename;
    _titleController.addListener(_onTitleChanged);
    _filenameController.addListener(_onFilenameChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _filenameController.removeListener(_onFilenameChanged);
    _titleController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    if (!_sameName || _syncing) return;
    _syncing = true;
    _filenameController.text = _sanitizeBasename(_titleController.text);
    _syncing = false;
  }

  void _onFilenameChanged() {
    if (!_sameName || _syncing) return;
    _syncing = true;
    _titleController.text = _filenameController.text;
    _syncing = false;
  }

  void _onSameNameChanged(bool? value) {
    if (value == null) return;
    setState(() {
      _sameName = value;
      if (_sameName) {
        _syncing = true;
        _filenameController.text = _sanitizeBasename(_titleController.text);
        _syncing = false;
      }
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    final basename = _sameName
        ? _sanitizeBasename(title)
        : _sanitizeBasename(_filenameController.text);
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track name cannot be empty.')),
      );
      return;
    }
    if (basename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File name cannot be empty.')),
      );
      return;
    }
    Navigator.pop(context, (title: title, basename: basename));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return AlertDialog(
      backgroundColor: pal.surface,
      title: Text(
        'Rename track',
        style: theme.textTheme.titleLarge?.copyWith(color: pal.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              value: _sameName,
              onChanged: _onSameNameChanged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Same name for track and file',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textPrimary,
                ),
              ),
              subtitle: _sameName
                  ? Text(
                      'File name uses safe characters for your device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pal.textSecondary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Track name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _filenameController,
              readOnly: _sameName,
              decoration: InputDecoration(
                labelText: 'File name',
                suffixText: widget.ext,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<void> _applyYoutubeLibraryRename(
  BuildContext context, {
  required TrackItem track,
  required String originalPath,
  required String newTitle,
  required String newBasenameWithoutExt,
}) async {
  if (!await ensureCanWriteLibraryFiles(context)) return;
  if (!context.mounted) return;

  final player = PlayerController.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final wasPlaying = player.isPlaying;
  final resumePos = player.position;
  var stoppedForEdit = false;
  var saveSucceeded = false;
  final filenameChanged =
      newBasenameWithoutExt != p.basenameWithoutExtension(originalPath);
  final titleChanged = newTitle != track.title.trim();

  if (!filenameChanged && !titleChanged) return;

  try {
    var isCurrent = player.isCurrentTrackFilePath(originalPath);
    if (isCurrent) {
      await player.stopForExternalFileEdit();
      stoppedForEdit = true;
    }

    var newPath = originalPath;
    if (filenameChanged) {
      newPath = await _renameKeepingExtension(
        originalPath,
        newBasenameWithoutExt,
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

    if (titleChanged) {
      await writeEmbeddedAudioTags(
        filePath: newPath,
        title: newTitle,
        artist: artistBefore,
        album: albumBefore,
        genre: _genrePlain(snapBeforeWrite),
        composer: (snapBeforeWrite.composer ?? '').trim(),
        artEdit: AlbumArtEditKind.keep,
      );
    }

    final refreshed = await readAudioMetadata(TrackItem.fromFilePath(newPath));

    final record = await YoutubeTrackStore.instance.findByLocalPath(originalPath) ??
        await YoutubeTrackStore.instance.findByLocalPath(newPath);
    if (record != null) {
      record
        ..title = refreshed.title.trim().isNotEmpty ? refreshed.title : newTitle
        ..localPath = newPath;
      await YoutubeTrackStore.instance.save(record);
    }

    if (filenameChanged) {
      await migrateLibraryPathReferences(originalPath, newPath);
      await player.replaceTrackPath(
        originalPath,
        refreshed,
        resumePosition: isCurrent ? resumePos : null,
        resumePlaying: isCurrent ? wasPlaying : null,
      );
      await SongMetadataCache.deletePaths([originalPath]);
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
    unawaited(SongMetadataCache.saveTracks([refreshed]));
    unawaited(YoutubeLibraryCatalog.instance.reload());

    saveSucceeded = true;
    if (context.mounted) {
      ActionPillToast.show(context, 'Renamed', uppercaseLabel: true);
    }
  } on StateError catch (e) {
    if (!context.mounted) return;
    final msg = e.message;
    if (msg.startsWith('Target already exists:')) {
      ActionPillToast.show(
        context,
        renameTargetExistsUserMessage(e),
        uppercaseLabel: false,
      );
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
    }
  } on UnsupportedError catch (e) {
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text(e.message ?? 'Not supported for this file type.')),
    );
  } on FileSystemException catch (e) {
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not rename file. (${e.message})')),
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
