import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Matches [TrackAlbumArt] / Android widget placeholder branching.
enum TrackArtPlaceholderStyle {
  gradient,
  silver,
  daisy,
  ivy,
}

extension TrackArtPlaceholderStyleWire on TrackArtPlaceholderStyle {
  String get wireName => switch (this) {
        TrackArtPlaceholderStyle.daisy => 'daisy',
        TrackArtPlaceholderStyle.silver => 'silver',
        TrackArtPlaceholderStyle.ivy => 'ivy',
        TrackArtPlaceholderStyle.gradient => 'gradient',
      };
}

TrackArtPlaceholderStyle trackArtPlaceholderStyleFor(AppThemePalette palette) {
  return switch (palette) {
    AppThemePalette.daisy => TrackArtPlaceholderStyle.daisy,
    AppThemePalette.silver => TrackArtPlaceholderStyle.silver,
    AppThemePalette.ivy => TrackArtPlaceholderStyle.ivy,
    _ => TrackArtPlaceholderStyle.gradient,
  };
}

/// Rasterizes a square PNG for media notifications / platform decoders.
Future<Uint8List?> rasterizeTrackArtPlaceholder({
  required TrackArtPlaceholderStyle style,
  required List<Color> artColors,
  int size = 512,
}) async {
  final s = size.clamp(64, 512);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, s.toDouble(), s.toDouble());

  late List<Color> colors;
  late Alignment begin;
  late Alignment end;
  switch (style) {
    case TrackArtPlaceholderStyle.daisy:
      colors = const [Color(0xFFE5D8C4), Color(0xFFD3C0A7)];
      begin = Alignment.topCenter;
      end = Alignment.bottomCenter;
    case TrackArtPlaceholderStyle.silver:
      colors = const [Color(0xFFC4C0BA), Color(0xFFB8B4AE)];
      begin = Alignment.topLeft;
      end = Alignment.bottomRight;
    case TrackArtPlaceholderStyle.ivy:
      colors = [
        const Color(0xFFF2F2F5),
        const Color(0xFFD8D8DC),
      ];
      begin = Alignment.topLeft;
      end = Alignment.bottomRight;
    case TrackArtPlaceholderStyle.gradient:
      final c0 = artColors.isNotEmpty
          ? artColors.first
          : const Color(0xFFA18CD1);
      final c1 = artColors.length > 1 ? artColors[1] : c0;
      colors = [c0, c1];
      begin = Alignment.topLeft;
      end = Alignment.bottomRight;
  }

  final fill = Paint()
    ..shader = LinearGradient(
      begin: begin,
      end: end,
      colors: colors,
    ).createShader(rect);
  canvas.drawRect(rect, fill);

  switch (style) {
    case TrackArtPlaceholderStyle.daisy:
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s / 128.0).clamp(2.0, 6.0)
        ..color = const Color(0xFF2B2117).withValues(alpha: 0.9);
      canvas.drawRect(rect.deflate(stroke.strokeWidth / 2), stroke);
    case TrackArtPlaceholderStyle.silver:
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s / 90.0).clamp(3.0, 8.0)
        ..color = const Color(0xFF0A0A0A);
      canvas.drawRect(rect.deflate(stroke.strokeWidth / 2), stroke);
    case TrackArtPlaceholderStyle.ivy:
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s / 128.0).clamp(2.0, 6.0)
        ..color = Colors.white.withValues(alpha: 0.72);
      canvas.drawRect(rect.deflate(stroke.strokeWidth / 2), stroke);
    case TrackArtPlaceholderStyle.gradient:
      break;
  }

  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(s, s);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = byteData?.buffer.asUint8List();
    if (out == null || out.isEmpty) return null;
    return out;
  } finally {
    image?.dispose();
  }
}
