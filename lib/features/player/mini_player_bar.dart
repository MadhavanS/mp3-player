import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../widgets/glass_mini_player.dart';

/// Shell entry for the minimized player above the bottom nav.
///
/// Visuals and behavior live in [GlassMiniPlayer].
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final PlayerController controller;
  final VoidCallback onTap;

  /// Matches full-screen Now Playing top radius for one continuous chrome curve.
  static const double topSheetRadius = 28;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.currentTrack == null) {
          return const SizedBox.shrink();
        }
        return GlassMiniPlayer(
          controller: controller,
          onTap: onTap,
          topCornerRadius: topSheetRadius,
        );
      },
    );
  }
}
