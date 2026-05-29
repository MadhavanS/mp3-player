import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/track_grouping.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_list_album_art.dart';

class ContextTracksScreen extends StatelessWidget {
  const ContextTracksScreen({
    super.key,
    required this.groupKind,
    required this.groupValue,
    required this.tracks,
    this.initialArtistNames = const <String>[],
  });

  final TrackGroupKind groupKind;
  final String groupValue;
  final List<TrackItem> tracks;
  final List<String> initialArtistNames;

  @override
  Widget build(BuildContext context) {
    return _ContextTracksView(
      groupKind: groupKind,
      groupValue: groupValue,
      initialTracks: tracks,
      initialArtistNames: initialArtistNames,
    );
  }
}

class _ContextTracksView extends StatefulWidget {
  const _ContextTracksView({
    required this.groupKind,
    required this.groupValue,
    required this.initialTracks,
    required this.initialArtistNames,
  });

  final TrackGroupKind groupKind;
  final String groupValue;
  final List<TrackItem> initialTracks;
  final List<String> initialArtistNames;

  @override
  State<_ContextTracksView> createState() => _ContextTracksViewState();
}

class _ContextTracksViewState extends State<_ContextTracksView> {
  late final List<TrackItem> _allTracks = List<TrackItem>.from(widget.initialTracks);
  late Set<String> _activeArtistNames = widget.initialArtistNames
      .map(normalizeTrackGroupValue)
      .where((v) => v.isNotEmpty)
      .toSet();
  final Set<String> _removedTrackIds = <String>{};

  String _trackStableId(TrackItem t) =>
      (t.filePath?.trim().isNotEmpty ?? false) ? t.filePath!.trim() : '${t.title}|${t.artist}';

  List<TrackItem> _visibleTracks() {
    Iterable<TrackItem> filtered = _allTracks;
    if (widget.groupKind == TrackGroupKind.artist && _activeArtistNames.isNotEmpty) {
      filtered = filtered.where((track) {
        final tokens = splitArtistNames(track.artist)
            .map(normalizeTrackGroupValue)
            .where((v) => v.isNotEmpty);
        for (final t in tokens) {
          if (_activeArtistNames.contains(t)) return true;
        }
        return false;
      });
    }
    return filtered
        .where((t) => !_removedTrackIds.contains(_trackStableId(t)))
        .toList(growable: false);
  }

  void _closeOverlay(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _playList({
    required BuildContext context,
    required int startIndex,
    bool shuffle = false,
  }) async {
    final nowTracks = _visibleTracks();
    if (nowTracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= nowTracks.length) return;

    final player = PlayerController.of(context);
    // Close immediately so Songs + mini player are visible while playback starts.
    _closeOverlay(context);

    try {
      await player.setPlaylistAndPlay(
        nowTracks,
        startIndex: startIndex,
        playbackOriginTab: LibraryTabId.songs,
        keepShuffleMode: false,
        enableShuffle: shuffle,
      );
    } catch (e, st) {
      debugPrint('ContextTracksScreen._playList: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);
    final title = '${groupLabel(widget.groupKind)} Tracks';
    final subtitle = widget.groupValue.trim().isEmpty
        ? 'Unknown'
        : widget.groupValue.trim();
    const leadingSize = 34.0;
    const dividerIndent = 12.0 + leadingSize + 10.0;
    final nowTracks = _visibleTracks();
    final isArtistMode = widget.groupKind == TrackGroupKind.artist;

    return Material(
      color: pal.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: pal.textMuted.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: pal.onScaffold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (!isArtistMode)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: pal.textSecondary,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final artist in widget.initialArtistNames)
                                Text(
                                  artist,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: pal.textSecondary,
                                    decoration: _activeArtistNames.contains(
                                          normalizeTrackGroupValue(artist),
                                        )
                                        ? TextDecoration.none
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => _closeOverlay(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: pal.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isArtistMode && widget.initialArtistNames.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
                  children: [
                    for (final artist in widget.initialArtistNames)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(artist),
                          selected: _activeArtistNames.contains(normalizeTrackGroupValue(artist)),
                          onSelected: (_activeArtistNames.length <= 1 &&
                                  _activeArtistNames.contains(
                                    normalizeTrackGroupValue(artist),
                                  ))
                              ? null
                              : (enabled) {
                            final key = normalizeTrackGroupValue(artist);
                            setState(() {
                              if (enabled) {
                                _activeArtistNames.add(key);
                              } else {
                                _activeArtistNames.remove(key);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: nowTracks.isEmpty
                          ? null
                          : () => _playList(context: context, startIndex: 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play all'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: nowTracks.isEmpty
                          ? null
                          : () => _playList(
                                context: context,
                                startIndex: 0,
                                shuffle: true,
                              ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle play'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: nowTracks.isEmpty
                  ? Center(
              child: Text(
                'No tracks found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.textSecondary,
                ),
              ),
            )
                  : ListView.builder(
                      itemCount: nowTracks.length,
                      itemBuilder: (context, index) {
                        final t = nowTracks[index];
                        final row = Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                _playList(context: context, startIndex: index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: leadingSize,
                                    height: leadingSize,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: pal.onScaffold.withValues(
                                          alpha: 0.08,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                color: pal.onScaffold,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TrackListAlbumArt(track: t),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                color: pal.onScaffold,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          t.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: pal.textSecondary
                                                    .withValues(alpha: 0.95),
                                                fontSize: 13,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove from this list',
                                    icon: Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: pal.textSecondary,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _removedTrackIds.add(_trackStableId(t));
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            row,
                            Divider(
                              height: 1,
                              color: pal.onScaffold.withValues(alpha: 0.08),
                              indent: dividerIndent,
                            ),
                          ],
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
