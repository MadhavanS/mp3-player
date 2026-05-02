import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/storage_access.dart';
import '../../services/track_metadata.dart';
import '../../services/track_tag_writer.dart';
import '../../theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    _title = TextEditingController(text: t.title);
    _artist = TextEditingController(text: t.artist == 'Unknown artist' ? '' : t.artist);
    _album = TextEditingController(text: t.metaLine == 'mp3' ? '' : t.metaLine);
    _genre = TextEditingController(text: _genreTextFromTrack(t));
  }

  @override
  void dispose() {
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
        messenger.showSnackBar(const SnackBar(content: Text('Tags saved to file.')));
        Navigator.of(context).pop();
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
                    color: AppColors.textMuted.withValues(alpha: 0.4),
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
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
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
                              color: AppColors.navy.withValues(alpha: 0.08),
                              child: Icon(
                                Icons.album_outlined,
                                size: 48,
                                color: AppColors.textSecondary.withValues(alpha: 0.6),
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
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _artist,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Artist',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _album,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Album',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _genre,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Genre (comma-separated)',
                  border: OutlineInputBorder(),
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
