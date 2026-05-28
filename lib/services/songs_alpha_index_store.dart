import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted toggle for Songs-tab alphabet side index (A-Z quick jump).
///
/// The index is gated behind [loadExperimentEnabled] (Settings → Experiments).
class SongsAlphaIndexStore {
  SongsAlphaIndexStore._();

  static const _prefsKey = 'songs_alpha_index_enabled_v1';
  static const _experimentPrefsKey = 'songs_alpha_index_experiment_v1';
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// When false (default), the alphabet bar and its menu entry stay hidden.
  static Future<bool> loadExperimentEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_experimentPrefsKey) ?? false;
  }

  static Future<void> saveExperimentEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_experimentPrefsKey, enabled);
    if (!enabled) {
      await prefs.setBool(_prefsKey, false);
    }
    revision.value++;
  }

  static Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    revision.value++;
  }
}
