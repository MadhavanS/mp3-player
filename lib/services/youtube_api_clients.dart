import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Clients used when resolving stream manifests (tried in order).
///
/// [YoutubeApiClient.androidSdkless] is listed first — youtube_explode recommends
/// it for fewer 403/timeouts vs legacy [YoutubeApiClient.android].
final List<YoutubeApiClient> youtubeManifestClients = [
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.ios,
  YoutubeApiClient.mweb,
];

/// Extra client sets when the first [youtubeManifestClients] fetch fails.
final List<List<YoutubeApiClient>> youtubeManifestClientFallbacks = [
  [YoutubeApiClient.tv],
  [YoutubeApiClient.androidVr, YoutubeApiClient.ios],
  [YoutubeApiClient.mweb],
  [YoutubeApiClient.android],
];

/// User-Agent aligned with Android YouTube clients (must match CDN expectations).
const String youtubeStreamUserAgent =
    'com.google.android.youtube/19.45.37 (Linux; U; Android 12) gzip';

/// Required for ExoPlayer / [AudioSource.uri] on Android (otherwise HTTP 403).
const Map<String, String> youtubeStreamPlaybackHeaders = {
  'User-Agent': youtubeStreamUserAgent,
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
  'Accept': '*/*',
  'Accept-Language': 'en-US,en;q=0.9',
  'Connection': 'keep-alive',
};
