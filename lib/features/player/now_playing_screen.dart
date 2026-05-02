import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../theme/app_theme.dart';

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
                    icon: const Icon(Icons.more_horiz_rounded),
                    color: AppColors.textOnNavy,
                    onPressed: () {},
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
                          _AlbumArt(colors: t.artColors),
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
                                    player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                          const SizedBox(height: 28),
                          _StatsRow(theme: theme),
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

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    const size = 280.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        chip(Icons.keyboard_arrow_up_rounded, '201'),
        chip(Icons.repeat_rounded, '18'),
        chip(Icons.play_arrow_rounded, '2,004'),
        Icon(Icons.add_rounded, color: AppColors.textSecondary, size: 22),
      ],
    );
  }
}
