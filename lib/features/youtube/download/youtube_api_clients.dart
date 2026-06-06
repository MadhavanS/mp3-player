import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Clients tried in order when resolving a stream manifest.
///
/// Prefer stable mobile/TV clients before [YoutubeApiClient.androidVr], which
/// often 403s on certain videos/regions.
final kYoutubeManifestClientPriority = <YoutubeApiClient>[
  YoutubeApiClient.android,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
  YoutubeApiClient.mediaConnect,
  YoutubeApiClient.androidVr,
];

/// Default UA when a client payload omits [userAgent] (e.g. TV).
const kYoutubeStreamFallbackUserAgent =
    'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

/// HTTP headers ExoPlayer/AVPlayer must send when fetching a googlevideo URL.
Map<String, String> youtubeStreamRequestHeaders(YoutubeApiClient client) {
  final payloadClient = client.payload['context']?['client'];
  final userAgent = payloadClient?['userAgent'] as String?;
  final headers = <String, String>{
    'User-Agent': (userAgent != null && userAgent.trim().isNotEmpty)
        ? userAgent.trim()
        : kYoutubeStreamFallbackUserAgent,
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };
  for (final entry in client.headers.entries) {
    headers[entry.key.toString()] = entry.value.toString();
  }
  return headers;
}
