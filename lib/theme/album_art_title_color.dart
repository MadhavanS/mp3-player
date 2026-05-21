import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// Adjusts a base color (usually theme accent) to stay legible on frost glass.
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
