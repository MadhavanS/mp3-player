import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../help/search_help_text.dart';
import '../../services/youtube_channel_resolver.dart';

/// How a single Online search field should be interpreted.
enum OnlineSearchInputKind {
  empty,
  atChannel,
  youtubeUrl,
  hashtag,
  plain,
}

/// Parsed value from the unified search box (prefix shortcuts).
class OnlineSearchInput {
  const OnlineSearchInput({
    required this.kind,
    required this.raw,
    this.channelToken,
    this.inChannelQuery,
    this.url,
    this.plainQuery,
    this.videoId,
    this.playlistId,
    this.isChannelUrl = false,
  });

  final OnlineSearchInputKind kind;
  final String raw;

  /// Text after `@` used to resolve a channel (handle, name, UC…, or channel URL).
  final String? channelToken;

  /// Words after the channel token in `@channel query` form.
  final String? inChannelQuery;

  /// Full pasted link when [kind] is [OnlineSearchInputKind.youtubeUrl].
  final String? url;

  /// Plain or `#tag` search text.
  final String? plainQuery;

  final String? videoId;
  final String? playlistId;
  final bool isChannelUrl;

  static final RegExp _urlPattern = RegExp(
    r'^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be|m\.youtube\.com)\/',
    caseSensitive: false,
  );

  static OnlineSearchInput parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return OnlineSearchInput(kind: OnlineSearchInputKind.empty, raw: trimmed);
    }

    if (trimmed.startsWith('@')) {
      return _parseAtChannel(trimmed);
    }

    if (_looksLikeYoutubeUrl(trimmed)) {
      return _parseUrl(trimmed);
    }

    if (trimmed.startsWith('#') && trimmed.length > 1) {
      return OnlineSearchInput(
        kind: OnlineSearchInputKind.hashtag,
        raw: trimmed,
        plainQuery: trimmed,
      );
    }

    return OnlineSearchInput(
      kind: OnlineSearchInputKind.plain,
      raw: trimmed,
      plainQuery: trimmed,
    );
  }

  static OnlineSearchInput _parseAtChannel(String trimmed) {
    final body = trimmed.substring(1).trim();
    if (body.isEmpty) {
      return OnlineSearchInput(kind: OnlineSearchInputKind.atChannel, raw: trimmed);
    }

    if (YoutubeChannelResolver.isDirectChannelInput('@$body') ||
        _looksLikeYoutubeUrl(body)) {
      return OnlineSearchInput(
        kind: OnlineSearchInputKind.atChannel,
        raw: trimmed,
        channelToken: body,
        inChannelQuery: '',
      );
    }

    final space = body.indexOf(' ');
    if (space < 0) {
      return OnlineSearchInput(
        kind: OnlineSearchInputKind.atChannel,
        raw: trimmed,
        channelToken: body,
        inChannelQuery: '',
      );
    }

    return OnlineSearchInput(
      kind: OnlineSearchInputKind.atChannel,
      raw: trimmed,
      channelToken: body.substring(0, space).trim(),
      inChannelQuery: body.substring(space + 1).trim(),
    );
  }

  static OnlineSearchInput _parseUrl(String trimmed) {
    String? videoId;
    String? playlistId;
    var isChannel = false;

    try {
      videoId = VideoId.parseVideoId(trimmed);
    } catch (_) {}

    if (videoId == null) {
      try {
        playlistId = PlaylistId.parsePlaylistId(trimmed);
      } catch (_) {}
    }

    if (videoId == null && playlistId == null) {
      isChannel = YoutubeChannelResolver.isDirectChannelInput(trimmed) ||
          RegExp(r'youtube\.com/channel/', caseSensitive: false).hasMatch(trimmed) ||
          RegExp(r'youtube\.com/@', caseSensitive: false).hasMatch(trimmed);
    }

    return OnlineSearchInput(
      kind: OnlineSearchInputKind.youtubeUrl,
      raw: trimmed,
      url: trimmed,
      videoId: videoId,
      playlistId: playlistId,
      isChannelUrl: isChannel,
    );
  }

  static bool _looksLikeYoutubeUrl(String text) {
    if (_urlPattern.hasMatch(text)) return true;
    if (text.contains('youtu.be/')) return true;
    return false;
  }

  /// True while the user is typing an `@` channel lookup (show channel chips).
  bool get isTypingChannelLookup {
    if (kind != OnlineSearchInputKind.atChannel) return false;
    final token = channelToken?.trim() ?? '';
    return token.isNotEmpty;
  }

  String get channelLookupQuery {
    if (kind != OnlineSearchInputKind.atChannel) return '';
    return channelToken?.trim() ?? '';
  }

  IconData get prefixIcon => switch (kind) {
        OnlineSearchInputKind.atChannel => Icons.alternate_email_rounded,
        OnlineSearchInputKind.youtubeUrl => Icons.link_rounded,
        OnlineSearchInputKind.hashtag => Icons.tag_rounded,
        OnlineSearchInputKind.plain => Icons.search_rounded,
        OnlineSearchInputKind.empty => Icons.search_rounded,
      };

  static const String unifiedHint = SearchHelpText.onlineSearchFieldHint;
}
