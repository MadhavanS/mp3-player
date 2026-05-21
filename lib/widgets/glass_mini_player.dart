import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../audio/player_controller.dart';
import '../theme/app_theme.dart';
import 'daisy_background.dart';
import 'liquid_glass.dart';
import 'player_adaptive_controls.dart';
import 'track_album_art.dart';

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
    final silver = palette == AppThemePalette.silver;
    final ivy = palette == AppThemePalette.ivy;

    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = ivy ? 32.0 : (playerChrome ? 24.0 : 18.0);

    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(widget.topCornerRadius),
    );

    final borderColor = daisy
        ? const Color(0xFF9A856A).withValues(alpha: 0.55)
        : leah
        ? const Color(0xFF8B7A64).withValues(alpha: 0.48)
        : ivy
        ? Colors.white.withValues(alpha: 0.55)
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
        : ivy
        ? [
            Colors.white.withValues(alpha: 0.82),
            Colors.white.withValues(alpha: 0.38),
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
        : ivy
        ? const Color(0xFF1C1C1E)
        : isDark
        ? Colors.white
        : pal.textPrimary;
    final iconColor = daisy
        ? const Color(0xFF2B2117)
        : leah
        ? const Color(0xFF2D241B)
        : ivy
        ? const Color(0xFF1C1C1E)
        : isDark
        ? Colors.white
        : pal.textPrimary;
    final mutedIcon = daisy
        ? const Color(0xFF2B2117).withValues(alpha: 0.42)
        : leah
        ? const Color(0xFF2D241B).withValues(alpha: 0.4)
        : ivy
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.32)
        : isDark
        ? Colors.white.withValues(alpha: 0.38)
        : pal.textSecondary.withValues(alpha: 0.38);
    final thumbColor = daisy
        ? const Color(0xFF2B2117)
        : leah
        ? const Color(0xFF2D241B)
        : ivy
        ? const Color(0xFF1C1C1E)
        : isDark
        ? Colors.white
        : pal.textPrimary.withValues(alpha: 0.92);
    final inactiveTrack = daisy
        ? const Color(0xFF2B2117).withValues(alpha: 0.24)
        : leah
        ? const Color(0xFF2D241B).withValues(alpha: 0.22)
        : ivy
        ? const Color(0xFFAEAEB2).withValues(alpha: 0.45)
        : isDark
        ? Colors.white.withValues(alpha: 0.28)
        : pal.textMuted.withValues(alpha: 0.32);
    final playButtonBg = (daisy || leah)
        ? const Color(0xFF151515)
        : ivy
        ? Colors.transparent
        : silver
        ? Colors.white.withValues(alpha: 0.74)
        : accent;
    final playButtonFg = (daisy || leah)
        ? const Color(0xFFF0E4D2)
        : ivy
        ? const Color(0xFF1C1C1E)
        : silver
        ? Colors.black
        : Colors.white;
    final playButtonShape = silver
        ? const CircleBorder(side: BorderSide(color: Colors.black, width: 1.4))
        : const CircleBorder();

    if (ivy) {
      return _buildIvyMiniPlayer(
        theme: theme,
        borderRadius: borderRadius,
        accent: accent,
        titleColor: titleColor,
        iconColor: iconColor,
        mutedIcon: mutedIcon,
        thumbColor: accent,
        inactiveTrack: inactiveTrack,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (daisy ? const Color(0xFF2A2118) : Colors.black)
                .withValues(
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
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
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
                                  shape: playButtonShape,
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => widget.controller
                                        .togglePlayPause(),
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _buildProgressSlider(
                      accent: accent,
                      iconColor: iconColor,
                      thumbColor: thumbColor,
                      inactiveTrack: inactiveTrack,
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

  Widget _buildIvyMiniPlayer({
    required ThemeData theme,
    required BorderRadius borderRadius,
    required Color accent,
    required Color titleColor,
    required Color iconColor,
    required Color mutedIcon,
    required Color thumbColor,
    required Color inactiveTrack,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border(
          top: BorderSide(
            color: accent.withValues(alpha: 0.72),
            width: 2.2,
          ),
        ),
      ),
      child: LiquidGlassConvexSurface(
        borderRadius: borderRadius,
        blurSigma: 20,
        child: Material(
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
              splashColor: Colors.white.withValues(alpha: 0.22),
              highlightColor: Colors.white.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
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
                              shadows: [
                                Shadow(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  offset: const Offset(0, -0.5),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    LiquidGlassRingIconButton(
                      icon: Icons.skip_previous,
                      onPressed: () => widget.controller.skipPrevious(),
                      size: 44,
                      iconSize: 24,
                      accentColor: accent,
                      inactiveColor: const Color(0xFFC8C8CE),
                      disabledColor: const Color(0xFFC7C7CC),
                      highlighted: true,
                      active: true,
                    ),
                    const SizedBox(width: 4),
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final playing = widget.controller.isPlaying;
                        return LiquidGlassRingIconButton(
                          icon: playing
                              ? Icons.pause
                              : Icons.play_arrow,
                          onPressed: () => widget.controller.togglePlayPause(),
                          size: 52,
                          iconSize: 28,
                          accentColor: accent,
                          inactiveColor: const Color(0xFFC8C8CE),
                          disabledColor: const Color(0xFFC7C7CC),
                          highlighted: true,
                          active: true,
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final canNext = widget.controller.canSkipNext;
                        return LiquidGlassRingIconButton(
                          icon: Icons.skip_next,
                          onPressed: canNext
                              ? () => widget.controller.skipNext()
                              : null,
                          size: 44,
                          iconSize: 24,
                          accentColor: accent,
                          inactiveColor: mutedIcon,
                          disabledColor: const Color(0xFFC7C7CC),
                          highlighted: canNext,
                          active: canNext,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _buildProgressSlider(
                accent: accent,
                iconColor: iconColor,
                thumbColor: thumbColor,
                inactiveTrack: inactiveTrack,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildProgressSlider({
    required Color accent,
    required Color iconColor,
    required Color thumbColor,
    required Color inactiveTrack,
  }) {
    final daisy = context.appliedThemePalette == AppThemePalette.daisy;
    final leah = context.appliedThemePalette == AppThemePalette.leah;
    final isIvy = context.appliedThemePalette == AppThemePalette.ivy;

    return StreamBuilder<Duration>(
      stream: widget.controller.audioPlayer.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: widget.controller.audioPlayer.durationStream,
          builder: (context, durSnap) {
            final dur = durSnap.data ?? widget.controller.duration;
            final pos = posSnap.data ?? widget.controller.position;
            final total = dur?.inMilliseconds ?? 0;
            final live = total > 0
                ? (pos.inMilliseconds / total).clamp(0.0, 1.0)
                : 0.0;
            final p = (_dragFraction ?? live).clamp(0.0, 1.0);

            return PlayerAdaptiveSlider(
              value: p,
              appearance: isIvy
                  ? PlayerSliderAppearance.ivy
                  : PlayerSliderAppearance.miniPill,
              activeColor: (daisy || leah) ? iconColor : accent,
              inactiveColor: inactiveTrack,
              thumbColor: thumbColor,
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
                          milliseconds:
                              (v * total).round().clamp(0, total),
                        ),
                      );
                      if (mounted) {
                        setState(() => _dragFraction = null);
                      }
                    },
            );
          },
        );
      },
    );
  }
}
