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
  const NowPlayingScreen({
    super.key,
    required this.sourceTitle,
    required this.sourceSubtitle,
    required this.onCollapse,
  });

  final String sourceTitle;
  final String sourceSubtitle;
  final VoidCallback onCollapse;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double? _dragPositionFraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const sheetRadius = 36.0;
    final player = PlayerController.of(context);
    final track = player.currentTrack;

    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCollapse();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded),
                    color: AppColors.textOnNavy,
                    tooltip: 'Edit tags & cover',
                    onPressed: track.filePath == null || track.filePath!.isEmpty
                        ? null
                        : () {
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: AppColors.surface,
                              showDragHandle: false,
                              builder: (ctx) => EditTrackTagsSheet(track: track),
                            );
                          },
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.sourceTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textOnNavy.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.sourceSubtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textOnNavy,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                    color: AppColors.textOnNavy,
                    onPressed: widget.onCollapse,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(0, -4),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                child: ListenableBuilder(
                  listenable: player,
                  builder: (context, _) {
                    final t = player.currentTrack;
                    if (t == null) {
                      return const SizedBox.shrink();
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: Column(
                        children: [
                          TrackAlbumArt(track: t, display: TrackArtDisplay.full),
                          const SizedBox(height: 32),
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
                          const SizedBox(height: 28),
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
                                      (totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0);

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
                                              ? (v) => setState(() => _dragPositionFraction = v)
                                              : null,
                                          onChangeEnd: totalMs > 0
                                              ? (v) {
                                                  player.seek(
                                                    Duration(
                                                      milliseconds: (v * totalMs).round(),
                                                    ),
                                                  );
                                                  setState(() => _dragPositionFraction = null);
                                                }
                                              : null,
                                        ),
                                      ),
                                      Text(
                                        dur != null ? _formatDuration(dur) : '--:--',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          ListenableBuilder(
                            listenable: player,
                            builder: (context, _) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Shuffle',
                                    icon: Icon(
                                      Icons.shuffle_rounded,
                                      color: player.shuffleEnabled
                                          ? AppColors.navy
                                          : AppColors.textSecondary,
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
                                          ? AppColors.textSecondary.withOpacity(0.55)
                                          : AppColors.navy,
                                    ),
                                    onPressed: () => player.cycleRepeatMode(),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.skip_previous_rounded),
                                color: AppColors.textPrimary,
                                onPressed: () => player.skipPrevious(),
                              ),
                              const SizedBox(width: 20),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: IconButton.filled(
                                  iconSize: 40,
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.surface,
                                    foregroundColor: AppColors.textSecondary,
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
                                color: AppColors.textPrimary,
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
          ),
        ],
      ),
    );
  }
}
