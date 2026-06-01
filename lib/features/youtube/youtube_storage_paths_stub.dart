Future<String> defaultYoutubeAudioStorageDirectoryPath() async => '';

Future<String> youtubeAudioStorageDirectoryPath() async => '';

Future<bool> usesDefaultYoutubeAudioStoragePath() async => true;

Future<String> ensureYoutubeAudioStorageDirectory() async => '';

Future<bool> isYoutubeStoragePathInAppSandbox(String path) async => true;

Future<bool> probeYoutubeStorageDirectoryWritable(String path) async => false;
