import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../audio/player_controller.dart';
import '../theme/app_theme.dart';
import 'daisy_background.dart';
import 'track_album_art.dart';

/// Pill thumb on the seek bar (reference-style).
final class _GlassMiniPlayerThumbShape extends SliderComponentShape {
  const _GlassMiniPlayerThumbShape({required this.color});

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

/// Frosted “glass” mini player: circular art, title, skip + play/pause + seek.
///
/// Rebuilds art and title when [controller] notifies; position/duration via streams.
/// Call only when [PlayerController.currentTrack] is non-null (parent may wrap with
/// [SizedBox.shrink] when idle).
class GlassMiniPlayer extends StatefulWidget {
  const GlassMiniPlayer({
    super.key,
    required this.controller,
    required this.onTap,
    this.topCornerRadius = 28,
  });

  final PlayerController controller;
  final VoidCallback onTap;

  /// Rounded top sheet radius; align with full-screen Now Playing for one continuous edge.
  final double topCornerRadius;

  @override
  State<GlassMiniPlayer> createState() => _GlassMiniPlayerState();
}

class _GlassMiniPlayerState extends State<GlassMiniPlayer> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final playerChrome = context.usesPlayerChrome;
    final accent = context.controlAccent;
    final palette = context.appliedThemePalette;
    final daisy = context.appliedThemePalette == AppThemePalette.daisy;
    final leah = palette == AppThemePalette.leah;

    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = playerChrome ? 24.0 : 18.0;

    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(widget.topCornerRadius),
    );

    final borderColor = daisy
        ? const Color(0xFF9A856A).withValues(alpha: 0.55)
        : leah
        ? const Color(0xFF8B7A64).withValues(alpha: 0.48)
        : isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.08);

    /// Dark reference: charcoal tint over blur; light: bright frosted sheet.
    final List<Color> glassGradient = daisy
        ? [
            const Color(0xFFE5D8C4).withValues(alpha: 0.94),
            const Color(0xFFD3C0A7).withValues(alpha: 0.92),
          ]
        : leah
        ? [
            const Color(0xFFF3EBE0).withValues(alpha: 0.94),
            const Color(0xFFE5DACB).withValues(alpha: 0.9),
          ]
        : isDark
        ? [
            const Color(0xA0181818),
            const Color(0xC0222222),
          ]
        : [
            Colors.white.withValues(alpha: 0.82),
            Colors.white.withValues(alpha: 0.66),
          ];

    final titleColor = daisy
        ? const Color(0xFF2B2117)
        : leah
        ? const Color(0xFF2D241B)
        : isDark
        ? Colors.white
        : pal.textPrimary;
    final iconColor = daisy
        ? const Color(0xFF2B2117)
        : leah
        ? const Color(0xFF2D241B)
        : isDark
        ? Colors.white
        : pal.textPrimary;
    final mutedIcon = daisy
        ? const Color(0xFF2B2117).withValues(alpha: 0.42)
        : leah
        ? const Color(0xFF2D241B).withValues(alpha: 0.4)
        : isDark
        ? Colors.white.withValues(alpha: 0.38)
        : pal.textSecondary.withValues(alpha: 0.38);
    final thumbColor = daisy
        ? const Color(0xFF2B2117)
        : leah
        ? const Color(0xFF2D241B)
        : isDark
        ? Colors.white
        : pal.textPrimary.withValues(alpha: 0.92);
    final inactiveTrack = daisy
        ? const Color(0xFF2B2117).withValues(alpha: 0.24)
        : leah
        ? const Color(0xFF2D241B).withValues(alpha: 0.22)
        : isDark
        ? Colors.white.withValues(alpha: 0.28)
        : pal.textMuted.withValues(alpha: 0.32);
    final playButtonBg = (daisy || leah) ? const Color(0xFF151515) : accent;
    final playButtonFg = (daisy || leah)
        ? const Color(0xFFF0E4D2)
        : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (daisy ? const Color(0xFF2A2118) : Colors.black).withValues(
              alpha: playerChrome ? 0.34 : 0.22,
            ),
            blurRadius: playerChrome ? 24 : 16,
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
                colors: glassGradient,
              ),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (daisy || leah)
                  Positioned.fill(
                    child: Opacity(
                      opacity: daisy ? 0.5 : 0.44,
                      child: Image.asset(
                        daisy ? daisyTextureAssetPath : leahTextureAssetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  InkWell(
                    onTap: widget.onTap,
                    borderRadius: borderRadius.copyWith(
                      bottomLeft: Radius.zero,
                      bottomRight: Radius.zero,
                    ),
                    splashColor:
                        accent.withValues(alpha: isDark ? 0.14 : 0.10),
                    highlightColor:
                        accent.withValues(alpha: isDark ? 0.08 : 0.06),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
                      child: Row(
                        children: [
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (context, _) {
                              final t = widget.controller.currentTrack!;
                              return TrackAlbumArt(
                                key: ValueKey<int>(Object.hash(
                                  t.filePath,
                                  t.title,
                                  identityHashCode(t.albumArtBytes),
                                )),
                                track: t,
                                display: TrackArtDisplay.mini,
                                showShadow: false,
                              );
                            },
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: widget.controller,
                              builder: (context, _) {
                                final t = widget.controller.currentTrack!;
                                return Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: titleColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              color: iconColor,
                              size: 30,
                              semanticLabel: 'Previous track',
                            ),
                            onPressed: () => widget.controller.skipPrevious(),
                          ),
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (context, _) {
                              final playing = widget.controller.isPlaying;
                              return SizedBox(
                                width: 48,
                                height: 48,
                                child: Material(
                                  color: playButtonBg,
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        widget.controller.togglePlayPause(),
                                    customBorder: const CircleBorder(),
                                    child: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: playButtonFg,
                                      size: 30,
                                      semanticLabel: playing
                                          ? 'Pause'
                                          : 'Play',
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (context, _) {
                              final canNext = widget.controller.canSkipNext;
                              return IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
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
                                  semanticLabel: 'Next track',
                                ),
                                onPressed: canNext
                                    ? () => widget.controller.skipNext()
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                    child: StreamBuilder<Duration>(
                      stream: widget.controller.audioPlayer.positionStream,
                      builder: (context, posSnap) {
                        return StreamBuilder<Duration?>(
                          stream: widget.controller.audioPlayer.durationStream,
                          builder: (context, durSnap) {
                            final dur = durSnap.data ?? widget.controller.duration;
                            final pos =
                                posSnap.data ?? widget.controller.position;
                            final total = dur?.inMilliseconds ?? 0;
                            final live = total > 0
                                ? (pos.inMilliseconds / total)
                                    .clamp(0.0, 1.0)
                                : 0.0;
                            final p = (_dragFraction ?? live).clamp(0.0, 1.0);

                            return SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor:
                                    (daisy || leah) ? iconColor : accent,
                                inactiveTrackColor: inactiveTrack,
                                thumbColor: thumbColor,
                                overlayColor:
                                    WidgetStateColor.resolveWith(
                                  (_) => Colors.transparent,
                                ),
                                thumbShape:
                                    _GlassMiniPlayerThumbShape(
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
                                        setState(() => _dragFraction = v);
                                      },
                                onChangeEnd: total <= 0
                                    ? null
                                    : (v) {
                                        widget.controller.seek(
                                          Duration(
                                            milliseconds: (v * total)
                                                .round()
                                                .clamp(0, total),
                                          ),
                                        );
                                        if (mounted) {
                                          setState(() => _dragFraction = null);
                                        }
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
