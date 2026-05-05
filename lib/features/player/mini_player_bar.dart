import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';

/// Rounded capsule thumb for the seek slider.
final class _MiniPlayerThumbShape extends SliderComponentShape {
  const _MiniPlayerThumbShape({required this.color});

  final Color color;

  static const double width = 12;
  static const double height = 6;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final rrect = RRect.fromRectXY(rect, 3, 3);
    context.canvas.drawRRect(
      rrect,
      Paint()..color = color,
    );
  }
}

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final PlayerController controller;
  final VoidCallback onTap;

  /// Frosted chrome top corners (mini bar aligns with Now Playing sheet).
  static const double topSheetRadius = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final playerChrome = context.usesPlayerChrome;
    final accent = context.controlAccent;
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = playerChrome ? 22.0 : 15.0;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.white.withValues(alpha: 0.82);
    final glassBottom = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.68);
    final borderRadius = const BorderRadius.vertical(
      top: Radius.circular(topSheetRadius),
    );
    final iconColor = pal.textPrimary;
    final mutedIcon = pal.textSecondary.withValues(alpha: 0.38);
    final thumbColor =
        isDark ? Colors.white : pal.textPrimary.withValues(alpha: 0.92);

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onTap,
                    borderRadius: borderRadius.copyWith(
                      bottomLeft: Radius.zero,
                      bottomRight: Radius.zero,
                    ),
                    splashColor: pal.primary.withValues(alpha: 0.08),
                    highlightColor: pal.primary.withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                      child: Row(
                        children: [
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              return TrackAlbumArt(
                                track: controller.currentTrack!,
                                display: TrackArtDisplay.mini,
                                showShadow: true,
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.25,
                                    color: pal.textPrimary,
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              color: iconColor,
                              size: 30,
                            ),
                            onPressed: () => controller.skipPrevious(),
                          ),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final playing = controller.isPlaying;
                              return SizedBox(
                                width: 48,
                                height: 48,
                                child: Material(
                                  color: accent,
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        controller.togglePlayPause(),
                                    customBorder: const CircleBorder(),
                                    child: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final canNext = controller.canSkipNext;
                              return IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: canNext
                                    ? 'Next track'
                                    : 'End of playlist',
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  color:
                                      canNext ? iconColor : mutedIcon,
                                  size: 30,
                                ),
                                onPressed: canNext
                                    ? () => controller.skipNext()
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
                                ? (pos.inMilliseconds / total)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                            return SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor:
                                    accent.withValues(alpha: 0.92),
                                inactiveTrackColor: pal.textMuted.withValues(
                                  alpha: 0.32,
                                ),
                                thumbColor: thumbColor,
                                overlayColor:
                                    WidgetStateColor.resolveWith(
                                  (_) => Colors.transparent,
                                ),
                                thumbShape: _MiniPlayerThumbShape(
                                  color: thumbColor,
                                ),
                                trackShape:
                                    const RoundedRectSliderTrackShape(),
                                padding: EdgeInsets.zero,
                              ),
                              child: Slider(
                                value: p,
                                onChanged: total <= 0
                                    ? null
                                    : (v) {
                                        controller.seek(
                                          Duration(
                                            milliseconds: (v * total)
                                                .round()
                                                .clamp(0, total),
                                          ),
                                        );
                                      },
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
    );
  }
}
