import 'package:shared_preferences/shared_preferences.dart';

const _kVolumeLevelKey = 'player_volume_level_v1';

abstract final class VolumeSettingsStore {
  static Future<double> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_kVolumeLevelKey) ?? 1.0)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static Future<void> save(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _kVolumeLevelKey,
      volume.clamp(0.0, 1.0).toDouble(),
    );
  }
}
