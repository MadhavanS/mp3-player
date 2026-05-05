import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/track_item.dart';

/// Picks a readable title color from embedded cover art (or [TrackItem.artColors]).
Future<Color> resolveNowPlayingTitleColor({
  required TrackItem track,
  required bool darkFrostedBackground,
}) async {
  final bytes = track.albumArtBytes;
  if (bytes != null && bytes.isNotEmpty) {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(112, 112),
        maximumColorCount: 16,
      );
      final picked = _pickSwatch(palette);
      if (picked != null) {
        return tuneTitleColorForFrostedCard(picked, darkFrostedBackground);
      }
    } catch (_) {}
  }
  return tuneTitleColorForFrostedCard(
    track.artColors.isNotEmpty
        ? track.artColors.first
        : const Color(0xFFE8EAED),
    darkFrostedBackground,
  );
}

/// Synchronous hint until [resolveNowPlayingTitleColor] completes (uses path gradient).
Color provisionalNowPlayingTitleColor({
  required TrackItem track,
  required bool darkFrostedBackground,
}) {
  final base = track.artColors.isNotEmpty
      ? track.artColors.first
      : const Color(0xFFE8EAED);
  return tuneTitleColorForFrostedCard(base, darkFrostedBackground);
}

Color? _pickSwatch(PaletteGenerator g) {
  return g.vibrantColor?.color ??
      g.lightVibrantColor?.color ??
      g.darkVibrantColor?.color ??
      g.dominantColor?.color;
}

/// Keeps album-art character while staying legible on frost glass.
Color tuneTitleColorForFrostedCard(Color c, bool darkBackground) {
  final hsl = HSLColor.fromColor(c);
  if (darkBackground) {
    var l = hsl.lightness;
    var s = hsl.saturation;
    if (l < 0.46) {
      l = lerpDouble(l, 0.62, 0.72)!;
    }
    l = l.clamp(0.42, 0.92);
    if (s < 0.45) {
      s = lerpDouble(s, 0.78, 0.55)!;
    }
    s = s.clamp(0.38, 1.0);
    return hsl.withLightness(l).withSaturation(s).toColor();
  }
  var l = hsl.lightness;
  if (l > 0.58) {
    l = lerpDouble(l, 0.28, 0.55)!;
  }
  l = l.clamp(0.18, 0.58);
  final s = hsl.saturation.clamp(0.25, 0.95);
  return hsl.withLightness(l).withSaturation(s).toColor();
}
