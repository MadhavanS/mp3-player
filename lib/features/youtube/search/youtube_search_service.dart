import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_track.dart';
import 'youtube_channel_query.dart';

/// YouTube search (metadata only — playback uses downloaded local files).
class YoutubeSearchService {
  YoutubeSearchService._();

  static final instance = YoutubeSearchService._();

  final YoutubeExplode _yt = YoutubeExplode();

  YoutubeExplode get youtubeExplode => _yt;

  Future<List<YoutubeTrack>> search(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty || isYoutubeChannelSearchQuery(q)) return const [];

    try {
      final list = await _yt.search.search(q);
      final videos = list.take(limit);
      return videos.map(trackFromVideo).toList(growable: false);
    } catch (e, st) {
      debugPrint('YoutubeSearchService.search: $e\n$st');
      return const [];
    }
  }

  /// Resolves a channel from `@handle`, `@name`, or plain channel name.
  Future<Channel?> resolveChannel(String query) async {
    final name = isYoutubeChannelSearchQuery(query)
        ? youtubeChannelNameFromQuery(query)
        : query.trim();
    if (name.isEmpty) return null;

    final normalized = _normalizeChannelName(name);

    // Direct @handle URL (works for Unicode handles; skip strict ASCII regex).
    if (!name.contains(' ')) {
      final handle = name.startsWith('@') ? name : '@$name';
      try {
        final channel = await _yt.channels.getByHandle(handle);
        debugPrint('[YoutubeSearch] resolved handle $handle → ${channel.id}');
        return channel;
      } catch (e, st) {
        debugPrint('YoutubeSearchService.resolveChannel handle: $e\n$st');
      }
    }

    final searchTerms = <String>{
      name,
      if (!name.startsWith('@')) '@$name',
      '$name channel',
      normalized,
    };

    for (final term in searchTerms) {
      final fromChannelFilter = await _resolveFromSearchContent(
        term,
        TypeFilters.channel,
        normalized,
      );
      if (fromChannelFilter != null) return fromChannelFilter;

      final fromMixed = await _resolveFromSearchContent(
        term,
        const SearchFilter(''),
        normalized,
      );
      if (fromMixed != null) return fromMixed;
    }

    for (final term in searchTerms) {
      final fromVideos = await _findChannelFromVideoSearch(term, normalized);
      if (fromVideos != null) return fromVideos;
    }

    return null;
  }

  static String _normalizeChannelName(String name) {
    return name.toLowerCase().replaceAll('@', '').trim();
  }

  Future<Channel?> _resolveFromSearchContent(
    String searchTerm,
    SearchFilter filter,
    String normalizedName,
  ) async {
    try {
      var results = await _yt.search.searchContent(searchTerm, filter: filter);

      for (var page = 0; page < 4; page++) {
        final channelResult = _pickChannelMatch(results, normalizedName);
        if (channelResult != null) {
          return _yt.channels.get(channelResult.id);
        }

        final fromVideos =
            await _pickChannelFromSearchVideos(results, normalizedName);
        if (fromVideos != null) return fromVideos;

        final next = await results.nextPage();
        if (next == null) break;
        results = next;
      }
    } catch (e, st) {
      debugPrint('YoutubeSearchService._resolveFromSearchContent: $e\n$st');
    }
    return null;
  }

  SearchChannel? _pickChannelMatch(
    List<SearchResult> results,
    String normalizedName,
  ) {
    SearchChannel? first;
    SearchChannel? best;

    for (final item in results) {
      if (item is! SearchChannel) continue;
      first ??= item;
      final channelLower = _normalizeChannelName(item.name);
      if (channelLower == normalizedName) return item;
      if (channelLower.contains(normalizedName) ||
          normalizedName.contains(channelLower)) {
        best ??= item;
      }
    }

    return best ?? first;
  }

  Future<Channel?> _pickChannelFromSearchVideos(
    List<SearchResult> results,
    String normalizedName,
  ) async {
    ChannelId? exactId;
    ChannelId? partialId;

    for (final item in results) {
      if (item is! SearchVideo) continue;
      final channelId = item.channelId.trim();
      if (channelId.isEmpty) continue;

      final author = _normalizeChannelName(item.author);
      final cid = ChannelId(channelId);
      if (author == normalizedName) {
        exactId = cid;
        break;
      }
      if (partialId == null &&
          (author.contains(normalizedName) ||
              normalizedName.contains(author))) {
        partialId = cid;
      }
    }

    final id = exactId ?? partialId;
    if (id == null) return null;

    try {
      return await _yt.channels.get(id);
    } catch (e, st) {
      debugPrint('YoutubeSearchService._pickChannelFromSearchVideos: $e\n$st');
      return null;
    }
  }

  Future<Channel?> _findChannelFromVideoSearch(
    String searchTerm,
    String normalizedName,
  ) async {
    try {
      final videos = await _yt.search.search(
        searchTerm,
        filter: TypeFilters.video,
      );
      if (videos.isEmpty) return null;

      ChannelId? exactId;
      ChannelId? partialId;

      for (final video in videos) {
        final author = _normalizeChannelName(video.author);
        if (author == normalizedName) {
          exactId = video.channelId;
          break;
        }
        if (partialId == null &&
            (author.contains(normalizedName) ||
                normalizedName.contains(author))) {
          partialId = video.channelId;
        }
      }

      final id = exactId ?? partialId;
      if (id == null) return null;

      final channel = await _yt.channels.get(id);
      debugPrint(
        '[YoutubeSearch] resolved "$searchTerm" via videos → ${channel.title}',
      );
      return channel;
    } catch (e, st) {
      debugPrint('YoutubeSearchService._findChannelFromVideoSearch: $e\n$st');
      return null;
    }
  }

  /// Uploads playlist id (`UU…`) for a channel id (`UC…`).
  static PlaylistId uploadsPlaylistId(ChannelId channelId) {
    final value = channelId.value;
    if (value.startsWith('UC') && value.length > 2) {
      return PlaylistId('UU${value.substring(2)}');
    }
    return PlaylistId('UU$value');
  }

  Future<YoutubeTrack?> resolveVideo(String videoIdOrUrl) async {
    try {
      final video = await _yt.videos.get(videoIdOrUrl);
      return trackFromVideo(video);
    } catch (e, st) {
      debugPrint('YoutubeSearchService.resolveVideo: $e\n$st');
      return null;
    }
  }

  YoutubeTrack trackFromVideo(Video video) {
    return YoutubeTrack(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration,
    );
  }

  void close() => _yt.close();
}
