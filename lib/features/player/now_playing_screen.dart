import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';
import 'edit_track_tags_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    const sheetRadius = 36.0;
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
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        offset: const Offset(0, -2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (_) => _resetPullDismiss(),
                          onVerticalDragUpdate: (d) => _onPullDownUpdate(d.delta.dy),
                          onVerticalDragEnd: (d) {
                            final v = d.primaryVelocity;
                            if (v != null && v > 220) {
                              _safeCollapse();
                            }
                            _resetPullDismiss();
                          },
                          child: SizedBox(
                            height: 40,
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: pal.textMuted.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onScrollForDismiss,
                            child: ListenableBuilder(
                              listenable: player,
                              builder: (context, _) {
                                final t = player.currentTrack;
                                if (t == null) {
                                  return const SizedBox.shrink();
                                }
                                return SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                                  child: Column(
                                    children: [
                                      TrackAlbumArt(
                                        track: t,
                                        display: TrackArtDisplay.full,
                                      ),
                                      const SizedBox(height: 28),
                                      Text(
                                        t.title,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t.artist,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 24),
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
                                      const SizedBox(height: 8),
                                      ListenableBuilder(
                                        listenable: player,
                                        builder: (context, _) {
                                          final cur = player.currentTrack;
                                          final canEdit = cur != null &&
                                              cur.filePath != null &&
                                              cur.filePath!.isNotEmpty;
                                          return Row(
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
                                              const SizedBox(width: 8),
                                              IconButton(
                                                tooltip: 'Edit tags & cover',
                                                icon: Icon(
                                                  Icons.edit_note_rounded,
                                                  color: canEdit
                                                      ? pal.primary
                                                      : pal.textSecondary
                                                          .withValues(alpha: 0.45),
                                                ),
                                                onPressed: canEdit
                                                    ? () => _openTagEditor(player)
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                tooltip: 'Repeat mode',
                                                icon: Icon(
                                                  player.repeatMode == PlaylistRepeatMode.one
                                                      ? Icons.repeat_one_rounded
                                                      : Icons.repeat_rounded,
                                                  color: player.repeatMode ==
                                                          PlaylistRepeatMode.off
                                                      ? pal.textSecondary
                                                          .withValues(alpha: 0.55)
                                                      : pal.primary,
                                                ),
                                                onPressed: () => player.cycleRepeatMode(),
                                              ),
                                            ],
                                          );
                                        },
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
                                                  color: Colors.black
                                                      .withValues(alpha: 0.08),
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
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
