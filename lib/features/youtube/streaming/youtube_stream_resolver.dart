import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../download/youtube_manifest_resolver.dart';
import '../download/youtube_stream_format.dart';

/// Resolved HTTP stream metadata for live YouTube playback (phase 1+).
class YoutubeStreamInfo {
  const YoutubeStreamInfo({
    required this.videoId,
    required this.streamUrl,
    required this.mimeType,
    required this.bitrateKbps,
    required this.contentLength,
    required this.resolvedAtMs,
  });

  final String videoId;
  final String streamUrl;
  final String mimeType;
  final int bitrateKbps;
  final int contentLength;
  final int resolvedAtMs;
}

/// Manifest + URL resolution with client rotation (streaming playback).
///
/// Phase 1: wraps [YoutubeManifestResolver]; URI playback + retry wiring come next.
class YoutubeStreamResolver {
  YoutubeStreamResolver._();

  static final instance = YoutubeStreamResolver._();

  static const _manifestTtlMs = 20 * 60 * 1000;

  final _cache = <String, YoutubeStreamInfo>{};
  final _resolvedAt = <String, int>{};

  static final _clientPriority = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
  ];

  Future<YoutubeStreamInfo?> resolve(
    String videoId, {
    bool forceRefresh = false,
  }) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;

    if (!forceRefresh) {
      final cached = _getCachedIfValid(id);
      if (cached != null) return cached;
    }

    for (final client in _clientPriority) {
      try {
        final info = await _resolveWithClient(id, client);
        if (info != null) {
          _cache[id] = info;
          _resolvedAt[id] = info.resolvedAtMs;
          return info;
        }
      } catch (e, st) {
        debugPrint('[YoutubeStreamResolver] $client failed: $e\n$st');
      }
    }
    return null;
  }

  Future<YoutubeStreamInfo?> _resolveWithClient(
    String videoId,
    YoutubeApiClient client,
  ) async {
    final yt = YoutubeManifestResolver.instance.youtubeExplode;
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [client],
    );
    final stream = pickPreferredAudioStream(manifest.audioOnly);
    if (stream == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    return YoutubeStreamInfo(
      videoId: videoId,
      streamUrl: stream.url.toString(),
      mimeType: stream.codec.mimeType,
      bitrateKbps: stream.bitrate.kiloBitsPerSecond.round(),
      contentLength: stream.size.totalBytes,
      resolvedAtMs: now,
    );
  }

  YoutubeStreamInfo? _getCachedIfValid(String videoId) {
    final info = _cache[videoId];
    final at = _resolvedAt[videoId];
    if (info == null || at == null) return null;
    if (DateTime.now().millisecondsSinceEpoch - at > _manifestTtlMs) {
      invalidate(videoId);
      return null;
    }
    return info;
  }

  void invalidate(String videoId) {
    _cache.remove(videoId);
    _resolvedAt.remove(videoId);
  }
}
