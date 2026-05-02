import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';

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
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Material(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      return _ArtThumb(track: controller.currentTrack!);
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
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      return IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: controller.shuffleEnabled
                              ? AppColors.navy
                              : AppColors.textSecondary,
                        ),
                        onPressed: controller.playlist.length < 2
                            ? null
                            : () => controller.toggleShuffle(),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    color: AppColors.textPrimary,
                    onPressed: () => controller.skipPrevious(),
                  ),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final playing = controller.isPlaying;
                      return IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: AppColors.surface,
                        ),
                        onPressed: () => controller.togglePlayPause(),
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    color: AppColors.textPrimary,
                    onPressed: () => controller.skipNext(),
                  ),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final mode = controller.repeatMode;
                      return IconButton(
                        tooltip: 'Repeat',
                        icon: Icon(
                          mode == PlaylistRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: mode == PlaylistRepeatMode.off
                              ? AppColors.textSecondary.withOpacity(0.55)
                              : AppColors.navy,
                        ),
                        onPressed: () => controller.cycleRepeatMode(),
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
                      final p =
                          total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 2,
                          backgroundColor: AppColors.textMuted.withOpacity(0.25),
                          color: AppColors.navy.withOpacity(0.7),
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

class _ArtThumb extends StatelessWidget {
  const _ArtThumb({required this.track});

  final TrackItem track;

  @override
  Widget build(BuildContext context) {
    final bytes = track.albumArtBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _gradientCircle(),
        ),
      );
    }
    return _gradientCircle();
  }

  Widget _gradientCircle() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: track.artColors,
        ),
        boxShadow: [
          BoxShadow(
            color: track.artColors.first.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}
