import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_channel_ref.dart';
import 'youtube_client.dart';

const Duration _channelResolveTimeout = Duration(seconds: 20);
const Duration _channelSearchMinInterval = Duration(seconds: 2);
const int _channelNameSearchMinLength = 3;

/// Resolves channel URLs, handles, and ids via [ytClient].
class YoutubeChannelResolver {
  YoutubeChannelResolver._();

  static final YoutubeChannelResolver instance = YoutubeChannelResolver._();

  static final RegExp _channelIdPattern = RegExp(r'^UC[\w-]{22}$');
  static final RegExp _channelIdInUrl = RegExp(
    r'youtube\.com/channel/(UC[\w-]{22})',
    caseSensitive: false,
  );
  static final RegExp _handleInUrl = RegExp(
    r'youtube\.com/@([\w.\-]+)',
    caseSensitive: false,
  );

  DateTime? _lastChannelListSearchAt;

  /// Shown in Online search when the last channel lookup failed (rate limit, etc.).
  String? lastChannelSearchError;

  /// True when [raw] is a handle, UC id, or channel URL (not a free-text name).
  static bool isDirectChannelInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('@')) return true;
    if (_channelIdPattern.hasMatch(trimmed)) return true;
    if (_channelIdInUrl.hasMatch(trimmed)) return true;
    if (_handleInUrl.hasMatch(trimmed)) return true;
    return false;
  }

  bool _throttleChannelListSearch() {
    final last = _lastChannelListSearchAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _channelSearchMinInterval;
  }

  void _markChannelListSearch() {
    _lastChannelListSearchAt = DateTime.now();
  }

  /// Finds channels matching [query] (picker UI).
  ///
  /// Uses video search and groups by channel — avoids [SearchClient.searchContent]
  /// with [TypeFilters.channel], which breaks when YouTube changes result JSON.
  Future<List<YoutubeChannelRef>> searchChannels(String query) async {
    final trimmed = query.trim();
    lastChannelSearchError = null;
    if (trimmed.length < _channelNameSearchMinLength) return [];

    if (!_throttleChannelListSearch()) {
      lastChannelSearchError = 'Please wait a moment before searching again.';
      return [];
    }

    try {
      _markChannelListSearch();
      return await _channelsFromVideoSearch(trimmed);
    } on RequestLimitExceededException {
      lastChannelSearchError =
          'YouTube rate limit — wait a minute, then try again.';
      debugPrint('Channel search rate limited for: $trimmed');
      return [];
    } on TimeoutException {
      lastChannelSearchError = 'Channel search timed out. Try again.';
      debugPrint('Channel search timed out for: $trimmed');
      return [];
    } catch (e, st) {
      lastChannelSearchError = 'Could not load channel suggestions.';
      debugPrint('Channel search error: $e\n$st');
      return [];
    }
  }

  Future<List<YoutubeChannelRef>> _channelsFromVideoSearch(String query) async {
    final results = await ytClient.search
        .search(query)
        .timeout(_channelResolveTimeout);
    final seen = <String>{};
    final out = <YoutubeChannelRef>[];
    for (final video in results) {
      final id = video.channelId.value.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(
        YoutubeChannelRef(
          id: id,
          title: video.author.trim().isEmpty ? 'Unknown channel' : video.author,
        ),
      );
      if (out.length >= 10) break;
    }
    return out;
  }

  /// Resolves [raw] to a single channel (URL, @handle, UC id, or name lookup).
  Future<YoutubeChannelRef?> resolveChannelInput(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    lastChannelSearchError = null;

    try {
      final idFromUrl = _channelIdInUrl.firstMatch(trimmed)?.group(1);
      if (idFromUrl != null) {
        return _channelFromId(idFromUrl);
      }

      final handleFromUrl = _handleInUrl.firstMatch(trimmed)?.group(1);
      if (handleFromUrl != null) {
        return _channelFromHandle(handleFromUrl);
      }

      if (_channelIdPattern.hasMatch(trimmed)) {
        return _channelFromId(trimmed);
      }

      if (trimmed.startsWith('@')) {
        return _channelFromHandle(trimmed.substring(1));
      }

      if (trimmed.length < _channelNameSearchMinLength) return null;
      if (!_throttleChannelListSearch()) {
        lastChannelSearchError = 'Please wait a moment before searching again.';
        return null;
      }
      _markChannelListSearch();
      final channels = await _channelsFromVideoSearch(trimmed);
      return channels.isEmpty ? null : channels.first;
    } on RequestLimitExceededException {
      lastChannelSearchError =
          'YouTube rate limit — wait a minute, then try again.';
      debugPrint('Resolve channel rate limited for: $trimmed');
      return null;
    } catch (e, st) {
      lastChannelSearchError = 'Could not resolve channel.';
      debugPrint('Resolve channel error: $e\n$st');
      return null;
    }
  }

  Future<YoutubeChannelRef?> _channelFromId(String id) async {
    final channel = await ytClient.channels
        .get(id)
        .timeout(_channelResolveTimeout);
    return YoutubeChannelRef(
      id: channel.id.value,
      title: channel.title,
      thumbnailUrl: channel.logoUrl,
    );
  }

  /// Resolves the upload channel for a YouTube video id.
  Future<YoutubeChannelRef?> channelForVideo(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    try {
      final video =
          await ytClient.videos.get(id).timeout(_channelResolveTimeout);
      final channelId = video.channelId.value.trim();
      if (channelId.isEmpty) return null;
      return YoutubeChannelRef(
        id: channelId,
        title: video.author.trim().isEmpty ? 'Channel' : video.author,
      );
    } on TimeoutException {
      debugPrint('channelForVideo timed out: $id');
      return null;
    } catch (e, st) {
      debugPrint('channelForVideo error: $e\n$st');
      return null;
    }
  }

  Future<YoutubeChannelRef?> _channelFromHandle(String handle) async {
    final channel = await ytClient.channels
        .getByHandle(handle)
        .timeout(_channelResolveTimeout);
    return YoutubeChannelRef(
      id: channel.id.value,
      title: channel.title,
      thumbnailUrl: channel.logoUrl,
    );
  }
}
