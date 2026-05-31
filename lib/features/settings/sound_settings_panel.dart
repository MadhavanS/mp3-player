import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/equalizer_preset.dart';
import '../../audio/player_controller.dart';
import '../../audio/replay_gain.dart';
import '../../theme/app_theme.dart';

class SoundSettingsPanel extends StatefulWidget {
  const SoundSettingsPanel({super.key});

  @override
  State<SoundSettingsPanel> createState() => _SoundSettingsPanelState();
}

class _SoundSettingsPanelState extends State<SoundSettingsPanel> {
  Future<void> _apply(Future<void> Function() action) async {
    await action();
    if (mounted) setState(() {});
  }

  Future<void> _applyAndSyncPlayback(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    final player = PlayerController.of(context);
    await player.syncPlaybackEnhancements();
    if (mounted) setState(() {});
  }

  Widget _materialTile({required Widget child}) {
    return Material(color: Colors.transparent, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);
    final eq = player.equalizerService;
    final rg = player.replayGainService;

    if (!eq.isSupported) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Playback enhancement is available on Android. '
            'On this platform, volume is controlled by the system and the in-app slider.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary.withValues(alpha: 0.95),
            ),
          ),
        ],
      );
    }

    final eqSettings = eq.settings;
    final rgSettings = rg.settings;
    final current = player.currentTrack;
    final currentRgDb = rg.resolveOutputDb(
      track: current,
      albumPlaybackContext: false,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'ReplayGain normalizes loudness using embedded track/album tags. '
          'Extra loudness boost and EQ stack on top.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ReplayGain',
          style: theme.textTheme.titleSmall?.copyWith(
            color: pal.onScaffold,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...ReplayGainMode.values.map((mode) {
          final selected = rgSettings.mode == mode;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected
                      ? context.controlAccent.withValues(alpha: 0.65)
                      : pal.dividerOnHero,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  mode.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: pal.onScaffold,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  mode.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.92),
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: context.controlAccent)
                    : null,
                onTap: () => unawaited(
                  _applyAndSyncPlayback(() => rg.setMode(mode)),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          'Pre-amp when tags present (${rgSettings.preAmpWithTagsDb.toStringAsFixed(1)} dB)',
          style: theme.textTheme.bodySmall?.copyWith(color: pal.textMuted),
        ),
        Slider(
          min: -6,
          max: 6,
          divisions: 24,
          value: rgSettings.preAmpWithTagsDb,
          label: '${rgSettings.preAmpWithTagsDb.toStringAsFixed(1)} dB',
          onChanged: (value) => unawaited(
            _applyAndSyncPlayback(() => rg.setPreAmpWithTagsDb(value)),
          ),
        ),
        Text(
          'Pre-amp when tags missing (${rgSettings.preAmpWithoutTagsDb.toStringAsFixed(1)} dB)',
          style: theme.textTheme.bodySmall?.copyWith(color: pal.textMuted),
        ),
        Slider(
          min: -6,
          max: 6,
          divisions: 24,
          value: rgSettings.preAmpWithoutTagsDb,
          label: '${rgSettings.preAmpWithoutTagsDb.toStringAsFixed(1)} dB',
          onChanged: (value) => unawaited(
            _applyAndSyncPlayback(() => rg.setPreAmpWithoutTagsDb(value)),
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 4),
          Text(
            'Now playing: track ${current.replayGainTrackDb?.toStringAsFixed(1) ?? '—'} dB, '
            'album ${current.replayGainAlbumDb?.toStringAsFixed(1) ?? '—'} dB '
            '→ applied ${currentRgDb.toStringAsFixed(1)} dB',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.92),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _materialTile(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Loudness boost',
              style: theme.textTheme.titleSmall?.copyWith(
                color: pal.onScaffold,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Extra lift on top of ReplayGain (does not change your volume slider).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted.withValues(alpha: 0.95),
              ),
            ),
            value: eqSettings.loudnessEnabled,
            onChanged: (value) => unawaited(
              _applyAndSyncPlayback(() => eq.setLoudnessEnabled(value)),
            ),
          ),
        ),
        if (eqSettings.loudnessEnabled) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 8,
                    divisions: 16,
                    label: '${eqSettings.loudnessGainDb.toStringAsFixed(1)} dB',
                    value: eqSettings.loudnessGainDb,
                    onChanged: (value) => unawaited(
                      _applyAndSyncPlayback(() => eq.setLoudnessGainDb(value)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${eqSettings.loudnessGainDb.toStringAsFixed(1)} dB',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: pal.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        _materialTile(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Equalizer',
              style: theme.textTheme.titleSmall?.copyWith(
                color: pal.onScaffold,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Preset shaping for bass and treble.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted.withValues(alpha: 0.95),
              ),
            ),
            value: eqSettings.eqEnabled,
            onChanged: (value) => unawaited(
              _apply(() => eq.setEqEnabled(value)),
            ),
          ),
        ),
        if (eqSettings.eqEnabled) ...[
          const SizedBox(height: 8),
          Text(
            'Preset',
            style: theme.textTheme.titleSmall?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...EqualizerPreset.values.map((preset) {
            final selected = eqSettings.preset == preset;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected
                        ? context.controlAccent.withValues(alpha: 0.65)
                        : pal.dividerOnHero,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(
                    preset.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: pal.onScaffold,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    preset.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: pal.textMuted.withValues(alpha: 0.92),
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check_rounded, color: context.controlAccent)
                      : null,
                  onTap: () => unawaited(
                    _apply(() => eq.setPreset(preset)),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
