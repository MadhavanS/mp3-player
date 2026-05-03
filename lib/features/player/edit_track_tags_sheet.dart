import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/site_audio_rename.dart';
import '../../services/storage_access.dart';
import '../../services/track_metadata.dart';
import '../../services/track_tag_writer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';

String _genreTextFromTrack(TrackItem t) {
  return t.genres.replaceAll('#', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _mimeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Future<void> _resumePlaybackAfterTagSave(
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
    debugPrint('Playback reload after tag save: $e\n$st');
  }
}

class EditTrackTagsSheet extends StatefulWidget {
  const EditTrackTagsSheet({super.key, required this.track});

  final TrackItem track;

  @override
  State<EditTrackTagsSheet> createState() => _EditTrackTagsSheetState();
}

class _EditTrackTagsSheetState extends State<EditTrackTagsSheet> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _genre;

  AlbumArtEditKind _artEdit = AlbumArtEditKind.keep;
  Uint8List? _pickedCoverBytes;
  String _pickedCoverMime = 'image/jpeg';

  bool _saving = false;
  bool _siteRenameBusy = false;

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    _title = TextEditingController(text: t.title);
    _artist = TextEditingController(text: t.artist == 'Unknown artist' ? '' : t.artist);
    _album = TextEditingController(text: t.metaLine == 'mp3' ? '' : t.metaLine);
    _genre = TextEditingController(text: _genreTextFromTrack(t));
    _title.addListener(_onTagFieldChanged);
    _artist.addListener(_onTagFieldChanged);
    _album.addListener(_onTagFieldChanged);
    _genre.addListener(_onTagFieldChanged);
  }

  void _onTagFieldChanged() {
    if (mounted) setState(() {});
  }

  Widget? _clearFieldSuffix(TextEditingController controller) {
    if (_saving || controller.text.isEmpty) return null;
    return IconButton(
      icon: const Icon(Icons.clear_rounded, size: 22),
      tooltip: 'Clear field',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        controller.clear();
      },
    );
  }

  @override
  void dispose() {
    _title.removeListener(_onTagFieldChanged);
    _artist.removeListener(_onTagFieldChanged);
    _album.removeListener(_onTagFieldChanged);
    _genre.removeListener(_onTagFieldChanged);
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    super.dispose();
  }

  Uint8List? get _effectivePreviewBytes {
    switch (_artEdit) {
      case AlbumArtEditKind.remove:
        return null;
      case AlbumArtEditKind.replace:
        return _pickedCoverBytes;
      case AlbumArtEditKind.keep:
        return widget.track.albumArtBytes;
    }
  }

  Future<void> _pickCover() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _artEdit = AlbumArtEditKind.replace;
      _pickedCoverBytes = bytes;
      _pickedCoverMime = _mimeFromFileName(f.name);
    });
  }

  void _clearCover() {
    setState(() {
      _artEdit = AlbumArtEditKind.remove;
      _pickedCoverBytes = null;
    });
  }

  void _resetCoverEdit() {
    setState(() {
      _artEdit = AlbumArtEditKind.keep;
      _pickedCoverBytes = null;
    });
  }

  Future<void> _previewSiteRename() async {
    final path = widget.track.filePath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no file path.')),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This tool needs local files.')),
      );
      return;
    }

    setState(() => _siteRenameBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final snap = await readAudioMetadata(widget.track);
      if (!mounted) return;
      final albumTag = snap.metaLine == 'mp3' ? null : snap.metaLine;
      final artistTag =
          snap.artist == 'Unknown artist' ? '' : snap.artist;
      final suggestion = computeSiteRename(
        filePath: path,
        albumFromTags: albumTag,
        artistFromTags: artistTag,
        titleFromTags: snap.title,
      );
      if (!mounted) return;
      if (!suggestion.hasSuggestion) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No cleaner name was suggested.')),
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
                  'Uses the same rules as SongsPK Renamer (filename + tags). '
                  'Review before updating the file.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Filename',
                  style: Theme.of(ctx).textTheme.labelSmall,
                ),
                Text(
                  '${suggestion.originalBasenameWithoutExt}.mp3\n→ ${suggestion.newBasenameWithoutExt}.mp3',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text('Album (tag)', style: Theme.of(ctx).textTheme.labelSmall),
                Text(suggestion.suggestedAlbum, style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text('Title (tag)', style: Theme.of(ctx).textTheme.labelSmall),
                Text(suggestion.suggestedTitle, style: Theme.of(ctx).textTheme.bodyMedium),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _title.text = suggestion.suggestedTitle;
                _album.text = suggestion.suggestedAlbum;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Filled the form — tap Save to write the file.'),
                  ),
                );
              },
              child: const Text('Use in editor'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_applySiteRename(suggestion));
              },
              child: const Text('Rename & save'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Could not analyze file: $e')));
      }
    } finally {
      if (mounted) setState(() => _siteRenameBusy = false);
    }
  }

  Future<void> _applySiteRename(SiteRenameSuggestion suggestion) async {
    final path = widget.track.filePath;
    if (path == null || path.isEmpty) return;

    if (!await ensureCanWriteLibraryFiles(context)) {
      return;
    }
    if (!mounted) return;

    final player = PlayerController.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);
    final wasPlaying = player.isPlaying;
    final resumePosition = player.position;
    await player.stopForExternalFileEdit();

    try {
      var newPath = path;
      if (suggestion.filenameChanged) {
        newPath = await renameMp3File(path, suggestion.newBasenameWithoutExt);
      }

      await writeEmbeddedAudioTags(
        filePath: newPath,
        title: suggestion.suggestedTitle,
        album: suggestion.suggestedAlbum,
        artist: _artist.text,
        genre: _genre.text,
        artEdit: _artEdit,
        newCoverBytes: _pickedCoverBytes,
        newCoverMimeType: _pickedCoverMime,
      );

      final base = TrackItem.fromFilePath(newPath);
      final refreshed = await readAudioMetadata(base);
      if (suggestion.filenameChanged) {
        player.replaceTrackPath(path, refreshed);
      } else {
        player.updateTrackByPath(path, refreshed);
      }

      if (mounted) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ActionPillToast.showUsingRootNavigator(
            'File updated',
            uppercaseLabel: true,
          );
        });
      }
      unawaited(_resumePlaybackAfterTagSave(player, wasPlaying, resumePosition));
    } on StateError catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } on UnsupportedError catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Not supported.')));
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not update file. (${e.message})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final path = widget.track.filePath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no file path.')),
      );
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing tags is not supported on web.')),
      );
      return;
    }

    final player = PlayerController.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!await ensureCanWriteLibraryFiles(context)) {
      return;
    }

    setState(() => _saving = true);
    final wasPlaying = player.isPlaying;
    final resumePosition = player.position;
    await player.stopForExternalFileEdit();
    try {
      await writeEmbeddedAudioTags(
        filePath: path,
        title: _title.text,
        artist: _artist.text,
        album: _album.text,
        genre: _genre.text,
        artEdit: _artEdit,
        newCoverBytes: _pickedCoverBytes,
        newCoverMimeType: _pickedCoverMime,
      );
      final refreshed = await readAudioMetadata(widget.track);
      player.updateTrackByPath(path, refreshed);
      if (mounted) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ActionPillToast.showUsingRootNavigator(
            'Tags saved',
            uppercaseLabel: true,
          );
        });
      }
      unawaited(_resumePlaybackAfterTagSave(player, wasPlaying, resumePosition));
    } on UnsupportedError catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Not supported.')));
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not write the file. On Android, enable "All files access" for this app. (${e.message})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save tags: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit tags',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Changes are written into the MP3 file.',
                style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: (_saving || _siteRenameBusy) ? null : _previewSiteRename,
                  icon: _siteRenameBusy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.primary,
                          ),
                        )
                      : const Icon(Icons.auto_fix_high_outlined, size: 20),
                  label: const Text('Clean site-style name'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _effectivePreviewBytes != null
                          ? Image.memory(
                              _effectivePreviewBytes!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 120,
                              height: 120,
                              color: context.palette.primary.withValues(alpha: 0.12),
                              child: Icon(
                                Icons.album_outlined,
                                size: 48,
                                color: context.palette.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: _saving ? null : _pickCover,
                          icon: const Icon(Icons.image_outlined, size: 20),
                          label: const Text('Cover image'),
                        ),
                        if (_artEdit != AlbumArtEditKind.keep ||
                            widget.track.albumArtBytes != null)
                          TextButton.icon(
                            onPressed: _saving ? null : _clearCover,
                            icon: const Icon(Icons.hide_image_outlined, size: 20),
                            label: const Text('Remove art'),
                          ),
                        if (_artEdit != AlbumArtEditKind.keep)
                          TextButton(
                            onPressed: _saving ? null : _resetCoverEdit,
                            child: const Text('Reset cover'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: const OutlineInputBorder(),
                  suffixIcon: _clearFieldSuffix(_title),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _artist,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Artist',
                  border: const OutlineInputBorder(),
                  suffixIcon: _clearFieldSuffix(_artist),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _album,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Album',
                  border: const OutlineInputBorder(),
                  suffixIcon: _clearFieldSuffix(_album),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _genre,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Genre (comma-separated)',
                  border: const OutlineInputBorder(),
                  suffixIcon: _clearFieldSuffix(_genre),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
