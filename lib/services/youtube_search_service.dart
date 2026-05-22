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

const Duration _searchTimeout = Duration(seconds: 25);
const Duration _streamManifestTimeout = Duration(seconds: 30);

/// YouTube search and stream URL resolution via [ytClient].
class YoutubeSearchService {
  YoutubeSearchService._();

  static final YoutubeSearchService instance = YoutubeSearchService._();

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
      return matches
          .take(maxVideos)
          .map(TrackItem.fromYoutubeVideo)
          .toList();
    } catch (e, st) {
      debugPrint('Channel uploads error: $e\n$st');
      return [];
    }
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

      return out;
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
  Future<YoutubePlaybackSource?> resolveYoutubePlayback(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;

    final clientSets = <List<YoutubeApiClient>>[
      youtubeManifestClients,
      ...youtubeManifestClientFallbacks,
    ];

    for (var i = 0; i < clientSets.length; i++) {
      try {
        final manifest = await ytClient.videos.streams
            .getManifest(id, ytClients: clientSets[i])
            .timeout(_streamManifestTimeout);
        final audioOnly = manifest.audioOnly;
        if (audioOnly.isEmpty) continue;

        final stream = audioOnly.withHighestBitrate();
        return YoutubePlaybackSource(
          uri: stream.url,
          headers: Map<String, String>.from(youtubeStreamPlaybackHeaders),
          bitrateBitsPerSec: stream.bitrate.bitsPerSecond,
          totalBytes: stream.size.totalBytes,
        );
      } on TimeoutException {
        debugPrint('YouTube stream manifest timed out for: $id (set $i)');
      } catch (e, st) {
        debugPrint('YouTube stream resolve error (set $i): $e\n$st');
      }
    }
    return null;
  }
}
