/// Returns error message string on failure or when unsupported; null on success.
Future<String?> deleteMusicFileOrError(String path) async =>
    'Deleting audio files is not supported on this platform.';
