import 'package:flutter/material.dart';

import '../models/track_item.dart';
import '../theme/app_theme.dart';

/// Where to show artwork: mini player, library row, full hero, compact now-playing.
enum TrackArtDisplay { mini, list, full, nowPlaying }

/// Embedded ID3 cover when [TrackItem.albumArtBytes] is set; otherwise gradient [TrackItem.artColors].
class TrackAlbumArt extends StatelessWidget {
  const TrackAlbumArt({
    super.key,
    required this.track,
    required this.display,
    this.showShadow = true,
    this.cornerRadius,
  });

  final TrackItem track;
  final TrackArtDisplay display;

  /// When false, skips drop shadow on the artwork (e.g. when wrapped in an outer card).
  final bool showShadow;

  /// When non-null, overrides the default corner radius for this [display] (use `0` for square art).
  final double? cornerRadius;

  double get _size => switch (display) {
    TrackArtDisplay.mini => 48,
    TrackArtDisplay.list => 56,
    TrackArtDisplay.full => 295,
    TrackArtDisplay.nowPlaying => 248,
  };

  double get _radius => switch (display) {
    TrackArtDisplay.mini => 24,
    TrackArtDisplay.list => 14,
    TrackArtDisplay.full => 34,
    TrackArtDisplay.nowPlaying => 22,
  };

  double _radiusFor(BuildContext context) {
    if (!context.usesPlayerChrome) return _radius;
    return switch (display) {
      TrackArtDisplay.mini => _radius,
      TrackArtDisplay.list => 18,
      TrackArtDisplay.full => 38,
      TrackArtDisplay.nowPlaying => 28,
    };
  }

  double _effectiveRadius(BuildContext context) {
    if (display == TrackArtDisplay.mini) return _radiusFor(context);
    return cornerRadius ?? _radiusFor(context);
  }

  Widget _noArtPlaceholder(BuildContext context) {
    if (context.appliedThemePalette == AppThemePalette.silver) {
      return _silverPlaceholderDecoration(context);
    }
    return _gradientDecoration(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = _effectiveRadius(context);
    final bytes = track.albumArtBytes;
    if (bytes == null || bytes.isEmpty) {
      return _noArtPlaceholder(context);
    }

    final image = Image.memory(
      bytes,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _noArtPlaceholder(context),
    );

    if (display == TrackArtDisplay.mini) {
      return ClipOval(
        child: SizedBox(width: _size, height: _size, child: image),
      );
    }
    final br = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: showShadow ? _imageShadows() : const <BoxShadow>[],
      ),
      child: ClipRRect(borderRadius: br, child: image),
    );
  }

  List<BoxShadow> _imageShadows() => switch (display) {
    TrackArtDisplay.full => [
      BoxShadow(
        color: Colors.black.withOpacity(0.12),
        blurRadius: 28,
        offset: const Offset(0, 18),
      ),
    ],
    TrackArtDisplay.nowPlaying => [
      BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
    _ => const [],
  };

  /// Silver: flat neutral tile instead of [track.artColors] gradient when there is no cover.
  Widget _silverPlaceholderDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final brNonMini = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    const fill = Color(0xFFB8B4AE);
    const fillTop = Color(0xFFC4C0BA);
    const placeholderBorder = Border.fromBorderSide(
      BorderSide(color: Color(0xFF0A0A0A), width: 1.75),
    );
    final deco = BoxDecoration(
      border: placeholderBorder,
      borderRadius: display == TrackArtDisplay.mini
          ? null
          : brNonMini,
      shape: display == TrackArtDisplay.mini
          ? BoxShape.circle
          : BoxShape.rectangle,
      gradient: display == TrackArtDisplay.mini
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [fillTop, fill],
            ),
      color: display == TrackArtDisplay.mini ? fill : null,
      boxShadow: showShadow
          ? switch (display) {
              TrackArtDisplay.mini => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              TrackArtDisplay.list => const [],
              TrackArtDisplay.full => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              TrackArtDisplay.nowPlaying => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
            }
          : const <BoxShadow>[],
    );

    return Container(width: _size, height: _size, decoration: deco);
  }

  Widget _gradientDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final brNonMini = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    final gradient = BoxDecoration(
      borderRadius: display == TrackArtDisplay.mini
          ? null
          : brNonMini,
      shape: display == TrackArtDisplay.mini
          ? BoxShape.circle
          : BoxShape.rectangle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: track.artColors,
      ),
      boxShadow: showShadow
          ? switch (display) {
              TrackArtDisplay.mini => [
                BoxShadow(
                  color: track.artColors.first.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              TrackArtDisplay.list => const [],
              TrackArtDisplay.full => [
                BoxShadow(
                  color: track.artColors.last.withOpacity(0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
              TrackArtDisplay.nowPlaying => [
                BoxShadow(
                  color: track.artColors.last.withOpacity(0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            }
          : const <BoxShadow>[],
    );

    return Container(width: _size, height: _size, decoration: gradient);
  }
}
