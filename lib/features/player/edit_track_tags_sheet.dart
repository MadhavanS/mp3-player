import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/site_audio_rename.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/storage_access.dart';
import '../../services/track_metadata.dart';
import '../../services/track_tag_writer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';
import '../../services/picker_album_art_loader.dart';
import 'pick_cover_from_library_sheet.dart';

String _genreTextFromTrack(TrackItem t) {
  return t.genres.replaceAll('#', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _composerTextFromTrack(TrackItem t) => (t.composer ?? '').trim();

String _mimeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

String _mimeFromArtBytes(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/// After a failed save, reload from [diskPath] when the file was renamed on disk.
Future<void> recoverPlaybackAfterFailedTagWrite({
  required PlayerController player,
  required String originalPath,
  required String diskPath,
  required bool stoppedForEdit,
  required bool saveSucceeded,
  required Duration resumePos,
  required bool wasPlaying,
}) async {
  if (!stoppedForEdit || saveSucceeded) return;

  if (diskPath != originalPath) {
    try {
      final file = File(diskPath);
      if (await file.exists()) {
        await player.reloadCurrentSourceAfterTagWrite(
          resumePosition: resumePos,
          resumePlaying: wasPlaying,
        );
        return;
      }
    } catch (_) {}
    return;
  }

  await player.reloadCurrentSourceAfterTagWrite(
    resumePosition: resumePos,
    resumePlaying: wasPlaying,
  );
}

/// Shown when tag save / site-rename write fails — root overlay so it is visible
/// above the bottom sheet and matches success [ActionPillToast] behavior.
void _showTagEditFailureToast(String message) {
  var text = message.trim();
  if (text.isEmpty) return;
  const maxLen = 200;
  if (text.length > maxLen) {
    text = '${text.substring(0, maxLen - 1)}…';
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ActionPillToast.showUsingRootNavigator(
      text,
      icon: Icons.error_outline_rounded,
      uppercaseLabel: false,
      dwell: const Duration(milliseconds: 4200),
    );
  });
}

String _oneLineError(Object e) {
  var s = e.toString().trim();
  if (s.startsWith('Exception: ')) {
    s = s.substring('Exception: '.length).trim();
  }
  return s;
}

/// Opens the manual tag editor bottom sheet for [track].
Future<void> showManualTagEditor(BuildContext context, TrackItem track) {
  final path = track.filePath;
  if (path == null || path.isEmpty) {
    ActionPillToast.show(context, 'Need a local file', uppercaseLabel: true);
    return Future.value();
  }
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Editing tags is not supported on web.')),
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    showDragHandle: false,
    builder: (ctx) => EditTrackTagsSheet(track: track),
  );
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
  late final TextEditingController _composer;
  late final TextEditingController _fileName;

  AlbumArtEditKind _artEdit = AlbumArtEditKind.keep;
  Uint8List? _pickedCoverBytes;
  String _pickedCoverMime = 'image/jpeg';

  /// Small preview only (full cover is read on save / import, not held in memory).
  Uint8List? _embeddedArtBytes;
  bool _embeddedArtLoading = false;
  bool _diskHasEmbeddedArt = false;

  bool _saving = false;
  bool _siteRenameBusy = false;
  bool _coverImportBusy = false;

  late final String _initialTitle;
  late final String _initialArtist;
  late final String _initialAlbum;
  late final String _initialGenre;
  late final String _initialComposer;

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    _diskHasEmbeddedArt =
        t.albumArtBytes != null && t.albumArtBytes!.isNotEmpty;
    _embeddedArtLoading = t.filePath != null && t.filePath!.isNotEmpty;
    if (_embeddedArtLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadEmbeddedAlbumArtPreview());
      });
    }
    _initialTitle = t.title;
    _initialArtist = t.artist == 'Unknown artist' ? '' : t.artist;
    _initialAlbum = t.metaLine == 'mp3' ? '' : t.metaLine;
    _initialGenre = _genreTextFromTrack(t);
    _initialComposer = _composerTextFromTrack(t);
    _title = TextEditingController(text: _initialTitle);
    _artist = TextEditingController(text: _initialArtist);
    _album = TextEditingController(text: _initialAlbum);
    _genre = TextEditingController(text: _initialGenre);
    _composer = TextEditingController(text: _initialComposer);
    final fp = t.filePath ?? '';
    _fileName = TextEditingController(
      text: fp.isEmpty ? '' : p.basenameWithoutExtension(fp),
    );
    _title.addListener(_onTagFieldChanged);
    _artist.addListener(_onTagFieldChanged);
    _album.addListener(_onTagFieldChanged);
    _genre.addListener(_onTagFieldChanged);
    _composer.addListener(_onTagFieldChanged);
    _fileName.addListener(_onTagFieldChanged);
  }

  void _onTagFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEmbeddedAlbumArtPreview() async {
    final rawPath = widget.track.filePath?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      if (mounted) setState(() => _embeddedArtLoading = false);
      return;
    }

    final path = p.normalize(File(rawPath).absolute.path);
    try {
      var merged = widget.track;
      if (mounted) {
        final fromLibrary = PlayerController.of(context).trackForLibraryPath(path);
        final libArt = fromLibrary.albumArtBytes;
        if ((merged.albumArtBytes == null || merged.albumArtBytes!.isEmpty) &&
            libArt != null &&
            libArt.isNotEmpty) {
          merged = merged.withEmbeddedMetadata(
            albumArtBytes: libArt,
            replaceAlbumArtFromFile: true,
          );
        }
      }

      final thumb = await PickerAlbumArtLoader.thumbForTrack(merged);
      if (!mounted) return;
      setState(() {
        _embeddedArtBytes = thumb;
        _diskHasEmbeddedArt =
            _diskHasEmbeddedArt || (thumb != null && thumb.isNotEmpty);
        _embeddedArtLoading = false;
      });
    } catch (e, st) {
      debugPrint(
        'EditTrackTagsSheet: album art preview failed for $path: $e\n$st',
      );
      if (mounted) setState(() => _embeddedArtLoading = false);
    }
  }

  bool get _trackHasKnownEmbeddedArt {
    if (_artEdit == AlbumArtEditKind.remove) return false;
    if (_pickedCoverBytes != null && _pickedCoverBytes!.isNotEmpty) {
      return true;
    }
    if (_diskHasEmbeddedArt) return true;
    final preview = _embeddedArtBytes;
    return preview != null && preview.isNotEmpty;
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
    _composer.removeListener(_onTagFieldChanged);
    _fileName.removeListener(_onTagFieldChanged);
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _composer.dispose();
    _fileName.dispose();
    super.dispose();
  }

  Uint8List? get _effectivePreviewBytes {
    switch (_artEdit) {
      case AlbumArtEditKind.remove:
        return null;
      case AlbumArtEditKind.replace:
        return _pickedCoverBytes;
      case AlbumArtEditKind.keep:
        return _embeddedArtBytes ?? widget.track.albumArtBytes;
    }
  }

  Future<void> _applyEmbeddedCoverFromPath(String pickedPath) async {
    setState(() => _coverImportBusy = true);
    try {
      final normalized = p.normalize(File(pickedPath).absolute.path);
      final meta = await readAudioMetadata(
        TrackItem.fromFilePath(normalized),
      );
      if (!mounted) return;
      final art = meta.albumArtBytes;
      if (art == null || art.isEmpty) {
        ActionPillToast.show(
          context,
          'No embedded cover in that file',
          icon: Icons.image_not_supported_outlined,
          uppercaseLabel: false,
        );
        return;
      }
      setState(() {
        _artEdit = AlbumArtEditKind.replace;
        _pickedCoverBytes = art;
        _pickedCoverMime = _mimeFromArtBytes(art);
      });
      ActionPillToast.show(
        context,
        'Cover copied — tap Save to write',
        icon: Icons.check_rounded,
        uppercaseLabel: false,
      );
    } on FileSystemException catch (e) {
      if (!mounted) return;
      final msg = e.message.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty
                ? 'Could not read that file — $msg'
                : 'Could not read that file.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read cover — ${_oneLineError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _coverImportBusy = false);
    }
  }

  Future<void> _pickCoverFromLibrary() async {
    final picked = await showPickCoverFromLibrarySheet(
      context,
      excludePath: widget.track.filePath,
    );
    if (picked == null || !mounted) return;
    final path = picked.filePath?.trim();
    if (path == null || path.isEmpty) return;
    final cachedArt = picked.albumArtBytes;
    if (cachedArt != null && cachedArt.isNotEmpty) {
      setState(() {
        _artEdit = AlbumArtEditKind.replace;
        _pickedCoverBytes = cachedArt;
        _pickedCoverMime = _mimeFromArtBytes(cachedArt);
      });
      ActionPillToast.show(
        context,
        'Cover copied — tap Save to write',
        icon: Icons.check_rounded,
        uppercaseLabel: false,
      );
      return;
    }
    await _applyEmbeddedCoverFromPath(path);
  }

  /// Device file picker for audio (no album-art preview on Android).
  Future<void> _pickCoverFromAudioFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'flac',
        'ogg',
        'opus',
        'wav',
        'ape',
      ],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final pickedPath = result.files.single.path;
    if (pickedPath == null || pickedPath.trim().isEmpty) return;
    await _applyEmbeddedCoverFromPath(pickedPath);
  }

  Future<void> _pickCover() async {
    final r = await FilePicker.pickFiles(
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

  Future<ResolvedTagsForWrite> _resolveTagsForPath(String filePath) async {
    final snap = await readAudioMetadata(TrackItem.fromFilePath(filePath));
    final albumFromFile = snap.metaLine == 'mp3' ? '' : snap.metaLine;
    final artistFromFile =
        snap.artist == 'Unknown artist' ? '' : snap.artist.trim();
    return resolveTagsForWrite(
      filePath: filePath,
      editorTitle: _title.text,
      editorArtist: _artist.text,
      editorAlbum: _album.text,
      editorGenre: _genre.text,
      editorComposer: _composer.text,
      initialTitle: _initialTitle,
      initialArtist: _initialArtist,
      initialAlbum: _initialAlbum,
      initialGenre: _initialGenre,
      initialComposer: _initialComposer,
      embeddedTitle: snap.title,
      embeddedArtist: artistFromFile,
      embeddedAlbum: albumFromFile,
      embeddedGenre: _genreTextFromTrack(snap),
      embeddedComposer: _composerTextFromTrack(snap),
    );
  }

  Future<void> _previewSiteRename({required bool tagOnlyFlow}) async {
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
      final ctx = siteRenameContextFromTrack(snap);
      final suggestion = computeSiteRename(
        filePath: path,
        albumFromTags: _album.text.trim().isNotEmpty
            ? _album.text.trim()
            : ctx.album,
        artistFromTags: _artist.text.trim().isNotEmpty
            ? _artist.text.trim()
            : ctx.artist,
        titleFromTags: _title.text.trim().isNotEmpty
            ? _title.text.trim()
            : ctx.title,
        genreFromTags: _genre.text.trim().isNotEmpty
            ? _genre.text.trim()
            : ctx.genre,
        composerFromTags: _composer.text.trim().isNotEmpty
            ? _composer.text.trim()
            : ctx.composer,
        filenameBasenameOverride: _fileName.text.trim(),
      );
      if (!mounted) return;
      if (!suggestion.hasSuggestion) {
        ActionPillToast.showUsingRootNavigator(
          'No cleanup rule matched',
          icon: Icons.auto_fix_high_outlined,
          uppercaseLabel: true,
        );
        return;
      }
      if (suggestion.matchesCurrent(
        title: _title.text,
        artist: _artist.text,
        album: _album.text,
        genre: _genre.text,
        composer: _composer.text,
        checkFilename: !tagOnlyFlow,
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
          title: Text(
            tagOnlyFlow
                ? 'Auto edit tags (tag-only)'
                : 'Clean site-style filename',
          ),
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
                if (!tagOnlyFlow) ...[
                  Text('Filename', style: Theme.of(ctx).textTheme.labelSmall),
                  Text(
                    '${suggestion.originalBasenameWithoutExt}.mp3\n→ ${suggestion.newBasenameWithoutExt}.mp3',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
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
                if (tagOnlyFlow) ...[
                  const SizedBox(height: 8),
                  Text('Genre (tag)', style: Theme.of(ctx).textTheme.labelSmall),
                  Text(
                    suggestion.suggestedGenre,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Composer (tag)', style: Theme.of(ctx).textTheme.labelSmall),
                  Text(
                    suggestion.suggestedComposer,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ] else ...[
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
                if (tagOnlyFlow) {
                  Navigator.pop(ctx);
                  unawaited(_applySiteRename(suggestion, tagOnlyFlow: true));
                  return;
                }
                _title.text = suggestion.suggestedTitle;
                _artist.text = suggestion.suggestedArtist;
                _album.text = suggestion.suggestedAlbum;
                _genre.text = '';
                _composer.text = tagOnlyFlow
                    ? suggestion.suggestedComposer
                    : '';
                _fileName.text = suggestion.newBasenameWithoutExt;
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ActionPillToast.showUsingRootNavigator(
                    'Suggested tags and filename in editor — tap Save to write',
                    icon: Icons.edit_note_rounded,
                    uppercaseLabel: false,
                  );
                });
              },
              child: Text(tagOnlyFlow ? 'Apply tag edits' : 'Use in editor'),
            ),
            if (!tagOnlyFlow)
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_applySiteRename(suggestion, tagOnlyFlow: false));
                },
                child: const Text('Rename & save'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not analyze file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _siteRenameBusy = false);
    }
  }

  Future<void> _applySiteRename(
    SiteRenameSuggestion suggestion, {
    required bool tagOnlyFlow,
  }) async {
    final rawPath = widget.track.filePath;
    if (rawPath == null || rawPath.isEmpty) return;
    final path = p.normalize(File(rawPath).absolute.path);

    if (!await ensureCanWriteLibraryFiles(context)) {
      return;
    }
    if (!mounted) return;

    final player = PlayerController.of(context);

    setState(() => _saving = true);

    final wasPlaying = player.isPlaying;
    final resumePos = player.position;
    var stoppedForEdit = false;
    var saveSucceeded = false;
    var diskPath = path;

    try {
      var isCurrent = player.isCurrentTrackFilePath(path);
      if (isCurrent) {
        await player.stopForExternalFileEdit();
        stoppedForEdit = true;
      }

      var newPath = path;
      if (!tagOnlyFlow && suggestion.filenameChanged) {
        newPath = await renameMp3File(path, suggestion.newBasenameWithoutExt);
        player.registerLibraryPathRename(path, newPath);
      }
      diskPath = newPath;
      if (!isCurrent && newPath != path) {
        isCurrent = await player.shouldRewirePlaybackForRenamedFile(path, newPath);
        if (isCurrent && !stoppedForEdit) {
          await player.stopForExternalFileEdit();
          stoppedForEdit = true;
        }
      }

      final snapBeforeWrite = await readAudioMetadata(
        TrackItem.fromFilePath(newPath),
      );
      final albumBefore = snapBeforeWrite.metaLine == 'mp3'
          ? ''
          : snapBeforeWrite.metaLine;
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
        initialTitle: _initialTitle,
        initialArtist: _initialArtist,
        initialAlbum: _initialAlbum,
        initialGenre: _initialGenre,
        initialComposer: _initialComposer,
        embeddedTitle: snapBeforeWrite.title,
        embeddedArtist: artistBefore,
        embeddedAlbum: albumBefore,
        embeddedGenre: _genreTextFromTrack(snapBeforeWrite),
        embeddedComposer: _composerTextFromTrack(snapBeforeWrite),
        clearGenre: !tagOnlyFlow,
        clearComposer: !tagOnlyFlow,
      );
      await writeEmbeddedAudioTags(
        filePath: newPath,
        title: tags.title,
        album: tags.album,
        artist: tags.artist,
        genre: tags.genre,
        composer: tags.composer,
        artEdit: _artEdit,
        newCoverBytes: _pickedCoverBytes,
        newCoverMimeType: _pickedCoverMime,
      );

      final base = TrackItem.fromFilePath(newPath);
      final refreshed = await readAudioMetadata(base);
      if (!tagOnlyFlow && suggestion.filenameChanged) {
        await player.replaceTrackPath(
          path,
          refreshed,
          resumePosition: isCurrent ? resumePos : null,
          resumePlaying: isCurrent ? wasPlaying : null,
        );
        await SongMetadataCache.deletePaths([path]);
      } else {
        player.updateTrackByPath(
          path,
          refreshed,
          notify: CatalogNotifyMode.throttled,
          refreshNotificationArt: false,
        );
        if (isCurrent) {
          player.reloadCurrentSourceAfterTagWriteUnawaited(
            resumePosition: resumePos,
            resumePlaying: wasPlaying,
          );
        }
      }

      saveSucceeded = true;
      if (mounted) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ActionPillToast.showUsingRootNavigator(
            'File updated',
            uppercaseLabel: true,
          );
        });
      }
      unawaited(SongMetadataCache.saveTracks([refreshed]));
    } on StateError catch (e) {
      if (mounted) {
        final msg = e.toString();
        final alreadyExists = msg.toLowerCase().contains(
          'target already exists',
        );
        if (alreadyExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ActionPillToast.showUsingRootNavigator(
              renameTargetExistsUserMessage(e),
              icon: Icons.warning_amber_rounded,
              uppercaseLabel: false,
              dwell: const Duration(milliseconds: 4200),
            );
          });
        } else {
          final detail = e.message.trim();
          _showTagEditFailureToast(
            detail.isNotEmpty
                ? 'Could not update file — $detail'
                : 'Could not update file.',
          );
        }
      }
    } on UnsupportedError catch (e) {
      if (mounted) {
        final detail = (e.message ?? '').trim();
        _showTagEditFailureToast(
          detail.isNotEmpty
              ? 'This change is not supported — $detail'
              : 'This change is not supported for this file.',
        );
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        final os = e.message.trim();
        _showTagEditFailureToast(
          os.isNotEmpty
              ? 'Could not write the file — $os. On Android, enable All files access for this app if needed.'
              : 'Could not write the file — check permissions (All files access on Android).',
        );
      }
    } catch (e) {
      if (mounted) {
        _showTagEditFailureToast(
          'Could not update file — ${_oneLineError(e)}',
        );
      }
    } finally {
      await recoverPlaybackAfterFailedTagWrite(
        player: player,
        originalPath: path,
        diskPath: diskPath,
        stoppedForEdit: stoppedForEdit,
        saveSucceeded: saveSucceeded,
        resumePos: resumePos,
        wasPlaying: wasPlaying,
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final rawPath = widget.track.filePath;
    if (rawPath == null || rawPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no file path.')),
      );
      return;
    }
    final path = p.normalize(File(rawPath).absolute.path);

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing tags is not supported on web.')),
      );
      return;
    }

    final player = PlayerController.of(context);

    if (!await ensureCanWriteLibraryFiles(context)) {
      return;
    }

    setState(() => _saving = true);
    final wasPlaying = player.isPlaying;
    final resumePos = player.position;
    var stoppedForEdit = false;
    var saveSucceeded = false;
    var diskPath = path;

    try {
      var isCurrent = player.isCurrentTrackFilePath(path);
      if (isCurrent) {
        await player.stopForExternalFileEdit();
        stoppedForEdit = true;
      }

      final desiredBasename = sanitizeRenameBasename(_fileName.text);
      var targetPath = path;
      final currentBasename = p.basenameWithoutExtension(path);
      if (desiredBasename != currentBasename) {
        targetPath = await renameMp3File(path, desiredBasename);
        player.registerLibraryPathRename(path, targetPath);
      }
      diskPath = targetPath;
      if (!isCurrent && targetPath != path) {
        isCurrent = await player.shouldRewirePlaybackForRenamedFile(path, targetPath);
        if (isCurrent && !stoppedForEdit) {
          await player.stopForExternalFileEdit();
          stoppedForEdit = true;
        }
      }
      final tags = await _resolveTagsForPath(targetPath);
      await writeEmbeddedAudioTags(
        filePath: targetPath,
        title: tags.title,
        artist: tags.artist,
        album: tags.album,
        genre: tags.genre,
        composer: tags.composer,
        artEdit: _artEdit,
        newCoverBytes: _pickedCoverBytes,
        newCoverMimeType: _pickedCoverMime,
      );
      final refreshed = await readAudioMetadata(
        TrackItem.fromFilePath(targetPath),
      );
      if (targetPath != path) {
        await player.replaceTrackPath(
          path,
          refreshed,
          resumePosition: isCurrent ? resumePos : null,
          resumePlaying: isCurrent ? wasPlaying : null,
        );
        await SongMetadataCache.deletePaths([path]);
      } else {
        player.updateTrackByPath(
          path,
          refreshed,
          notify: CatalogNotifyMode.throttled,
          refreshNotificationArt: false,
        );
        if (isCurrent) {
          player.reloadCurrentSourceAfterTagWriteUnawaited(
            resumePosition: resumePos,
            resumePlaying: wasPlaying,
          );
        }
      }
      saveSucceeded = true;
      if (mounted) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ActionPillToast.showUsingRootNavigator(
            'Tags saved',
            uppercaseLabel: true,
          );
        });
      }
      unawaited(SongMetadataCache.saveTracks([refreshed]));
    } on UnsupportedError catch (e) {
      if (mounted) {
        final detail = (e.message ?? '').trim();
        _showTagEditFailureToast(
          detail.isNotEmpty
              ? 'Tags could not be saved — $detail'
              : 'Tags could not be saved — this format or change is not supported.',
        );
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        final os = e.message.trim();
        _showTagEditFailureToast(
          os.isNotEmpty
              ? 'Could not write the file — $os. On Android, enable All files access for this app if needed.'
              : 'Could not write the file — check permissions (All files access on Android).',
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        final msg = e.toString();
        final alreadyExists = msg.toLowerCase().contains(
          'target already exists',
        );
        if (alreadyExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ActionPillToast.showUsingRootNavigator(
              renameTargetExistsUserMessage(e),
              icon: Icons.warning_amber_rounded,
              uppercaseLabel: false,
              dwell: const Duration(milliseconds: 4200),
            );
          });
        } else {
          final detail = e.message.trim();
          _showTagEditFailureToast(
            detail.isNotEmpty
                ? 'Could not save tags — $detail'
                : 'Could not save tags.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showTagEditFailureToast(
          'Could not save tags — ${_oneLineError(e)}',
        );
      }
    } finally {
      await recoverPlaybackAfterFailedTagWrite(
        player: player,
        originalPath: path,
        diskPath: diskPath,
        stoppedForEdit: stoppedForEdit,
        saveSucceeded: saveSucceeded,
        resumePos: resumePos,
        wasPlaying: wasPlaying,
      );
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
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Changes are written into the MP3 file.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >= 480;
                  final coverPanel = _buildCoverArtPanel(context, theme);
                  final formPanel = _buildTagFormPanel(context, theme);
                  if (sideBySide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 272,
                          child: coverPanel,
                        ),
                        const SizedBox(width: 20),
                        Expanded(child: formPanel),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      coverPanel,
                      const SizedBox(height: 16),
                      formPanel,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverArtPanel(BuildContext context, ThemeData theme) {
    const previewSize = 120.0;
    final busy = _saving || _coverImportBusy;

    Widget coverButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      Widget? iconWidget,
    }) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: iconWidget ?? Icon(icon, size: 20),
          label: Text(label),
        ),
      );
    }

    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: previewSize,
        height: previewSize,
        child: _embeddedArtLoading && _artEdit == AlbumArtEditKind.keep
            ? ColoredBox(
                color: context.controlAccent.withValues(alpha: 0.12),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.controlAccent,
                    ),
                  ),
                ),
              )
            : _effectivePreviewBytes != null
            ? Image.memory(
                _effectivePreviewBytes!,
                width: previewSize,
                height: previewSize,
                fit: BoxFit.cover,
              )
            : ColoredBox(
                color: context.controlAccent.withValues(alpha: 0.12),
                child: Icon(
                  Icons.album_outlined,
                  size: 48,
                  color: context.palette.textSecondary.withValues(alpha: 0.6),
                ),
              ),
      ),
    );

    const optionGap = SizedBox(height: 8);
    final optionButtons = <Widget>[
      coverButton(
        icon: Icons.image_outlined,
        label: 'Cover image',
        onPressed: busy ? null : _pickCover,
      ),
      coverButton(
        icon: Icons.library_music_outlined,
        label: 'From library',
        onPressed: busy ? null : _pickCoverFromLibrary,
        iconWidget: _coverImportBusy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.controlAccent,
                ),
              )
            : const Icon(Icons.library_music_outlined, size: 20),
      ),
      coverButton(
        icon: Icons.audio_file_outlined,
        label: 'Audio file',
        onPressed: busy ? null : _pickCoverFromAudioFile,
      ),
      if (_trackHasKnownEmbeddedArt)
        coverButton(
          icon: Icons.hide_image_outlined,
          label: 'Remove art',
          onPressed: busy ? null : _clearCover,
        ),
      if (_artEdit != AlbumArtEditKind.keep)
        coverButton(
          icon: Icons.undo_rounded,
          label: 'Reset cover',
          onPressed: busy ? null : _resetCoverEdit,
        ),
    ];

    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < optionButtons.length; i++) ...[
          if (i > 0) optionGap,
          optionButtons[i],
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(width: 12),
        Expanded(child: options),
      ],
    );
  }

  Widget _buildTagFormPanel(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Auto edit tags (tag-only)',
              visualDensity: VisualDensity.compact,
              onPressed: (_saving || _siteRenameBusy)
                  ? null
                  : () => _previewSiteRename(tagOnlyFlow: true),
              icon: _siteRenameBusy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.controlAccent,
                      ),
                    )
                  : Icon(
                      Icons.auto_fix_high_outlined,
                      size: 24,
                      color: context.controlAccent,
                    ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                onPressed: (_saving || _siteRenameBusy)
                    ? null
                    : () => _previewSiteRename(tagOnlyFlow: false),
                child: const Text('Clean site-style name'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _fileName,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: 'File name',
            helperText: 'Saved as .mp3',
            border: const OutlineInputBorder(),
            suffixIcon: _clearFieldSuffix(_fileName),
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
        const SizedBox(height: 12),
        TextField(
          controller: _composer,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: 'Composer',
            border: const OutlineInputBorder(),
            suffixIcon: _clearFieldSuffix(_composer),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 24),
        Builder(
          builder: (context) {
            final outlineStyle = OutlinedButton.styleFrom(
              foregroundColor: context.palette.textPrimary,
              side: BorderSide(
                color: context.palette.textMuted.withValues(alpha: 0.45),
              ),
            );
            return Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: outlineStyle,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: outlineStyle,
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.controlAccent,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
