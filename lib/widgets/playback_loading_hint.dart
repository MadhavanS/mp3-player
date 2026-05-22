import 'package:flutter/material.dart';

/// Compact loading row for playback prepare/buffer states.
class PlaybackLoadingHint extends StatelessWidget {
  const PlaybackLoadingHint({
    super.key,
    required this.label,
    this.color,
    this.spinnerSize = 16,
    this.fontSize = 13,
    this.center = true,
  });

  final String label;
  final Color? color;
  final double spinnerSize;
  final double fontSize;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: spinnerSize,
          height: spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: fg,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (!center) return row;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [row],
    );
  }
}
