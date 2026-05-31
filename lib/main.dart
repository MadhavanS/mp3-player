import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'platform/windows_window.dart';
import 'services/metadata_god_init_stub.dart'
    if (dart.library.io) 'services/metadata_god_init_io.dart';
import 'features/youtube/youtube_init_stub.dart'
    if (dart.library.io) 'features/youtube/youtube_init.dart';

bool _justAudioBackgroundInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMetadataGodIfEnabled();
  await initYoutubeFeature();
  await initWindowsWindowOnLaunch();
  if (_mediaNotificationSupported && !_justAudioBackgroundInitialized) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.mp3_player.audio',
      androidNotificationChannelName: 'Now playing',
      androidNotificationChannelDescription:
          'Playback controls while the app is in the background.',
      // Mono drawable required for the compact notification icon on many OEMs.
      androidNotificationIcon: 'drawable/ic_stat_music',
      // Ongoing + stopForegroundOnPause must be paired (audio_service assertion).
      androidNotificationOngoing: true,
      preloadArtwork: true,
      // Large embedded movie-poster art can fail or OOM in the Android notification pipeline.
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    );
    _justAudioBackgroundInitialized = true;
  } else if (_mediaNotificationSupported && _justAudioBackgroundInitialized) {
    debugPrint(
      'main: JustAudioBackground already initialized (hot restart) — skipping',
    );
  }
  runApp(const MadPlayerApp());
}

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
