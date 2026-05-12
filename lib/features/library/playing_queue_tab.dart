import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../player/track_overflow_actions.dart';

String _formatQueueDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Library tab: live queue in playback order, card rows, handle-driven reorder.
class PlayingQueueTab extends StatelessWidget {
  const PlayingQueueTab({
    super.key,
    required this.theme,
    required this.pal,
    required this.player,
    required this.searchQuery,
    required this.scrollController,
    required this.scrollAnchorKey,
    required this.onOverflow,
    required this.onReorder,
  });

  final ThemeData theme;
  final AppPalette pal;
  final PlayerController player;
  final String searchQuery;

  final ScrollController scrollController;
  final GlobalKey scrollAnchorKey;

  final void Function(int playlistIndex, TrackOverflowAction action) onOverflow;

  final void Function(int oldOrderIndex, int newOrderIndex) onReorder;

  /// Used by [LibraryScreenState] when scrolling to the current row under search.
  static bool matchesSearchFilter(TrackItem t, String q) {
    if (q.isEmpty) return true;
    final s = q.toLowerCase();
    return t.title.toLowerCase().contains(s) ||
        t.artist.toLowerCase().contains(s);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final playlist = player.playlist;
        if (playlist.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 54,
                    color: pal.onScaffold.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Nothing in the queue',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: pal.onScaffold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start playback from Songs or another tab to build a queue.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final order = player.playbackOrderIndices;
        final rows = <({int orderPos, int plIndex, TrackItem track})>[];
        for (var i = 0; i < order.length; i++) {
          final pl = order[i];
          if (pl < 0 || pl >= playlist.length) continue;
          final t = playlist[pl];
          if (!matchesSearchFilter(t, searchQuery)) continue;
          rows.add((orderPos: i, plIndex: pl, track: t));
        }

        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'No queue items match your search.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ),
          );
        }

        final allowReorder =
            player.canReorderPlaybackQueue && searchQuery.isEmpty;

        return CustomScrollView(
          controller: scrollController,
          slivers: [
            if (allowReorder)
              SliverReorderableList(
                itemCount: rows.length,
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < newIndex) newIndex -= 1;
                  if (oldIndex == newIndex) return;
                  final oldRow = rows[oldIndex];
                  final newRow = rows[newIndex];
                  onReorder(oldRow.orderPos, newRow.orderPos);
                },
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final durationLabel = r.plIndex == player.currentIndex
                      ? (player.duration != null
                            ? _formatQueueDuration(player.duration!)
                            : null)
                      : null;
                  return _QueueListRow(
                    key: ValueKey(
                      'pq_${r.plIndex}_${r.orderPos}_${r.track.filePath ?? r.track.title}',
                    ),
                    displayIndex: index + 1,
                    track: r.track,
                    playlistIndex: r.plIndex,
                    isCurrent: r.plIndex == player.currentIndex,
                    scrollAnchorKey: r.plIndex == player.currentIndex
                        ? scrollAnchorKey
                        : null,
                    durationLabel: durationLabel,
                    theme: theme,
                    pal: pal,
                    reorderHandleIndex: index,
                    onOverflow: (a) => onOverflow(r.plIndex, a),
                  );
                },
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final r = rows[index];
                  final durationLabel = r.plIndex == player.currentIndex
                      ? (player.duration != null
                            ? _formatQueueDuration(player.duration!)
                            : null)
                      : null;
                  return _QueueListRow(
                    key: ValueKey(
                      'pq_${r.plIndex}_${r.orderPos}_${r.track.filePath ?? r.track.title}',
                    ),
                    displayIndex: index + 1,
                    track: r.track,
                    playlistIndex: r.plIndex,
                    isCurrent: r.plIndex == player.currentIndex,
                    scrollAnchorKey: r.plIndex == player.currentIndex
                        ? scrollAnchorKey
                        : null,
                    durationLabel: durationLabel,
                    theme: theme,
                    pal: pal,
                    reorderHandleIndex: null,
                    onOverflow: (a) => onOverflow(r.plIndex, a),
                  );
                }, childCount: rows.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}

class _QueueListRow extends StatelessWidget {
  const _QueueListRow({
    super.key,
    required this.displayIndex,
    required this.track,
    required this.playlistIndex,
    required this.isCurrent,
    required this.scrollAnchorKey,
    required this.durationLabel,
    required this.theme,
    required this.pal,
    required this.reorderHandleIndex,
    required this.onOverflow,
  });

  final int displayIndex;
  final TrackItem track;
  final int playlistIndex;
  final bool isCurrent;
  final GlobalKey? scrollAnchorKey;
  final String? durationLabel;
  final ThemeData theme;
  final AppPalette pal;

  /// When non-null, shows a drag handle wired to [SliverReorderableList].
  final int? reorderHandleIndex;
  final void Function(TrackOverflowAction action) onOverflow;

  @override
  Widget build(BuildContext context) {
    final accent = context.controlAccent;
    final artistLine = durationLabel != null && durationLabel!.isNotEmpty
        ? '${track.artist} • $durationLabel'
        : track.artist;

    const leadingSize = 36.0;
    const dividerIndent = 12.0 + leadingSize + 10.0;

    final handle = reorderHandleIndex != null
        ? ReorderableDragStartListener(
            index: reorderHandleIndex!,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                Icons.drag_handle_rounded,
                color: pal.onScaffold.withValues(alpha: 0.45),
                size: 22,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Icons.drag_handle_rounded,
              color: pal.onScaffold.withValues(alpha: 0.16),
              size: 22,
            ),
          );

    final textColumn = isCurrent
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.genres.isEmpty
                    ? track.metaLine
                    : '${track.metaLine} · ${track.genres}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: pal.textMuted.withValues(alpha: 0.9),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 22, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pal.onScaffold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary.withValues(alpha: 0.95),
                  fontSize: 13,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.onScaffold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary.withValues(alpha: 0.95),
                  fontSize: 13,
                ),
              ),
            ],
          );

    final row = Material(
      key: scrollAnchorKey,
      color: isCurrent
          ? pal.onScaffold.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(PlayerController.of(context).jumpToIndex(playlistIndex));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: leadingSize,
                height: leadingSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? accent.withValues(alpha: 0.2)
                        : pal.onScaffold.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$displayIndex',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: pal.onScaffold,
                        fontWeight: FontWeight.w800,
                        fontSize: isCurrent ? 14 : 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: textColumn),
              TrackOverflowMenuWithFavourite(
                pal: pal,
                track: track,
                overflowIcon: Icons.more_vert_rounded,
                onSelected: onOverflow,
              ),
              handle,
            ],
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Divider(height: 1, color: pal.dividerOnHero, indent: dividerIndent),
      ],
    );
  }
}
