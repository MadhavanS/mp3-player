import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track_item.dart';
import 'youtube_api_clients.dart';
import 'youtube_client.dart';

/// Resolved YouTube audio stream for [just_audio].
class YoutubePlaybackSource {
  const YoutubePlaybackSource({
    required this.uri,
    required this.headers,
    this.bitrateBitsPerSec = 0,
    this.totalBytes = 0,
  });

  final Uri uri;
  final Map<String, String> headers;

  /// Nominal stream bitrate from the manifest (for transfer estimates).
  final int bitrateBitsPerSec;

  /// Total stream size when known (0 if unknown).
  final int totalBytes;
}

/// Outcome of [YoutubeSearchService.resolveYoutubePlayback].
class YoutubePlaybackResolveResult {
  const YoutubePlaybackResolveResult.success(this.source)
      : lastError = null;

  const YoutubePlaybackResolveResult.failure(this.lastError) : source = null;

  final YoutubePlaybackSource? source;
  final Object? lastError;

  /// Short message for [ActionPillToast] when [source] is null.
  static String userMessageForFailure(Object? lastError) {
    final text = lastError?.toString().toLowerCase() ?? '';
    if (text.contains('not a bot') || text.contains('sign in to confirm')) {
      return 'YouTube blocked playback on this network — try another video or Wi-Fi';
    }
    if (lastError is TimeoutException) {
      return 'YouTube stream timed out — tap play to retry';
    }
    if (text.contains('unplayable') ||
        text.contains('not available') ||
        text.contains('private') ||
        text.contains('age')) {
      return 'This video cannot be streamed — try another';
    }
    return 'Stream unavailable — tap play to retry';
  }
}

const Duration _searchTimeout = Duration(seconds: 25);
/// Per client-set attempt; we try several sets so total wait can be longer.
const Duration _streamManifestTimeout = Duration(seconds: 18);
const Duration _videoMetadataTimeout = Duration(seconds: 12);
const int _enrichMetadataConcurrency = 6;

/// YouTube search and stream URL resolution via [ytClient].
class YoutubeSearchService {
  YoutubeSearchService._();

  static final YoutubeSearchService instance = YoutubeSearchService._();

