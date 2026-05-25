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

class _PickerLibraryEntry {
  const _PickerLibraryEntry({
    required this.track,
    required this.searchHay,
  });

  final TrackItem track;
  final String searchHay;
}

class _PickCoverFromLibrarySheet extends StatefulWidget {
  const _PickCoverFromLibrarySheet({this.excludePath});

  final String? excludePath;

  @override
  State<_PickCoverFromLibrarySheet> createState() =>
      _PickCoverFromLibrarySheetState();
}

class _PickCoverFromLibrarySheetState extends State<_PickCoverFromLibrarySheet> {
  static const int _preloadThumbCount = 18;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 220);

  final _search = TextEditingController();
  Timer? _searchDebounceTimer;

  List<_PickerLibraryEntry> _entries = const [];
  bool _snapshotCaptured = false;
  PlayerController? _player;

  List<TrackItem>? _filteredCache;
  String? _filteredCacheKey;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshotCaptured) return;
    _snapshotCaptured = true;
    _player = PlayerController.of(context);
    final excludeKey = widget.excludePath == null
        ? ''
        : canonicalMusicLibraryPathKey(widget.excludePath!);
    _entries = _player!.metadataLibrary
        .map((t) {
          final path = t.filePath?.trim();
          final track = path == null || path.isEmpty
              ? t
              : _player!.trackForLibraryPath(path);
          if (excludeKey.isNotEmpty) {
            final key = canonicalMusicLibraryPathKey(path ?? '');
            if (key == excludeKey) return null;
          }
          if (path == null || path.isEmpty) return null;
          return _PickerLibraryEntry(
            track: track,
            searchHay:
                '${track.title} ${track.artist} ${track.metaLine} ${track.genres}'
                    .toLowerCase(),
          );
        })
        .whereType<_PickerLibraryEntry>()
        .toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleSearchRebuild(immediate: true);
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearchRebuild({bool immediate = false}) {
    _searchDebounceTimer?.cancel();
    if (immediate) {
      _rebuildFilteredList();
      return;
    }
    _searchDebounceTimer = Timer(_searchDebounceDelay, () {
      if (!mounted) return;
      _rebuildFilteredList();
    });
  }

  void _rebuildFilteredList() {
    final player = _player;
    setState(() {
      _filteredCache = null;
      _filteredCacheKey = null;
    });
    final tracks = _filteredTracks();
    if (player != null && tracks.isNotEmpty) {
      PickerAlbumArtLoader.preloadTracks(
        tracks.take(_preloadThumbCount),
        player: player,
      );
    }
  }

  List<TrackItem> _filteredTracks() {
    final q = _search.text.trim().toLowerCase();
    if (_filteredCache != null && _filteredCacheKey == q) {
      return _filteredCache!;
    }

    Iterable<_PickerLibraryEntry> source = _entries;
    if (q.isNotEmpty) {
      source = source.where((e) => e.searchHay.contains(q));
    }

    final tracks = source.map((e) => e.track).toList(growable: false);
    if (q.isEmpty) {
      tracks.sort((a, b) {
        final aHas = a.albumArtBytes != null && a.albumArtBytes!.isNotEmpty;
        final bHas = b.albumArtBytes != null && b.albumArtBytes!.isNotEmpty;
        if (aHas != bHas) return aHas ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    } else {
      tracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }

    _filteredCache = tracks;
    _filteredCacheKey = q;
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final tracks = _filteredTracks();
    final player = _player;
    final hasSearchText = _search.text.trim().isNotEmpty;

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
                'Covers load from cache first, then from each file one at a time. '
                'Scroll to load more rows.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: PickerAlbumArtLoader.queueDepth,
              builder: (context, depth, _) {
                if (depth <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.controlAccent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              depth == 1
                                  ? 'Loading album art…'
                                  : 'Loading album art… ($depth files queued)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.palette.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: context.palette.textMuted.withValues(
                          alpha: 0.2,
                        ),
                        color: context.controlAccent.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                );
              },
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
                  suffixIcon: hasSearchText
                      ? IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _search.clear();
                            _scheduleSearchRebuild(immediate: true);
                          },
                          icon: const Icon(Icons.clear_rounded),
                        )
                      : null,
                ),
                onChanged: (_) => _scheduleSearchRebuild(),
              ),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _entries.isEmpty
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      cacheExtent: 280,
                      itemCount: tracks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return RepaintBoundary(
                          child: _CoverPickerRow(
                            track: track,
                            player: player,
                          ),
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
    required this.player,
  });

  final TrackItem track;
  final PlayerController? player;

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
              _CoverPickerThumb(
                track: track,
                player: player,
              ),
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

enum _ThumbDisplay { placeholder, loading, art, noArt }

class _CoverPickerThumb extends StatefulWidget {
  const _CoverPickerThumb({
    required this.track,
    required this.player,
  });

  final TrackItem track;
  final PlayerController? player;

  @override
  State<_CoverPickerThumb> createState() => _CoverPickerThumbState();
}

class _CoverPickerThumbState extends State<_CoverPickerThumb> {
  static const double _size = 56;

  Uint8List? _thumb;
  _ThumbDisplay _display = _ThumbDisplay.placeholder;
  bool _loadStarted = false;

  @override
  void didUpdateWidget(covariant _CoverPickerThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.filePath != oldWidget.track.filePath) {
      _resetForTrack();
      _maybeStartLoad();
    }
  }

  @override
  void initState() {
    super.initState();
    _applySyncArtIfAny();
    _maybeStartLoad();
  }

  void _resetForTrack() {
    _thumb = null;
    _loadStarted = false;
    _display = _ThumbDisplay.placeholder;
    _applySyncArtIfAny();
  }

  void _applySyncArtIfAny() {
    final player = widget.player;
    if (player == null) return;
    final sync = PickerAlbumArtLoader.resolveSync(widget.track, player);
    if (sync != null && sync.isNotEmpty) {
      _thumb = sync;
      _display = _ThumbDisplay.art;
    }
  }

  void _maybeStartLoad() {
    if (_loadStarted || _display == _ThumbDisplay.art) return;
    _loadStarted = true;
    if (_display == _ThumbDisplay.placeholder) {
      setState(() => _display = _ThumbDisplay.loading);
    }
    unawaited(_loadThumb());
  }

  Future<void> _loadThumb() async {
    final thumb = await PickerAlbumArtLoader.thumbForTrack(
      widget.track,
      highPriority: true,
    );
    if (!mounted) return;
    setState(() {
      _thumb = thumb;
      _display = thumb != null && thumb.isNotEmpty
          ? _ThumbDisplay.art
          : _ThumbDisplay.noArt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.track.artColors;
    Widget child;
    if (_display == _ThumbDisplay.art &&
        _thumb != null &&
        _thumb!.isNotEmpty) {
      child = Image.memory(
        _thumb!,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    } else if (_display == _ThumbDisplay.loading) {
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
    } else if (_display == _ThumbDisplay.noArt) {
      child = ColoredBox(
        color: colors.first.withValues(alpha: 0.2),
        child: Icon(
          Icons.album_outlined,
          size: 26,
          color: context.palette.textSecondary.withValues(alpha: 0.55),
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          key: ValueKey<String>('$_display-${_thumb?.length ?? 0}'),
          width: _size,
          height: _size,
          child: child,
        ),
      ),
    );
  }
}
