import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/player_controller.dart';
import '../../audio/sleep_timer_controller.dart';
import '../../theme/app_theme.dart';

Future<void> showSleepTimerDialog(
  BuildContext context,
  PlayerController player,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _SleepTimerDialog(player: player),
  );
}

Future<bool?> _confirmCancelSleepTimer(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel sleep timer?'),
      content: const Text(
        'Playback will continue until you stop it manually.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep timer'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Cancel timer'),
        ),
      ],
    ),
  );
}

/// Preset minute value, or [kCustomDuration] for user-entered duration.
const int kCustomDuration = -1;

class _SleepTimerDialog extends StatefulWidget {
  const _SleepTimerDialog({required this.player});

  final PlayerController player;

  @override
  State<_SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends State<_SleepTimerDialog> {
  static const _minuteOptions = <int>[5, 10, 15, 20, 25, 30, 45, 60];
  static const _maxCustomMinutes = 600;

  final _sleepTimer = SleepTimerController.instance;
  Timer? _tick;

  int _selected = 5;
  bool _endOfSong = false;
  late final TextEditingController _customMinutesController;

  @override
  void initState() {
    super.initState();
    _customMinutesController = TextEditingController(text: '5');
    _sleepTimer.addListener(_onTimerChanged);
    _syncTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sleepTimer.removeListener(_onTimerChanged);
    _customMinutesController.dispose();
    super.dispose();
  }

  void _onTimerChanged() {
    _syncTick();
    if (mounted) setState(() {});
  }

  void _syncTick() {
    if (_sleepTimer.isActive) {
      _tick ??= Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _onPillClose() async {
    final confirmed = await _confirmCancelSleepTimer(context);
    if (confirmed == true) {
      _sleepTimer.cancel();
    }
  }

  bool get _isCustom => _selected == kCustomDuration;

  int? get _resolvedMinutes {
    if (_endOfSong) return null;
    if (!_isCustom) return _selected;
    final parsed = int.tryParse(_customMinutesController.text.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed.clamp(1, _maxCustomMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final accent = context.controlAccent;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final canStart = _endOfSong || _resolvedMinutes != null;
    final timerActive = _sleepTimer.isActive;
    final pillLabel = _sleepTimer.pillLabel;

    final surface = Color.alphaBlend(
      pal.surface.withValues(alpha: 0.94),
      const Color(0xFF1A1D24),
    );

    final fieldDecoration = InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: pal.textMuted.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
      hintStyle: TextStyle(color: pal.textMuted),
    );

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Sleep timer',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: pal.textPrimary,
                    ),
                  ),
                ),
                if (timerActive && pillLabel.isNotEmpty)
                  _SleepTimerActivePill(
                    label: pillLabel,
                    accent: accent,
                    textColor: pal.textPrimary,
                    mutedColor: pal.textSecondary,
                    onClose: _onPillClose,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_endOfSong) ...[
              Text(
                'Stop after',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: pal.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: fieldDecoration.copyWith(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selected,
                    isExpanded: true,
                    dropdownColor: surface,
                    style: TextStyle(color: pal.textPrimary, fontSize: 16),
                    items: [
                      ..._minuteOptions.map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text('$m minutes'),
                        ),
                      ),
                      const DropdownMenuItem(
                        value: kCustomDuration,
                        child: Text('Custom…'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selected = v);
                    },
                  ),
                ),
              ),
              if (_isCustom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customMinutesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: pal.textPrimary),
                  decoration: fieldDecoration.copyWith(
                    labelText: 'Minutes',
                    hintText: 'e.g. 12',
                    helperText: '1–$_maxCustomMinutes minutes',
                    helperStyle: TextStyle(color: pal.textMuted),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Playback will stop when this song ends.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: pal.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _endOfSong = !_endOfSong),
              style: OutlinedButton.styleFrom(
                foregroundColor: pal.textPrimary,
                side: BorderSide(
                  color: _endOfSong
                      ? accent.withValues(alpha: 0.9)
                      : pal.textMuted.withValues(alpha: 0.55),
                  width: _endOfSong ? 1.6 : 1.2,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('End of the song'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.textPrimary,
                      side: BorderSide(
                        color: pal.textMuted.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canStart ? () => _start(context) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: onAccent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.35),
                      disabledForegroundColor: onAccent.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(timerActive ? 'Replace' : 'Start'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _start(BuildContext context) {
    _sleepTimer.cancel();
    widget.player.setStopAtTrackEndForSleepTimer(false);

    if (_endOfSong) {
      _sleepTimer.startEndOfSong(widget.player);
    } else {
      final minutes = _resolvedMinutes;
      if (minutes == null) return;
      _sleepTimer.startDuration(widget.player, Duration(minutes: minutes));
    }
    Navigator.pop(context);
  }
}

class _SleepTimerActivePill extends StatelessWidget {
  const _SleepTimerActivePill({
    required this.label,
    required this.accent,
    required this.textColor,
    required this.mutedColor,
    required this.onClose,
  });

  final String label;
  final Color accent;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.14),
      shape: StadiumBorder(
        side: BorderSide(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onClose,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: mutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