  /// Resolves a watch URL to a single [TrackItem], or null if not a video link.
  Future<TrackItem?> trackFromVideoUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      final id = VideoId.parseVideoId(trimmed);
      final video =
          await ytClient.videos.get(id).timeout(_videoMetadataTimeout);
      return TrackItem.fromYoutubeVideo(video);
    } on TimeoutException {
      debugPrint('YouTube video URL timed out: $trimmed');
      return null;
    } catch (e, st) {
      debugPrint('YouTube video URL error: $e\n$st');
      return null;
    }
  }

  /// Loads videos from a playlist URL.
  Future<List<TrackItem>> tracksFromPlaylistUrl(
    String url, {
    int maxVideos = 50,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return [];
    try {
      final playlistId = PlaylistId.parsePlaylistId(trimmed);
      final videos = await ytClient.playlists
          .getVideos(playlistId)
          .take(maxVideos)
          .toList();
      return _enrichTracksMissingTitles(
        videos.map(TrackItem.fromYoutubeVideo).toList(),
      );
    } on TimeoutException {
      debugPrint('YouTube playlist URL timed out: $trimmed');
      return [];
    } catch (e, st) {
      debugPrint('YouTube playlist URL error: $e\n$st');
      return [];
    }
  }

  /// Search YouTube for videos and map them to [TrackItem]s.
  Future<List<TrackItem>> searchVideos(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final results = await ytClient.search
          .search(trimmed)
          .timeout(_searchTimeout);
      return results.map(TrackItem.fromYoutubeVideo).toList();
    } on TimeoutException {
      debugPrint('YouTube search timed out for: $trimmed');
      return [];
    } catch (e, st) {
      debugPrint('YouTube search error: $e\n$st');
      return [];
    }
  }

  /// Lists recent uploads from [channelId] when the song query is empty.
  Future<List<TrackItem>> listChannelUploads(
    String channelId, {
    int maxVideos = 40,
  }) async {
    final id = channelId.trim();
    if (id.isEmpty) return [];

    try {
      final fromPlaylist = await ytClient.channels
          .getUploads(id)
          .take(maxVideos)
          .map(TrackItem.fromYoutubeVideo)
          .toList();
      if (fromPlaylist.isNotEmpty) {
        return _enrichTracksMissingTitles(fromPlaylist);
      }
    } catch (e, st) {
      debugPrint('Channel uploads (playlist) error: $e\n$st');
    }

    try {
      final matches = <Video>[];
      var page = await ytClient.channels
          .getUploadsFromPage(id)
          .timeout(_searchTimeout);
      while (matches.length < maxVideos) {
        matches.addAll(page);
        if (matches.length >= maxVideos) break;
        final next = await page.nextPage();
        if (next == null) break;
        page = next;
      }
      final tracks = matches
          .take(maxVideos)
          .map(TrackItem.fromYoutubeVideo)
          .toList();
      return _enrichTracksMissingTitles(tracks);
    } catch (e, st) {
      debugPrint('Channel uploads error: $e\n$st');
      return [];
    }
  }

  /// Channel upload grids often omit titles; fetch watch metadata when needed.
  Future<List<TrackItem>> _enrichTracksMissingTitles(
    List<TrackItem> tracks,
  ) async {
    if (tracks.isEmpty) return tracks;

    final needsEnrich = tracks.where((t) {
      final id = t.youtubeVideoId?.trim() ?? '';
      if (id.isEmpty) return false;
      final title = t.title.trim();
      return title.isEmpty || title == 'Untitled video';
    }).toList();
    if (needsEnrich.isEmpty) return tracks;

    final enrichedById = <String, TrackItem>{};
    for (var start = 0; start < needsEnrich.length; start += _enrichMetadataConcurrency) {
      final end = (start + _enrichMetadataConcurrency).clamp(0, needsEnrich.length);
      final chunk = needsEnrich.sublist(start, end);
      await Future.wait(
        chunk.map((track) async {
          final videoId = track.youtubeVideoId?.trim() ?? '';
          if (videoId.isEmpty) return;
          try {
            final video = await ytClient.videos
                .get(VideoId(videoId))
                .timeout(_videoMetadataTimeout);
            enrichedById[videoId] = TrackItem.fromYoutubeVideo(video);
          } catch (e, st) {
            debugPrint('YouTube metadata enrich failed for $videoId: $e\n$st');
          }
        }),
      );
    }

    return tracks.map((t) {
      final id = t.youtubeVideoId?.trim() ?? '';
      if (id.isEmpty) return t;
      return enrichedById[id] ?? t;
    }).toList();
  }

  /// Search within a channel: global results filtered by channel, then uploads.
  Future<List<TrackItem>> searchVideosInChannel({
    required String channelId,
    required String query,
    int maxResults = 40,
  }) async {
    final id = channelId.trim();
    final q = query.trim();
    if (id.isEmpty) return [];
    if (q.isEmpty) return listChannelUploads(id, maxVideos: maxResults);

    try {
      final seen = <String>{};
      final out = <TrackItem>[];

      void addVideos(Iterable<Video> videos) {
        for (final v in videos) {
          final vid = v.id.value;
          if (!seen.add(vid)) continue;
          if (v.channelId.value != id) continue;
          out.add(TrackItem.fromYoutubeVideo(v));
          if (out.length >= maxResults) return;
        }
      }

      final global = await ytClient.search.search(q).timeout(_searchTimeout);
      addVideos(global);
      if (out.length >= maxResults) return out;

      final ql = q.toLowerCase();
      var page = await ytClient.channels
          .getUploadsFromPage(id)
          .timeout(_searchTimeout);
      var pagesScanned = 0;
      while (out.length < maxResults && pagesScanned < 4) {
        for (final v in page) {
          if (v.title.toLowerCase().contains(ql)) {
            final vid = v.id.value;
            if (seen.add(vid)) {
              out.add(TrackItem.fromYoutubeVideo(v));
              if (out.length >= maxResults) break;
            }
          }
        }
        pagesScanned++;
        final next = await page.nextPage();
        if (next == null) break;
        page = next;
      }

      return _enrichTracksMissingTitles(out);
    } on TimeoutException {
      debugPrint('Channel-scoped search timed out');
      return [];
    } catch (e, st) {
      debugPrint('Channel-scoped search error: $e\n$st');
      return [];
    }
  }

  /// Autocomplete suggestions while typing.
  Future<List<String>> querySuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      return await ytClient.search
          .getQuerySuggestions(trimmed)
          .timeout(const Duration(seconds: 12));
    } catch (e, st) {
      debugPrint('YouTube suggestions error: $e\n$st');
      return [];
    }
  }

  /// Resolves a direct audio stream URL + headers for [videoId] (URL expires).
  Future<YoutubePlaybackResolveResult> resolveYoutubePlayback(
    String videoId,
  ) async {
    final id = videoId.trim();
    if (id.isEmpty) {
      return const YoutubePlaybackResolveResult.failure(null);
    }

    final clientSets = <List<YoutubeApiClient>>[
      youtubeManifestClients,
      ...youtubeManifestClientFallbacks,
    ];

    Object? lastError;
    for (var i = 0; i < clientSets.length; i++) {
      try {
        final manifest = await ytClient.videos.streams
            .getManifest(id, ytClients: clientSets[i])
            .timeout(_streamManifestTimeout);
        final audioOnly = manifest.audioOnly;
        if (audioOnly.isEmpty) continue;

        final stream = audioOnly.withHighestBitrate();
        return YoutubePlaybackResolveResult.success(
          YoutubePlaybackSource(
            uri: stream.url,
            headers: Map<String, String>.from(youtubeStreamPlaybackHeaders),
            bitrateBitsPerSec: stream.bitrate.bitsPerSecond,
            totalBytes: stream.size.totalBytes,
          ),
        );
      } on TimeoutException catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint(
            'YouTube manifest slow for $id (client set ${i + 1}/'
            '${clientSets.length})',
          );
        }
      } catch (e, st) {
        lastError = e;
        if (kDebugMode) {
          debugPrint('YouTube stream resolve error (set ${i + 1}): $e\n$st');
        }
      }
    }
    if (kDebugMode && lastError != null) {
      debugPrint(
        'YouTube stream manifest failed for $id after ${clientSets.length} '
        'client sets: $lastError',
      );
    }
    return YoutubePlaybackResolveResult.failure(lastError);
  }
}
