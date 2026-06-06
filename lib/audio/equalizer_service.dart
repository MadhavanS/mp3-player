import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../services/equalizer_settings_store.dart';
import 'equalizer_preset.dart';

/// Android playback enhancement via [just_audio]'s built-in effects.
///
/// Effect instances are process-static so they stay attached to the shared
/// native [AudioPlayer] across hot restart.
class EqualizerService {
  static const bool enabledByFlag = bool.fromEnvironment(
    'EQUALIZER_ENABLED',
    defaultValue: true,
  );

  static AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  static AndroidEqualizer _equalizer = AndroidEqualizer();

  /// After [AudioPlayer.dispose], effect instances must be recreated before the
  /// next player — otherwise just_audio asserts `_player == null`.
  static void resetSharedEffectsForNativePlayerRecreate() {
    if (!enabledByFlag) return;
    _loudnessEnhancer = AndroidLoudnessEnhancer();
    _equalizer = AndroidEqualizer();
  }

  static AudioPipeline get sharedPipeline => AudioPipeline(
        androidAudioEffects: [_loudnessEnhancer, _equalizer],
      );

  bool _initialized = false;
  double _replayGainDb = 0;
  EqualizerSettings _settings = const EqualizerSettings(
    loudnessEnabled: EqualizerSettingsStore.defaultLoudnessEnabled,
    loudnessGainDb: EqualizerSettingsStore.defaultLoudnessGainDb,
    eqEnabled: EqualizerSettingsStore.defaultEqEnabled,
    preset: EqualizerSettingsStore.defaultPreset,
  );

  bool get isInitialized => _initialized;
  bool get isFeatureEnabled => enabledByFlag;
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  EqualizerSettings get settings => _settings;

  AndroidLoudnessEnhancer get loudnessEnhancer => _loudnessEnhancer;
  AndroidEqualizer get equalizer => _equalizer;

  Future<void> init() async {
    if (!enabledByFlag) {
      debugPrint('[EQ] disabled by feature flag');
      return;
    }
    if (!isSupported) {
      debugPrint('[EQ] unsupported on this platform');
      return;
    }
    _settings = await EqualizerSettingsStore.load();
    _initialized = true;
    await _applySettings(_settings);
    debugPrint(
      '[EQ] initialized loudness=${_settings.loudnessEnabled} '
      '${_settings.loudnessGainDb.toStringAsFixed(1)} dB '
      'eq=${_settings.eqEnabled} preset=${_settings.preset.name}',
    );
  }

  Future<void> reattachToSession(int? sessionId) async {
    if (!_initialized || !enabledByFlag || !isSupported) return;
    await _applySettings(_settings);
    debugPrint(
      '[EQ] re-applied rg=${_replayGainDb.toStringAsFixed(2)} dB '
      'loudness=${_settings.loudnessEnabled} '
      '${_settings.loudnessGainDb.toStringAsFixed(1)} dB '
      'eq=${_settings.eqEnabled} preset=${_settings.preset.name} '
      'sessionId=$sessionId',
    );
  }

  Future<void> applyWithReplayGainDb(double replayGainDb) async {
    _replayGainDb = replayGainDb;
    await _applyLoudness();
  }

  Future<void> setLoudnessEnabled(bool enabled) async {
    _settings = _settings.copyWith(loudnessEnabled: enabled);
    await _applyLoudness();
    await EqualizerSettingsStore.save(_settings);
  }

  Future<void> setLoudnessGainDb(double gainDb) async {
    final next = gainDb.clamp(0.0, 8.0).toDouble();
    _settings = _settings.copyWith(loudnessGainDb: next);
    await _applyLoudness();
    await EqualizerSettingsStore.save(_settings);
  }

  Future<void> setEqEnabled(bool enabled) async {
    _settings = _settings.copyWith(eqEnabled: enabled);
    await _applyEqualizer();
    await EqualizerSettingsStore.save(_settings);
  }

  Future<void> setPreset(EqualizerPreset preset) async {
    _settings = _settings.copyWith(preset: preset);
    await _applyEqualizer();
    await EqualizerSettingsStore.save(_settings);
  }

  Future<void> _applySettings(EqualizerSettings settings) async {
    _settings = settings;
    await _applyLoudness();
    await _applyEqualizer();
  }

  Future<void> _applyLoudness() async {
    if (!isSupported) return;
    final userDb = _settings.loudnessEnabled ? _settings.loudnessGainDb : 0.0;
    final totalDb = _replayGainDb + userDb;
    await _loudnessEnhancer.setTargetGain(totalDb);
    await _loudnessEnhancer.setEnabled(
      _settings.loudnessEnabled || totalDb.abs() > 0.001,
    );
  }

  Future<void> _applyEqualizer() async {
    if (!isSupported) return;
    if (!_settings.eqEnabled || _settings.preset == EqualizerPreset.flat) {
      await _equalizer.setEnabled(false);
      return;
    }

    await _equalizer.setEnabled(true);
    try {
      final parameters = await _equalizer.parameters;
      final gains = equalizerGainsForPreset(
        _settings.preset,
        parameters.bands.length,
      );
      for (var i = 0; i < parameters.bands.length; i++) {
        final gain = gains[i].clamp(
          parameters.minDecibels,
          parameters.maxDecibels,
        );
        await parameters.bands[i].setGain(gain);
      }
    } catch (e, st) {
      debugPrint('[EQ] apply equalizer: $e\n$st');
    }
  }
}
