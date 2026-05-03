import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';
import '../../widgets/track_album_art.dart';
import 'edit_track_tags_sheet.dart';
import 'site_rename_standalone_dialog.dart';
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

  void _showTagSheet(PlayerController player) {
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

  void _openTagEditor(PlayerController player) =>
      _showTagSheet(player);

  void _notifyShuffle(PlayerController player) {
    if (player.playlist.length < 2) return;
    player.toggleShuffle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ActionPillToast.showUsingRootNavigator(
        player.shuffleEnabled ? 'Shuffle on' : 'Shuffle off',
        icon: Icons.shuffle_rounded,
        uppercaseLabel: true,
      );
    });
  }

  void _notifyRepeat(PlayerController player) {
    player.cycleRepeatMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mode = player.repeatMode;
      final msg = switch (mode) {
        PlaylistRepeatMode.off => 'Repeat off',
        PlaylistRepeatMode.all => 'Repeat all',
        PlaylistRepeatMode.one => 'Repeat current',
      };
      final icon = mode == PlaylistRepeatMode.one
          ? Icons.repeat_one_rounded
          : Icons.repeat_rounded;
      ActionPillToast.showUsingRootNavigator(
        msg,
        icon: icon,
        uppercaseLabel: true,
      );
    });
  }

  Widget _favoriteButton(AppPalette pal, TrackItem cur) {
    final path = cur.filePath ?? '';
    final canFav = path.isNotEmpty;
    return FutureBuilder<void>(
      future: FavoriteSongsStore.ensureLoaded(),
      builder: (context, snap) {
        final ready = snap.connectionState == ConnectionState.done;
        return ListenableBuilder(
          listenable: FavoriteSongsStore.revision,
          builder: (context, _) {
            final isFav = canFav && FavoriteSongsStore.isFavorite(path);
            return IconButton(
              iconSize: 28,
              tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: !canFav
                    ? pal.textSecondary.withValues(alpha: 0.35)
                    : isFav
                        ? pal.primary
                        : pal.textSecondary.withValues(alpha: 0.55),
              ),
              onPressed: !ready || !canFav
                  ? null
                  : () async {
                      final nowFav =
                          await FavoriteSongsStore.toggleFavorite(path);
                      if (!context.mounted) return;
                      ActionPillToast.showUsingRootNavigator(
                        nowFav ? 'Favourited' : 'Removed from favourites',
                        icon: nowFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        uppercaseLabel: true,
                      );
                    },
            );
          },
        );
      },
    );
  }

  Widget _footerTrackTools(
    BuildContext context,
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

        final footerChrome = context.usesPlayerChrome;
        final navIconColor =
            footerChrome ? pal.onScaffold : pal.textPrimary;
        return Material(
          color: footerChrome ? pal.scaffoldBackground : pal.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, thickness: 1, color: pal.dividerOnHero),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip:
                            footerChrome ? 'Collapse' : 'Back to library',
                        iconSize: 28,
                        icon: Icon(
                          footerChrome
                              ? Icons.expand_more_rounded
                              : Icons.arrow_back_rounded,
                          color: navIconColor,
                        ),
                        onPressed: _safeCollapse,
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit tags & cover',
                              iconSize: 28,
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
                            _favoriteButton(pal, cur),
                            IconButton(
                              tooltip: 'Clean site-style name',
                              iconSize: 28,
                              icon: Icon(
                                Icons.auto_fix_high_outlined,
                                color: canEdit
                                    ? pal.primary
                                    : pal.textSecondary
                                        .withValues(alpha: 0.45),
                              ),
                              onPressed: canEdit && !kIsWeb
                                  ? () =>
                                      showStandaloneSiteRenameDialog(
                                          context, cur)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<TrackOverflowAction>(
                        tooltip: 'Track options',
                        padding: EdgeInsets.zero,
                        position: PopupMenuPosition.under,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: navIconColor,
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
                        itemBuilder: (context) => trackOverflowPopupMenuEntries(
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

        final playerChrome = context.usesPlayerChrome;
        final pageBg =
            playerChrome ? pal.scaffoldBackground : pal.surface;

        return Scaffold(
          backgroundColor: pageBg,
          body: SafeArea(
            bottom: false,
            child: Column(
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
                                    child: _NowPlayingAlbumArtCard(
                                      playerChrome: playerChrome,
                                      theme: theme,
                                      title: t.title,
                                      artist: t.artist,
                                      artwork: TrackAlbumArt(
                                        track: t,
                                        display:
                                            TrackArtDisplay.nowPlaying,
                                        showShadow: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
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
                                  if (playerChrome)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: 'Shuffle',
                                          icon: Icon(
                                            Icons.shuffle_rounded,
                                            color: player.shuffleEnabled
                                                ? pal.primary
                                                : pal.textSecondary
                                                    .withValues(alpha: 0.55),
                                          ),
                                          onPressed: player.playlist.length <
                                                  2
                                              ? null
                                              : () => _notifyShuffle(player),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          iconSize: 36,
                                          icon: const Icon(
                                            Icons.skip_previous_rounded,
                                          ),
                                          color: pal.textPrimary,
                                          onPressed: () =>
                                              player.skipPrevious(),
                                        ),
                                        const SizedBox(width: 16),
                                        ListenableBuilder(
                                          listenable: player,
                                          builder: (context, _) {
                                            final playing =
                                                player.isPlaying;
                                            return IconButton.filled(
                                              tooltip: playing
                                                  ? 'Pause'
                                                  : 'Play',
                                              iconSize: 36,
                                              style: IconButton.styleFrom(
                                                backgroundColor:
                                                    pal.primary,
                                                foregroundColor:
                                                    Colors.white,
                                                fixedSize:
                                                    const Size(76, 76),
                                              ),
                                              onPressed: () => player
                                                  .togglePlayPause(),
                                              icon: Icon(
                                                playing
                                                    ? Icons.pause_rounded
                                                    : Icons
                                                        .play_arrow_rounded,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 16),
                                        ListenableBuilder(
                                          listenable: player,
                                          builder: (context, _) {
                                            final canNext =
                                                player.canSkipNext;
                                            return IconButton(
                                              tooltip: canNext
                                                  ? 'Next track'
                                                  : 'End of playlist',
                                              iconSize: 36,
                                              icon: const Icon(
                                                Icons.skip_next_rounded,
                                              ),
                                              color: canNext
                                                  ? pal.textPrimary
                                                  : pal.textSecondary
                                                      .withValues(
                                                        alpha: 0.38,
                                                      ),
                                              onPressed: canNext
                                                  ? () =>
                                                      player.skipNext()
                                                  : null,
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'Repeat mode',
                                          icon: Icon(
                                            player.repeatMode ==
                                                    PlaylistRepeatMode.one
                                                ? Icons.repeat_one_rounded
                                                : Icons.repeat_rounded,
                                            color:
                                                player.repeatMode ==
                                                        PlaylistRepeatMode
                                                            .off
                                                    ? pal.textSecondary
                                                        .withValues(
                                                          alpha: 0.55,
                                                        )
                                                    : pal.primary,
                                          ),
                                          onPressed: () => _notifyRepeat(player),
                                        ),
                                      ],
                                    )
                                  else ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: 'Shuffle',
                                          icon: Icon(
                                            Icons.shuffle_rounded,
                                            color: player.shuffleEnabled
                                                ? pal.primary
                                                : pal.textSecondary
                                                    .withValues(alpha: 0.55),
                                          ),
                                          onPressed:
                                              player.playlist.length < 2
                                                  ? null
                                                  : () =>
                                                      _notifyShuffle(player),
                                        ),
                                        const SizedBox(width: 24),
                                        IconButton(
                                          tooltip: 'Repeat mode',
                                          icon: Icon(
                                            player.repeatMode ==
                                                    PlaylistRepeatMode.one
                                                ? Icons.repeat_one_rounded
                                                : Icons.repeat_rounded,
                                            color: player.repeatMode ==
                                                    PlaylistRepeatMode.off
                                                ? pal.textSecondary
                                                    .withValues(alpha: 0.55)
                                                : pal.primary,
                                          ),
                                          onPressed: () =>
                                              _notifyRepeat(player),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          iconSize: 36,
                                          icon: const Icon(
                                            Icons.skip_previous_rounded,
                                          ),
                                          color: pal.textPrimary,
                                          onPressed: () =>
                                              player.skipPrevious(),
                                        ),
                                        const SizedBox(width: 20),
                                        ListenableBuilder(
                                          listenable: player,
                                          builder: (context, _) {
                                            final playing =
                                                player.isPlaying;
                                            return IconButton.filled(
                                              tooltip: playing
                                                  ? 'Pause'
                                                  : 'Play',
                                              iconSize: 40,
                                              style: IconButton.styleFrom(
                                                backgroundColor:
                                                    pal.primary,
                                                foregroundColor:
                                                    Colors.white,
                                                padding:
                                                    const EdgeInsets.all(20),
                                                elevation: 0,
                                              ),
                                              onPressed: () => player
                                                  .togglePlayPause(),
                                              icon: Icon(
                                                playing
                                                    ? Icons.pause_rounded
                                                    : Icons
                                                        .play_arrow_rounded,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 20),
                                        ListenableBuilder(
                                          listenable: player,
                                          builder: (context, _) {
                                            final canNext =
                                                player.canSkipNext;
                                            return IconButton(
                                              tooltip: canNext
                                                  ? 'Next track'
                                                  : 'End of playlist',
                                              iconSize: 36,
                                              icon: const Icon(
                                                Icons.skip_next_rounded,
                                              ),
                                              color: canNext
                                                  ? pal.textPrimary
                                                  : pal.textSecondary
                                                      .withValues(
                                                        alpha: 0.38,
                                                      ),
                                              onPressed: canNext
                                                  ? () =>
                                                      player.skipNext()
                                                  : null,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
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
                              playerChrome: playerChrome,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _footerTrackTools(context, pal, player),
            ],
          ),
        ),
        );
      },
    );
  }
}

/// Frosted glass frame (blur + translucent gradient) around artwork and metadata.
class _NowPlayingAlbumArtCard extends StatelessWidget {
  const _NowPlayingAlbumArtCard({
    required this.playerChrome,
    required this.theme,
    required this.title,
    required this.artist,
    required this.artwork,
  });

  final bool playerChrome;
  final ThemeData theme;
  final String title;
  final String artist;
  final Widget artwork;

  @override
  Widget build(BuildContext context) {
    final outerR = playerChrome ? 32.0 : 24.0;
    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = playerChrome ? 26.0 : 18.0;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop =
        isDark ? Colors.white.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.82);
    final glassBottom =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.68);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: playerChrome ? 0.42 : 0.24,
              ),
              blurRadius: playerChrome ? 28 : 20,
              offset: Offset(0, playerChrome ? 12 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(outerR),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(outerR),
                border: Border.all(width: 1, color: borderColor),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    glassTop,
                    glassBottom,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: artwork),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      artist,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Player theme: frosted “Up next” row matching hero glass + primary-tinted labels.
class _UpNextGlassTrackCard extends StatelessWidget {
  const _UpNextGlassTrackCard({
    required this.pal,
    required this.theme,
    required this.track,
  });

  final AppPalette pal;
  final ThemeData theme;
  final TrackItem track;

  static const _r = 22.0;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.white.withValues(alpha: 0.78);
    final glassBottom = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.62);

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: pal.primary,
      fontSize: 15,
    );
    final artistStyle = theme.textTheme.bodySmall?.copyWith(
      color: pal.primary.withValues(alpha: 0.78),
      fontSize: 13,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_r),
              border: Border.all(width: 1, color: borderColor),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [glassTop, glassBottom],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TrackAlbumArt(track: track, display: TrackArtDisplay.list),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: artistStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    required this.playerChrome,
  });

  final TrackItem? next;
  final AppPalette pal;
  final ThemeData theme;
  final PlaylistRepeatMode repeatMode;
  final int queueLength;
  final bool playerChrome;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: pal.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    final titleStyle =
        theme.textTheme.titleMedium?.copyWith(color: pal.textPrimary);
    final artistStyle =
        theme.textTheme.bodyMedium?.copyWith(color: pal.textSecondary);

    Widget upNextInner() {
      if (next != null && playerChrome) {
        return _UpNextGlassTrackCard(
          pal: pal,
          theme: theme,
          track: next!,
        );
      }
      if (next != null) {
        return Row(
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
        );
      }
      if (repeatMode == PlaylistRepeatMode.one &&
          queueLength > 0 &&
          next == null) {
        return Text(
          'This track repeats when it finishes.',
          style: artistStyle?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
          ),
        );
      }
      if (queueLength <= 1) {
        return Text(
          'Only one song in queue.',
          style: artistStyle?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
          ),
        );
      }
      return Text(
        'No more tracks queued.',
        style: artistStyle?.copyWith(
          color: pal.textMuted.withValues(alpha: 0.95),
        ),
      );
    }

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
              upNextInner(),
            ],
          ),
        ),
      ),
    );
  }
}
