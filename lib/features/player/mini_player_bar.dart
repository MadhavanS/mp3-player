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

    return Material(
      color: playerChrome ? pal.scaffoldBackground : pal.surface,
      elevation: playerChrome ? 18 : 12,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius)),
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
                          style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
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
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    color: pal.textPrimary,
                    onPressed: () => controller.skipNext(),
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
                      final p =
                          total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 2,
                          backgroundColor: pal.textMuted.withValues(alpha: 0.25),
                          color: pal.primary.withValues(alpha: 0.7),
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
    );
  }
}
