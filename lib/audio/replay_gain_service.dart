import 'package:flutter/foundation.dart';

import '../models/track_item.dart';
import '../services/replay_gain_settings_store.dart';
import 'equalizer_service.dart';
import 'replay_gain.dart';

/// Applies per-track ReplayGain via the shared [AndroidLoudnessEnhancer].
class ReplayGainService {
  ReplayGainService(this._equalizerService);

  final EqualizerService _equalizerService;

  ReplayGainSettings _settings = const ReplayGainSettings(
    mode: ReplayGainSettingsStore.defaultMode,
    preAmpWithTagsDb: ReplayGainSettingsStore.defaultPreAmpWithTagsDb,
    preAmpWithoutTagsDb: ReplayGainSettingsStore.defaultPreAmpWithoutTagsDb,
  );

  bool _initialized = false;
  double _lastAppliedDb = 0;

  bool get isInitialized => _initialized;
  ReplayGainSettings get settings => _settings;
  double get lastAppliedDb => _lastAppliedDb;

  Future<void> init() async {
    _settings = await ReplayGainSettingsStore.load();
    _initialized = true;
    debugPrint('[RG] initialized mode=${_settings.mode.name}');
  }

  Future<void> setMode(ReplayGainMode mode) async {
    _settings = _settings.copyWith(mode: mode);
    await ReplayGainSettingsStore.save(_settings);
  }

  Future<void> setPreAmpWithTagsDb(double db) async {
    _settings = _settings.copyWith(
      preAmpWithTagsDb: db.clamp(-12.0, 12.0).toDouble(),
    );
    await ReplayGainSettingsStore.save(_settings);
  }

  Future<void> setPreAmpWithoutTagsDb(double db) async {
    _settings = _settings.copyWith(
      preAmpWithoutTagsDb: db.clamp(-12.0, 12.0).toDouble(),
    );
    await ReplayGainSettingsStore.save(_settings);
  }

  double resolveOutputDb({
    required TrackItem? track,
    required bool albumPlaybackContext,
  }) {
    if (track == null) {
      return _settings.preAmpWithoutTagsDb;
    }
    return resolveReplayGainOutputDb(
      mode: _settings.mode,
      tags: track.replayGainAdjustment,
      albumPlaybackContext: albumPlaybackContext,
      preAmpWithTagsDb: _settings.preAmpWithTagsDb,
      preAmpWithoutTagsDb: _settings.preAmpWithoutTagsDb,
    );
  }

  Future<void> applyForTrack({
    required TrackItem? track,
    required bool albumPlaybackContext,
  }) async {
    if (!_initialized || !_equalizerService.isSupported) return;
    final outputDb = resolveOutputDb(
      track: track,
      albumPlaybackContext: albumPlaybackContext,
    );
    _lastAppliedDb = outputDb;
    await _equalizerService.applyWithReplayGainDb(outputDb);
    debugPrint(
      '[RG] applied ${outputDb.toStringAsFixed(2)} dB '
      'mode=${_settings.mode.name} '
      'track=${track?.replayGainTrackDb} album=${track?.replayGainAlbumDb} '
      'albumCtx=$albumPlaybackContext',
    );
  }
}
