import 'package:flutter/material.dart';

import '../models/track_item.dart';

/// Where to show artwork: mini player, library row, full hero, compact now-playing.
enum TrackArtDisplay { mini, list, full, nowPlaying }

/// Embedded ID3 cover when [TrackItem.albumArtBytes] is set; otherwise gradient [TrackItem.artColors].
class TrackAlbumArt extends StatelessWidget {
  const TrackAlbumArt({
    super.key,
    required this.track,
    required this.display,
  });

  final TrackItem track;
  final TrackArtDisplay display;

  double get _size => switch (display) {
        TrackArtDisplay.mini => 48,
        TrackArtDisplay.list => 56,
        TrackArtDisplay.full => 295,
        TrackArtDisplay.nowPlaying => 220,
      };

  double get _radius => switch (display) {
        TrackArtDisplay.mini => 24,
        TrackArtDisplay.list => 14,
        TrackArtDisplay.full => 34,
        TrackArtDisplay.nowPlaying => 22,
      };

  @override
  Widget build(BuildContext context) {
    final bytes = track.albumArtBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final image = Image.memory(
        bytes,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _gradientDecoration(),
      );

      if (display == TrackArtDisplay.mini) {
        return ClipOval(child: SizedBox(width: _size, height: _size, child: image));
      }
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: _imageShadows(),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: image,
        ),
      );
    }
    return _gradientDecoration();
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

  Widget _gradientDecoration() {
    final gradient = BoxDecoration(
      borderRadius: display == TrackArtDisplay.mini
          ? null
          : BorderRadius.circular(_radius),
      shape: display == TrackArtDisplay.mini ? BoxShape.circle : BoxShape.rectangle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: track.artColors,
      ),
      boxShadow: switch (display) {
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
      },
    );

    return Container(
      width: _size,
      height: _size,
      decoration: gradient,
    );
  }
}
