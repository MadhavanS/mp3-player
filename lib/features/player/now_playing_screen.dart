import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';
import 'edit_track_tags_sheet.dart';
import 'track_overflow_actions.dart';

String _formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key, required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double? _dragPositionFraction;
  double _pullDismissPx = 0;
  bool _collapseRequested = false;

  void _safeCollapse() {
    if (_collapseRequested || !mounted) return;
    _collapseRequested = true;
    widget.onCollapse();
  }

  void _resetPullDismiss() => _pullDismissPx = 0;

  void _onPullDownUpdate(double deltaDown) {
    if (deltaDown <= 0) return;
    _pullDismissPx += deltaDown;
    if (_pullDismissPx >= 56) {
      _resetPullDismiss();
      _safeCollapse();
    }
  }

  bool _onScrollOverscroll(ScrollNotification n) {
    if (_collapseRequested) return false;
    if (n is! OverscrollNotification || n.metrics.axis != Axis.vertical) {
      return false;
    }
    if (n.metrics.extentBefore > 0) {
      return false;
    }
    final o = n.overscroll;
    if (o.abs() < 40) {
      return false;
    }
    _safeCollapse();
    return true;
  }

  /// Pull down at scroll top (before/without overscroll) to dismiss—handles platforms
  /// where [OverscrollNotification] is sparse or missing.
  bool _onScrollPullAtTop(ScrollNotification n) {
    if (_collapseRequested || n is! ScrollUpdateNotification) {
      return false;
    }
    final m = n.metrics;
    if (m.axis != Axis.vertical || m.extentBefore > 0) {
      return false;
    }
    final delta = n.scrollDelta;
    if (delta == null) {
      return false;
    }
    if (m.pixels <= 0 && delta < 0) {
      _onPullDownUpdate(-delta);
      return false;
    }
    if (delta > 0 && m.pixels <= 0) {
      _resetPullDismiss();
    }
    return false;
  }

  bool _onScrollForDismiss(ScrollNotification n) {
    if (_onScrollOverscroll(n)) return true;
    _onScrollPullAtTop(n);
    return false;
  }

  void _openTagEditor(PlayerController player) {
    final t = player.currentTrack;
    if (t == null || t.filePath == null || t.filePath!.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      showDragHandle: false,
      builder: (ctx) => EditTrackTagsSheet(track: t),
    );
  }

  Widget _footerTrackTools(
    AppPalette pal,
    PlayerController player,
  ) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final cur = player.currentTrack;
        if (cur == null) return const SizedBox.shrink();

        final canEdit =
            cur.filePath != null && cur.filePath!.isNotEmpty;

        return Material(
          color: pal.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, thickness: 1, color: pal.dividerOnHero),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Edit tags & cover',
                        iconSize: 28,
                        icon: Icon(
                          Icons.edit_note_rounded,
                          color: canEdit
                              ? pal.primary
                              : pal.textSecondary.withValues(alpha: 0.45),
                        ),
                        onPressed:
                            canEdit ? () => _openTagEditor(player) : null,
                      ),
                      const SizedBox(width: 32),
                      PopupMenuButton<TrackOverflowAction>(
                        tooltip: 'Track options',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 28,
                          color: pal.textPrimary.withValues(alpha: 0.82),
                        ),
                        onSelected: (action) {
                          unawaited(
                            applyTrackOverflowAction(
                              context,
                              player,
                              player.currentIndex,
                              action,
                            ),
                          );
                        },
                        itemBuilder: (context) =>
                            trackOverflowPopupMenuEntries(
                          enableDeleteFromDevice:
                              trackCanDeleteFromDevice(cur),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.currentTrack;
        if (track == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _safeCollapse();
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          backgroundColor: pal.surface,
          appBar: AppBar(
            backgroundColor: pal.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to library',
              onPressed: _safeCollapse,
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollForDismiss,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                        sliver: SliverToBoxAdapter(
                          child: ListenableBuilder(
                            listenable: player,
                            builder: (context, _) {
                              final t = player.currentTrack;
                              if (t == null) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  Center(
                                    child: TrackAlbumArt(
                                      track: t,
                                      display: TrackArtDisplay.nowPlaying,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    t.title,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    t.artist,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 20),
                                  StreamBuilder<Duration>(
                                    stream: player.audioPlayer.positionStream,
                                    builder: (context, posSnap) {
                                      return StreamBuilder<Duration?>(
                                        stream: player.audioPlayer.durationStream,
                                        builder: (context, durSnap) {
                                          final dur = durSnap.data ?? player.duration;
                                          final pos = posSnap.data ?? player.position;
                                          final totalMs = dur?.inMilliseconds ?? 0;
                                          final posMs = pos.inMilliseconds;
                                          final sliderValue = _dragPositionFraction ??
                                              (totalMs > 0
                                                  ? (posMs / totalMs).clamp(0.0, 1.0)
                                                  : 0.0);

                                          return Row(
                                            children: [
                                              Text(
                                                _formatDuration(pos),
                                                style: theme.textTheme.labelSmall,
                                              ),
                                              Expanded(
                                                child: Slider(
                                                  value: sliderValue.clamp(0.0, 1.0),
                                                  onChanged: totalMs > 0
                                                      ? (v) => setState(
                                                            () => _dragPositionFraction = v,
                                                          )
                                                      : null,
                                                  onChangeEnd: totalMs > 0
                                                      ? (v) {
                                                          player.seek(
                                                            Duration(
                                                              milliseconds:
                                                                  (v * totalMs).round(),
                                                            ),
                                                          );
                                                          setState(
                                                            () => _dragPositionFraction =
                                                                null,
                                                          );
                                                        }
                                                      : null,
                                                ),
                                              ),
                                              Text(
                                                dur != null
                                                    ? _formatDuration(dur)
                                                    : '--:--',
                                                style: theme.textTheme.labelSmall,
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: 'Shuffle',
                                        icon: Icon(
                                          Icons.shuffle_rounded,
                                          color: player.shuffleEnabled
                                              ? pal.primary
                                              : pal.textSecondary,
                                        ),
                                        onPressed: player.playlist.length < 2
                                            ? null
                                            : () => player.toggleShuffle(),
                                      ),
                                      const SizedBox(width: 24),
                                      IconButton(
                                        tooltip: 'Repeat mode',
                                        icon: Icon(
                                          player.repeatMode == PlaylistRepeatMode.one
                                              ? Icons.repeat_one_rounded
                                              : Icons.repeat_rounded,
                                          color: player.repeatMode == PlaylistRepeatMode.off
                                              ? pal.textSecondary
                                                  .withValues(alpha: 0.55)
                                              : pal.primary,
                                        ),
                                        onPressed: () => player.cycleRepeatMode(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        iconSize: 36,
                                        icon: const Icon(Icons.skip_previous_rounded),
                                        color: pal.textPrimary,
                                        onPressed: () => player.skipPrevious(),
                                      ),
                                      const SizedBox(width: 20),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: pal.surface,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.08),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: IconButton.filled(
                                          iconSize: 40,
                                          style: IconButton.styleFrom(
                                            backgroundColor: pal.surface,
                                            foregroundColor: pal.textSecondary,
                                            padding: const EdgeInsets.all(20),
                                            elevation: 0,
                                          ),
                                          onPressed: () => player.togglePlayPause(),
                                          icon: Icon(
                                            player.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      IconButton(
                                        iconSize: 36,
                                        icon: const Icon(Icons.skip_next_rounded),
                                        color: pal.textPrimary,
                                        onPressed: () => player.skipNext(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ListenableBuilder(
                          listenable: player,
                          builder: (context, _) {
                            return _UpNextPanel(
                              next: player.upcomingTrack,
                              pal: pal,
                              theme: theme,
                              repeatMode: player.repeatMode,
                              queueLength: player.playlist.length,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _footerTrackTools(pal, player),
            ],
          ),
        );
      },
    );
  }
}

class _UpNextPanel extends StatelessWidget {
  const _UpNextPanel({
    required this.next,
    required this.pal,
    required this.theme,
    required this.repeatMode,
    required this.queueLength,
  });

  final TrackItem? next;
  final AppPalette pal;
  final ThemeData theme;
  final PlaylistRepeatMode repeatMode;
  final int queueLength;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: pal.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    final titleStyle = theme.textTheme.titleMedium?.copyWith(color: pal.textPrimary);
    final artistStyle =
        theme.textTheme.bodyMedium?.copyWith(color: pal.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Up next',
                style: labelStyle,
              ),
              const SizedBox(height: 12),
              if (next != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TrackAlbumArt(track: next!, display: TrackArtDisplay.list),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            next!.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            next!.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: artistStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else if (repeatMode == PlaylistRepeatMode.one &&
                  queueLength > 0 &&
                  next == null)
                Text(
                  'This track repeats when it finishes.',
                  style: artistStyle?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.95),
                  ),
                )
              else if (queueLength <= 1)
                Text(
                  'Only one song in queue.',
                  style: artistStyle?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.95),
                  ),
                )
              else
                Text(
                  'No more tracks queued.',
                  style: artistStyle?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.95),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
