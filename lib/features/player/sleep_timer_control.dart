import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../audio/sleep_timer_controller.dart';
import '../../theme/app_theme.dart';
import 'sleep_timer_dialog.dart';

/// Dark rose for active Leah NP chrome icons (matches favourite when saved).
const Color _kLeahNpIconActive = Color(0xFF9C3F6E);

/// Inactive Ivy NP icons (off toggles, unfavourited, sleep idle).
const Color _kIvyInactiveIcon = Color(0xFFC8C8CE);

/// Opens the sleep timer dialog from Now Playing.
class SleepTimerControl extends StatelessWidget {
  const SleepTimerControl({
    super.key,
    required this.player,
    required this.iconColor,
    this.iconSize = 28,
  });

  final PlayerController player;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SleepTimerController.instance,
      builder: (context, _) {
        final active = SleepTimerController.instance.isActive;
        final palette = context.appliedThemePalette;
        final leah = palette == AppThemePalette.leah;
        final ivy = palette == AppThemePalette.ivy;
        final color = active && leah
            ? _kLeahNpIconActive
            : active
            ? (ivy ? context.controlAccent : iconColor)
            : ivy
            ? _kIvyInactiveIcon
            : iconColor;
        return IconButton(
          tooltip: active ? 'Sleep timer on' : 'Sleep timer',
          iconSize: iconSize,
          onPressed: () => showSleepTimerDialog(context, player),
          icon: Icon(
            active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
            color: color,
          ),
        );
      },
    );
  }
}
