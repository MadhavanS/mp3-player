import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';

import 'metadata_backend_config.dart';

bool _initialized = false;
bool _initFailed = false;

/// True when [MetadataGod.initialize] completed successfully.
bool get metadataGodAvailable => _initialized && !_initFailed;

Future<void> initMetadataGodIfEnabled() async {
  if (!kUseMetadataGod || _initialized || _initFailed) return;
  try {
    await MetadataGod.initialize();
    _initialized = true;
  } catch (e, st) {
    _initFailed = true;
    debugPrint(
      'metadata_god init failed; using audio_metadata_reader only: $e\n$st',
    );
  }
}
