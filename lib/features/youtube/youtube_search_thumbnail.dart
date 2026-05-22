import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Thumbnail for Online search and download queue lists.
class YoutubeSearchThumbnail extends StatelessWidget {
  const YoutubeSearchThumbnail({this.url, this.size = 56, super.key});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    if (u == null || u.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: context.palette.onScaffold.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded, color: context.palette.textMuted),
      );
    }
    return Image.network(
      u,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: context.palette.onScaffold.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded, color: context.palette.textMuted),
      ),
    );
  }
}
