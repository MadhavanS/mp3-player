import 'package:path/path.dart' as p;

/// Experiment branch: native tag reads via [metadata_god] (Rust lofty), with Dart fallback.
///
/// Console noise at startup (`lofty: frame header uses a reserved layer`) is a
/// harmless MP3 frame probe warning while scanning tags; it is not a Flutter bug.
/// Non-.mp3 files use the Dart reader only ([pathUsesMetadataGodReader]).
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

/// [metadata_god] / lofty probes MPEG frame headers for MP3 only.
bool pathUsesMetadataGodReader(String path) {
  return p.extension(path).toLowerCase() == '.mp3';
}
