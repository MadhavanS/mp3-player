import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/music_library_path_key.dart';
import '../../services/picker_album_art_loader.dart';
import '../../theme/app_theme.dart';

/// Picks a library song to copy embedded cover art from (shows album art like the main library).
Future<TrackItem?> showPickCoverFromLibrarySheet(
  BuildContext context, {
  String? excludePath,
}) {
  return showModalBottomSheet<TrackItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _PickCoverFromLibrarySheet(excludePath: excludePath),
  );
}

class _PickCoverFromLibrarySheet extends StatefulWidget {
  const _PickCoverFromLibrarySheet({this.excludePath});

  final String? excludePath;

  @override
  State<_PickCoverFromLibrarySheet> createState() =>
      _PickCoverFromLibrarySheetState();
}

class _PickCoverFromLibrarySheetState extends State<_PickCoverFromLibrarySheet> {
  static const double _rowStride = 72;

  final _search = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';

  /// Frozen at open — avoids rebuilding the whole list on every catalog art update.
  List<TrackItem> _librarySnapshot = const [];
  bool _snapshotCaptured = false;

  int _visibleFirst = 0;
  int _visibleLast = 12;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshotCaptured) return;
    _snapshotCaptured = true;
    final player = PlayerController.of(context);
    _librarySnapshot = player.metadataLibrary
        .map((t) {
          final path = t.filePath?.trim();
          if (path == null || path.isEmpty) return t;
          return player.trackForLibraryPath(path);
        })
        .toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final rows = _candidates();
    if (rows.isEmpty) return;
    final pos = _scrollController.position;
    final first = (pos.pixels / _rowStride).floor().clamp(0, rows.length - 1);
    final last = ((pos.pixels + pos.viewportDimension) / _rowStride)
        .ceil()
        .clamp(0, rows.length - 1);
    final paddedFirst = (first - 2).clamp(0, rows.length - 1);
    final paddedLast = (last + 2).clamp(0, rows.length - 1);
    if (paddedFirst == _visibleFirst && paddedLast == _visibleLast) return;
    setState(() {
      _visibleFirst = paddedFirst;
      _visibleLast = paddedLast;
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  List<TrackItem> _candidates() {
    final excludeKey = widget.excludePath == null
        ? ''
        : canonicalMusicLibraryPathKey(widget.excludePath!);
    final q = _query.trim().toLowerCase();

    bool matches(TrackItem t) {
      if (q.isEmpty) return true;
      final hay =
          '${t.title} ${t.artist} ${t.metaLine} ${t.genres}'.toLowerCase();
      return hay.contains(q);
    }

    final tracks = _librarySnapshot
        .where((t) {
          final path = t.filePath?.trim();
          if (path == null || path.isEmpty) return false;
          if (excludeKey.isNotEmpty &&
              canonicalMusicLibraryPathKey(path) == excludeKey) {
            return false;
          }
          return matches(t);
        })
        .toList(growable: false);

    tracks.sort((a, b) {
      final aHas = a.albumArtBytes != null && a.albumArtBytes!.isNotEmpty;
      final bHas = b.albumArtBytes != null && b.albumArtBytes!.isNotEmpty;
      if (aHas != bHas) return aHas ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final tracks = _candidates();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Copy cover from library',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                'Tap a song to copy its cover. Thumbnails load one at a time while you scroll.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search songs',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _librarySnapshot.isEmpty
                              ? 'Your library is empty. Scan music folders first, or use Audio file below.'
                              : 'No songs match your search.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: tracks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final loadThumb = index >= _visibleFirst &&
                            index <= _visibleLast;
                        return _CoverPickerRow(
                          track: track,
                          loadThumb: loadThumb,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPickerRow extends StatelessWidget {
  const _CoverPickerRow({
    required this.track,
    required this.loadThumb,
  });

  final TrackItem track;
  final bool loadThumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pop(track),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _CoverPickerThumb(track: track, loadThumb: loadThumb),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.metaLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPickerThumb extends StatefulWidget {
  const _CoverPickerThumb({required this.track, required this.loadThumb});

  final TrackItem track;
  final bool loadThumb;

  @override
  State<_CoverPickerThumb> createState() => _CoverPickerThumbState();
}

class _CoverPickerThumbState extends State<_CoverPickerThumb> {
  static const double _size = 56;
  Uint8List? _thumb;
  bool _loading = false;
  bool _started = false;

  @override
  void didUpdateWidget(covariant _CoverPickerThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadThumb && !oldWidget.loadThumb) {
      _maybeStartLoad();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadThumb) {
      _maybeStartLoad();
    }
  }

  void _maybeStartLoad() {
    if (_started || _loading) return;
    _started = true;
    unawaited(_loadThumb());
  }

  Future<void> _loadThumb() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final thumb = await PickerAlbumArtLoader.thumbForTrack(widget.track);
    if (!mounted) return;
    setState(() {
      _thumb = thumb;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.track.artColors;
    Widget child;
    if (_thumb != null && _thumb!.isNotEmpty) {
      child = Image.memory(
        _thumb!,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    } else if (_loading) {
      child = ColoredBox(
        color: colors.first.withValues(alpha: 0.25),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.controlAccent,
            ),
          ),
        ),
      );
    } else {
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: _size, height: _size, child: child),
    );
  }
}
