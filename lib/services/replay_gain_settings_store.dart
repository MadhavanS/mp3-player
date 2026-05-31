import 'package:shared_preferences/shared_preferences.dart';

import '../audio/replay_gain.dart';

const _kModeKey = 'replay_gain_mode_v1';
const _kPreAmpWithKey = 'replay_gain_pre_amp_with_v1';
const _kPreAmpWithoutKey = 'replay_gain_pre_amp_without_v1';

class ReplayGainSettings {
  const ReplayGainSettings({
    required this.mode,
    required this.preAmpWithTagsDb,
    required this.preAmpWithoutTagsDb,
  });

  final ReplayGainMode mode;
  final double preAmpWithTagsDb;
  final double preAmpWithoutTagsDb;

  ReplayGainSettings copyWith({
    ReplayGainMode? mode,
    double? preAmpWithTagsDb,
    double? preAmpWithoutTagsDb,
  }) {
    return ReplayGainSettings(
      mode: mode ?? this.mode,
      preAmpWithTagsDb: preAmpWithTagsDb ?? this.preAmpWithTagsDb,
      preAmpWithoutTagsDb: preAmpWithoutTagsDb ?? this.preAmpWithoutTagsDb,
    );
  }
}

abstract final class ReplayGainSettingsStore {
  static const ReplayGainMode defaultMode = ReplayGainMode.track;
  static const double defaultPreAmpWithTagsDb = 0;
  static const double defaultPreAmpWithoutTagsDb = 0;

  static Future<ReplayGainSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReplayGainSettings(
      mode: ReplayGainMode.fromStorage(prefs.getString(_kModeKey)),
      preAmpWithTagsDb: (prefs.getDouble(_kPreAmpWithKey) ?? defaultPreAmpWithTagsDb)
          .clamp(-12.0, 12.0)
          .toDouble(),
      preAmpWithoutTagsDb:
          (prefs.getDouble(_kPreAmpWithoutKey) ?? defaultPreAmpWithoutTagsDb)
              .clamp(-12.0, 12.0)
              .toDouble(),
    );
  }

  static Future<void> save(ReplayGainSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, settings.mode.name);
    await prefs.setDouble(
      _kPreAmpWithKey,
      settings.preAmpWithTagsDb.clamp(-12.0, 12.0).toDouble(),
    );
    await prefs.setDouble(
      _kPreAmpWithoutKey,
      settings.preAmpWithoutTagsDb.clamp(-12.0, 12.0).toDouble(),
    );
  }
}
