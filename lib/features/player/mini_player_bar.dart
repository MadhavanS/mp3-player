import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final PlayerController controller;
  final VoidCallback onTap;

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final playerChrome = context.usesPlayerChrome;
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = playerChrome ? 22.0 : 15.0;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop =
        isDark ? Colors.white.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.82);
    final glassBottom =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.68);
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(_radius));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: playerChrome ? 0.32 : 0.18),
            blurRadius: playerChrome ? 22 : 14,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border(
                left: BorderSide(color: borderColor),
                top: BorderSide(color: borderColor),
                right: BorderSide(color: borderColor),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [glassTop, glassBottom],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        children: [
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              return TrackAlbumArt(
                                track: controller.currentTrack!,
                                display: TrackArtDisplay.mini,
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) {
                                final t = controller.currentTrack!;
                                return Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    color: pal.textPrimary,
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: pal.textPrimary,
                            onPressed: () => controller.skipPrevious(),
                          ),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final playing = controller.isPlaying;
                              return IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: pal.primary,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => controller.togglePlayPause(),
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              );
                            },
                          ),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final canNext = controller.canSkipNext;
                              return IconButton(
                                tooltip:
                                    canNext ? 'Next track' : 'End of playlist',
                                icon: const Icon(Icons.skip_next_rounded),
                                color: canNext
                                    ? pal.textPrimary
                                    : pal.textSecondary
                                        .withValues(alpha: 0.38),
                                onPressed: canNext
                                    ? () => controller.skipNext()
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                      child: StreamBuilder<Duration>(
                        stream: controller.audioPlayer.positionStream,
                        builder: (context, posSnap) {
                          return StreamBuilder<Duration?>(
                            stream: controller.audioPlayer.durationStream,
                            builder: (context, durSnap) {
                              final dur = durSnap.data ?? controller.duration;
                              final pos = posSnap.data ?? controller.position;
                              final total = dur?.inMilliseconds ?? 0;
                              final p = total > 0
                                  ? (pos.inMilliseconds / total).clamp(0.0, 1.0)
                                  : 0.0;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: p,
                                  minHeight: 2,
                                  backgroundColor:
                                      pal.textMuted.withValues(alpha: 0.28),
                                  color: pal.primary.withValues(alpha: 0.72),
                                ),
                              );
                            },
                          );
                        },
                      ),
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
