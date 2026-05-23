/// Experiment branch: native tag reads via [metadata_god] (Rust), with Dart fallback.
///
/// Override at build time: `--dart-define=USE_METADATA_GOD=false`
const bool kUseMetadataGod = bool.fromEnvironment(
  'USE_METADATA_GOD',
  defaultValue: true,
);

/// Log per-read timing when experimenting (visible in `flutter run` console).
const bool kMetadataReadTimingLogs = bool.fromEnvironment(
  'METADATA_READ_TIMING',
  defaultValue: false,
);
