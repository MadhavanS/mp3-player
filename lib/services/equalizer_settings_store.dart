import 'package:shared_preferences/shared_preferences.dart';

import '../audio/equalizer_preset.dart';

const _kLoudnessEnabledKey = 'audio_loudness_enabled_v1';
const _kLoudnessGainDbKey = 'audio_loudness_gain_db_v1';
const _kEqEnabledKey = 'audio_eq_enabled_v1';
const _kEqPresetKey = 'audio_eq_preset_v1';

abstract final class EqualizerSettingsStore {
  static const bool defaultLoudnessEnabled = false;
  static const double defaultLoudnessGainDb = 3.0;
  static const bool defaultEqEnabled = true;
  static const EqualizerPreset defaultPreset = EqualizerPreset.fullSound;

  static Future<EqualizerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return EqualizerSettings(
      loudnessEnabled: prefs.getBool(_kLoudnessEnabledKey) ?? defaultLoudnessEnabled,
      loudnessGainDb: (prefs.getDouble(_kLoudnessGainDbKey) ?? defaultLoudnessGainDb)
          .clamp(0.0, 8.0)
          .toDouble(),
      eqEnabled: prefs.getBool(_kEqEnabledKey) ?? defaultEqEnabled,
      preset: EqualizerPreset.fromStorage(prefs.getString(_kEqPresetKey)),
    );
  }

  static Future<void> save(EqualizerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoudnessEnabledKey, settings.loudnessEnabled);
    await prefs.setDouble(
      _kLoudnessGainDbKey,
      settings.loudnessGainDb.clamp(0.0, 8.0).toDouble(),
    );
    await prefs.setBool(_kEqEnabledKey, settings.eqEnabled);
    await prefs.setString(_kEqPresetKey, settings.preset.name);
  }
}

final class EqualizerSettings {
  const EqualizerSettings({
    required this.loudnessEnabled,
    required this.loudnessGainDb,
    required this.eqEnabled,
    required this.preset,
  });

  final bool loudnessEnabled;
  final double loudnessGainDb;
  final bool eqEnabled;
  final EqualizerPreset preset;

  EqualizerSettings copyWith({
    bool? loudnessEnabled,
    double? loudnessGainDb,
    bool? eqEnabled,
    EqualizerPreset? preset,
  }) {
    return EqualizerSettings(
      loudnessEnabled: loudnessEnabled ?? this.loudnessEnabled,
      loudnessGainDb: loudnessGainDb ?? this.loudnessGainDb,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      preset: preset ?? this.preset,
    );
  }
}
