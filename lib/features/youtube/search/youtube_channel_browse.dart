import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_track.dart';
import 'youtube_search_service.dart';

/// One page of uploads from a YouTube channel (15 tracks).
class YoutubeChannelBrowsePage {
  const YoutubeChannelBrowsePage({
    required this.channelTitle,
    required this.pageIndex,
    required this.tracks,
    required this.hasPreviousPage,
    required this.hasNextPage,
  });

  final String channelTitle;
  final int pageIndex;
  final List<YoutubeTrack> tracks;
  final bool hasPreviousPage;
  final bool hasNextPage;
}

/// Paginated channel uploads (15 tracks per UI page).
class YoutubeChannelBrowse {
  YoutubeChannelBrowse._({
    required this.channelTitle,
    required this.channelId,
    required List<YoutubeTrack> initialTracks,
    ChannelUploadsList? apiPage,
    StreamIterator<Video>? uploadIterator,
  })  : _tracks = List<YoutubeTrack>.from(initialTracks),
        _apiPage = apiPage,
        _uploadIterator = uploadIterator;

  static const int pageSize = 15;

  final String channelTitle;
  final ChannelId channelId;

  final List<YoutubeTrack> _tracks;
  ChannelUploadsList? _apiPage;
  StreamIterator<Video>? _uploadIterator;
  bool _apiExhausted = false;
  int _currentPageIndex = 0;

  static Future<YoutubeChannelBrowse?> open(String channelQuery) async {
    final channel =
        await YoutubeSearchService.instance.resolveChannel(channelQuery);
    if (channel == null) {
      debugPrint('[YoutubeChannelBrowse] channel not found for: $channelQuery');
      return null;
    }

    final service = YoutubeSearchService.instance;
    final yt = service.youtubeExplode;

    // Uploads playlist is the most reliable on current YouTube layouts.
    try {
      final playlistId = YoutubeSearchService.uploadsPlaylistId(channel.id);
      final iterator = StreamIterator<Video>(
        yt.playlists.getVideos(playlistId),
      );
      final initial = await _readUploadBatch(iterator, pageSize * 2);
      debugPrint(
        '[YoutubeChannelBrowse] playlist uploads: ${initial.length} for ${channel.title}',
      );
      return YoutubeChannelBrowse._(
        channelTitle: channel.title,
        channelId: channel.id,
        initialTracks: initial,
        uploadIterator: iterator,
      );
    } catch (e, st) {
      debugPrint('YoutubeChannelBrowse.open playlist: $e\n$st');
    }

    try {
      final iterator = StreamIterator<Video>(
        yt.channels.getUploads(channel.id),
      );
      final initial = await _readUploadBatch(iterator, pageSize * 2);
      debugPrint(
        '[YoutubeChannelBrowse] stream uploads: ${initial.length} for ${channel.title}',
      );
      return YoutubeChannelBrowse._(
        channelTitle: channel.title,
        channelId: channel.id,
        initialTracks: initial,
        uploadIterator: iterator,
      );
    } catch (e, st) {
      debugPrint('YoutubeChannelBrowse.open stream: $e\n$st');
    }

    try {
      final uploads = await yt.channels.getUploadsFromPage(channel.id);
      final initial = uploads
          .map(service.trackFromVideo)
          .toList(growable: false);
      debugPrint(
        '[YoutubeChannelBrowse] page uploads: ${initial.length} for ${channel.title}',
      );
      return YoutubeChannelBrowse._(
        channelTitle: channel.title,
        channelId: channel.id,
        initialTracks: initial,
        apiPage: uploads,
      );
    } catch (e, st) {
      debugPrint('YoutubeChannelBrowse.open uploads page: $e\n$st');
    }

    debugPrint(
      '[YoutubeChannelBrowse] channel found but no uploads loaded: ${channel.title}',
    );
    return YoutubeChannelBrowse._(
      channelTitle: channel.title,
      channelId: channel.id,
      initialTracks: const [],
    );
  }

  static Future<List<YoutubeTrack>> _readUploadBatch(
    StreamIterator<Video> iterator,
    int count,
  ) async {
    final service = YoutubeSearchService.instance;
    final out = <YoutubeTrack>[];
    while (out.length < count && await iterator.moveNext()) {
      out.add(service.trackFromVideo(iterator.current));
    }
    return out;
  }

  YoutubeChannelBrowsePage currentPage() {
    final start = _currentPageIndex * pageSize;
    final end = (start + pageSize).clamp(0, _tracks.length);
    final pageTracks = start >= _tracks.length
        ? const <YoutubeTrack>[]
        : _tracks.sublist(start, end);

    return YoutubeChannelBrowsePage(
      channelTitle: channelTitle,
      pageIndex: _currentPageIndex,
      tracks: pageTracks,
      hasPreviousPage: _currentPageIndex > 0,
      hasNextPage: _hasNextPage(),
    );
  }

  bool _hasNextPage() {
    final nextStart = (_currentPageIndex + 1) * pageSize;
    return nextStart < _tracks.length || !_apiExhausted;
  }

  Future<YoutubeChannelBrowsePage?> nextPage() async {
    if (!_hasNextPage()) return null;
    _currentPageIndex++;
    await _ensureLoadedThrough((_currentPageIndex + 1) * pageSize);
    return currentPage();
  }

  Future<YoutubeChannelBrowsePage?> previousPage() async {
    if (_currentPageIndex <= 0) return null;
    _currentPageIndex--;
    return currentPage();
  }

  Future<void> _ensureLoadedThrough(int endExclusive) async {
    while (_tracks.length < endExclusive && !_apiExhausted) {
      if (_apiPage != null) {
        final next = await _apiPage!.nextPage();
        if (next == null) {
          _apiExhausted = true;
          _apiPage = null;
          break;
        }
        _apiPage = next;
        _tracks.addAll(
          next.map(YoutubeSearchService.instance.trackFromVideo),
        );
        continue;
      }

      if (_uploadIterator != null) {
        final before = _tracks.length;
        while (_tracks.length < endExclusive &&
            await _uploadIterator!.moveNext()) {
          _tracks.add(
            YoutubeSearchService.instance.trackFromVideo(
              _uploadIterator!.current,
            ),
          );
        }
        if (_tracks.length == before) {
          _apiExhausted = true;
          _uploadIterator = null;
        }
        continue;
      }

      _apiExhausted = true;
      break;
    }
  }
}
