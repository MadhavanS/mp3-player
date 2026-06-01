import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../models/library_tab_id.dart';
import '../../../models/track_item.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/action_pill_toast.dart';
import '../catalog/youtube_library_catalog.dart';
import '../download/youtube_download_job.dart';
import '../download/youtube_download_manager.dart';
import '../models/youtube_track.dart';
import '../search/youtube_bookmark_store.dart';
import '../search/youtube_channel_browse.dart';
import '../search/youtube_channel_query.dart';
import '../search/youtube_search_history_status.dart';
import '../search/youtube_search_history_store.dart';
import '../search/youtube_search_service.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_duration_format.dart';
import '../youtube_settings_store.dart';
import '../youtube_search_playback.dart';
import '../../help/search_help_text.dart';
import 'youtube_download_sheet.dart';
import 'youtube_track_tile.dart';

class YoutubeSearchScreen extends StatelessWidget {
  const YoutubeSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const YoutubeSearchTab(),
    );
  }
}

/// YouTube lookup UI — used in Library › Find and the standalone screen.
class YoutubeSearchTab extends StatefulWidget {
  const YoutubeSearchTab({
    super.key,
    this.searchController,
    this.onSearchingChanged,
  });

  /// When set (Library › Find), the top library search bar owns the query field.
  final TextEditingController? searchController;

  final ValueChanged<bool>? onSearchingChanged;

  @override
  State<YoutubeSearchTab> createState() => YoutubeSearchTabState();
}

class YoutubeSearchTabState extends State<YoutubeSearchTab> {
  TextEditingController? _ownedQueryController;

  TextEditingController get _queryController =>
      widget.searchController ?? _ownedQueryController!;

  bool get _usesLibrarySearchBar => widget.searchController != null;
  var _searching = false;
  var _paging = false;
  List<YoutubeTrack> _results = const [];
  Set<String> _downloadedVideoIds = const {};
  Set<String> _bookmarkedVideoIds = const {};
  YoutubeChannelBrowse? _channelBrowse;
  YoutubeChannelBrowsePage? _channelPage;
  String? _channelError;
  List<String> _searchHistory = const [];
  String? _activeQuery;
  final Map<String, YoutubeSearchHistoryStatus> _historyStatus = {};

  @override
  void initState() {
    super.initState();
    if (!_usesLibrarySearchBar) {
      _ownedQueryController = TextEditingController()
        ..addListener(_onOwnedQueryChanged);
    }
    YoutubeDownloadManager.instance.addListener(_onDownloadsChanged);
    YoutubeBookmarkStore.revision.addListener(_onBookmarkRevision);
    unawaited(_refreshDownloadedIds());
    unawaited(_refreshBookmarkedIds());
    unawaited(_loadSearchHistory());
  }

  void _onBookmarkRevision() {
    unawaited(_refreshBookmarkedIds());
  }

  Future<void> _refreshBookmarkedIds() async {
    final ids = await YoutubeBookmarkStore.loadVideoIds();
    if (!mounted) return;
    setState(() => _bookmarkedVideoIds = ids);
  }

  Future<void> _loadSearchHistory() async {
    final history = await YoutubeSearchHistoryStore.load();
    if (!mounted) return;
    setState(() => _searchHistory = history);
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.removeListener(_onDownloadsChanged);
    YoutubeBookmarkStore.revision.removeListener(_onBookmarkRevision);
    _ownedQueryController?.dispose();
    super.dispose();
  }

  void _setSearching(bool value) {
    widget.onSearchingChanged?.call(value);
  }

  void _onOwnedQueryChanged() {
    if (mounted) setState(() {});
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshDownloadedIds());
  }

  void _clearOwnedQuery() {
    _queryController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  InputDecoration _ownedQueryDecoration(AppPalette pal, ThemeData theme) {
    final hasQuery = _queryController.text.trim().isNotEmpty;
    final showSuffix = hasQuery || _searching;
    return InputDecoration(
      hintText: SearchHelpText.youtubeFindFieldHint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: pal.textMuted.withValues(alpha: 0.72),
      ),
      isDense: true,
      filled: true,
      fillColor: pal.onScaffold.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: pal.textMuted.withValues(alpha: 0.9),
        size: 22,
      ),
      suffixIcon: showSuffix
          ? SizedBox(
              width: hasQuery && _searching ? 88 : 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: pal.accent,
                        ),
                      ),
                    ),
                  if (hasQuery)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(
                        Icons.close_rounded,
                        color: pal.onScaffold.withValues(alpha: 0.75),
                        size: 20,
                      ),
                      onPressed: _clearOwnedQuery,
                    ),
                ],
              ),
            )
          : null,
    );
  }

  Future<void> _refreshDownloadedIds() async {
    final ids = await YoutubeTrackStore.instance.downloadedVideoIds();
    if (!mounted) return;
    setState(() => _downloadedVideoIds = ids);
  }

  Future<void> runSearch([String? queryOverride]) async {
    final q = (queryOverride ?? _queryController.text).trim();
    if (q.isEmpty) return;

    if (queryOverride != null && !_usesLibrarySearchBar) {
      _queryController.text = q;
    } else if (queryOverride != null && _usesLibrarySearchBar) {
      widget.searchController!.text = q;
    }

    setState(() {
      _searching = true;
      _activeQuery = q;
      _historyStatus[q] = YoutubeSearchHistoryStatus.loading;
      _results = const [];
      _channelBrowse = null;
      _channelPage = null;
      _channelError = null;
    });
    _setSearching(true);

    final history = await YoutubeSearchHistoryStore.remember(q);
    if (mounted) {
      setState(() => _searchHistory = history);
    }

    void finish(YoutubeSearchHistoryStatus status) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _historyStatus[q] = status;
        if (_activeQuery == q) _activeQuery = null;
      });
      _setSearching(false);
    }

    if (isYoutubeChannelSearchQuery(q)) {
      final browse = await YoutubeChannelBrowse.open(q);
      await _refreshDownloadedIds();
      if (!mounted) return;
      if (browse == null) {
        setState(() {
          _channelError =
              'Could not find channel "$q". Try @handle or the exact channel name.';
        });
        finish(YoutubeSearchHistoryStatus.failed);
        return;
      }
      final page = browse.currentPage();
      setState(() {
        _channelBrowse = browse;
        _channelPage = page;
        _results = page.tracks;
        if (page.tracks.isEmpty) {
          _channelError =
              'Channel "${page.channelTitle}" has no uploads to show yet.';
        }
      });
      finish(
        page.tracks.isEmpty
            ? YoutubeSearchHistoryStatus.empty
            : YoutubeSearchHistoryStatus.success,
      );
      return;
    }

    final results = await YoutubeSearchService.instance.search(q);
    await _refreshDownloadedIds();
    if (!mounted) return;
    setState(() => _results = results);
    finish(
      results.isEmpty
          ? YoutubeSearchHistoryStatus.empty
          : YoutubeSearchHistoryStatus.success,
    );
  }

  Future<void> _goChannelPage({required bool next}) async {
    final browse = _channelBrowse;
    if (browse == null || _paging) return;

    setState(() => _paging = true);
    try {
      final page = next ? await browse.nextPage() : await browse.previousPage();
      if (!mounted || page == null) return;
      setState(() {
        _channelPage = page;
        _results = page.tracks;
      });
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  void clearResults() {
    setState(() {
      _searching = false;
      _activeQuery = null;
      _results = const [];
      _channelBrowse = null;
      _channelPage = null;
      _channelError = null;
    });
    _setSearching(false);
  }

  Future<void> _playSearchResult(int index) async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    try {
      await playYoutubeSearchResult(
        context: context,
        player: player,
        results: _results,
        index: index,
      );
    } catch (e, st) {
      debugPrint('YoutubeSearchTab._playSearchResult: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play: $e')),
      );
    }
  }

  Future<void> _handleSearchMenuAction(
    _YoutubeSearchMenuAction action,
    int index,
  ) async {
    if (!mounted || index < 0 || index >= _results.length) return;
    final yt = _results[index];
    final player = PlayerController.of(context);

    switch (action) {
      case _YoutubeSearchMenuAction.bookmark:
        final added = await YoutubeBookmarkStore.toggle(yt);
        await _refreshBookmarkedIds();
        if (!mounted) return;
        ActionPillToast.show(
          context,
          added ? 'Bookmarked' : 'Bookmark removed',
          icon: added ? Icons.bookmark : Icons.bookmark_border,
          uppercaseLabel: true,
        );
        return;

      case _YoutubeSearchMenuAction.download:
        await _download(yt);
        return;

      case _YoutubeSearchMenuAction.playNext:
      case _YoutubeSearchMenuAction.addToQueue:
      case _YoutubeSearchMenuAction.playOnly:
        final item = await trackItemForYoutubeSearchTrack(yt);
        if (!mounted) return;
        if (item == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not queue this track')),
          );
          return;
        }
        player.setPlaybackPathKeyScope(null, reloadQueue: false);
        switch (action) {
          case _YoutubeSearchMenuAction.playNext:
            final added = await player.playTrackNext(
              item,
              playbackOriginTab: LibraryTabId.youtubeSearch,
            );
            if (!mounted) return;
            ActionPillToast.show(
              context,
              added ? 'Queued as next' : 'Already in queue',
              icon: Icons.queue_play_next_rounded,
              uppercaseLabel: true,
            );
          case _YoutubeSearchMenuAction.addToQueue:
            final added = await player.addToPlaylistIfAbsent(item);
            if (!mounted) return;
            ActionPillToast.show(
              context,
              added ? 'Added to queue' : 'Already in queue',
              icon: Icons.playlist_add_rounded,
              uppercaseLabel: true,
            );
          case _YoutubeSearchMenuAction.playOnly:
            await player.setPlaylistAndPlay(
              [item],
              playbackOriginTab: LibraryTabId.youtubeSearch,
            );
          case _YoutubeSearchMenuAction.bookmark:
          case _YoutubeSearchMenuAction.download:
            break;
        }
    }
  }

  Future<void> _download(YoutubeTrack track) async {
    if (_downloadedVideoIds.contains(track.videoId)) return;
    try {
      await YoutubeDownloadManager.instance.enqueue(track);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading "${track.title}"')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const YoutubeActiveDownloadsBar(),
            if (!_usesLibrarySearchBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        decoration: _ownedQueryDecoration(pal, theme),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: pal.onScaffold,
                          fontSize: 15,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => unawaited(runSearch()),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                      ),
                    ),
                    IconButton(
                      onPressed: _searching ? null : () => unawaited(runSearch()),
                      icon: _searching
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: pal.accent,
                              ),
                            )
                          : Icon(Icons.search_rounded, color: pal.onScaffold),
                    ),
                  ],
                ),
              ),
            if (_searchHistory.isNotEmpty)
              _YoutubeSearchHistoryPills(
                queries: _searchHistory,
                activeQuery: _activeQuery,
                statusFor: (q) =>
                    _historyStatus[q] ?? YoutubeSearchHistoryStatus.idle,
                onTap: (q) => unawaited(runSearch(q)),
                onRemove: (q) async {
                  await YoutubeSearchHistoryStore.remove(q);
                  if (!mounted) return;
                  setState(() {
                    _searchHistory = _searchHistory
                        .where((item) => item != q)
                        .toList(growable: false);
                    _historyStatus.remove(q);
                  });
                },
              ),
            if (_channelPage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_channelPage!.channelTitle} · page ${_channelPage!.pageIndex + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: pal.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _buildResultsBody(theme, pal),
            ),
          ],
        ),
        if (_channelPage != null) ...[
          if (_channelPage!.hasPreviousPage)
            Positioned(
              left: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'yt_channel_prev',
                onPressed: _paging
                    ? null
                    : () => unawaited(_goChannelPage(next: false)),
                tooltip: 'Previous page',
                child: _paging
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_left),
              ),
            ),
          if (_channelPage!.hasNextPage)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'yt_channel_next',
                onPressed: _paging
                    ? null
                    : () => unawaited(_goChannelPage(next: true)),
                tooltip: 'Next page',
                child: _paging
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildResultsBody(ThemeData theme, AppPalette pal) {
    if (_channelError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _channelError!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary,
            ),
          ),
        ),
      );
    }

    if (_results.isEmpty && _channelPage == null) {
      return Center(
        child: _searching
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: pal.accent),
                  const SizedBox(height: 16),
                  Text(
                    'Loading…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary,
                    ),
                  ),
                ],
              )
            : Text(
                'Title, artist, or @channel',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary,
                ),
              ),
      );
    }

    if (_searching && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: pal.accent),
            const SizedBox(height: 16),
            Text(
              'Loading…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: pal.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: _channelPage != null ? 80 : 0,
      ),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: pal.dividerOnHero.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, i) {
        final t = _results[i];
        final job = YoutubeDownloadManager.instance.jobForVideoId(t.videoId);
        final downloaded = _downloadedVideoIds.contains(t.videoId);
        return _YoutubeSearchResultTile(
          track: t,
          downloaded: downloaded,
          bookmarked: _bookmarkedVideoIds.contains(t.videoId),
          job: job,
          onTap: () => unawaited(_playSearchResult(i)),
          onMenuAction: (action) =>
              unawaited(_handleSearchMenuAction(action, i)),
        );
      },
    );
  }
}

class _YoutubeSearchHistoryPills extends StatelessWidget {
  const _YoutubeSearchHistoryPills({
    required this.queries,
    required this.activeQuery,
    required this.statusFor,
    required this.onTap,
    required this.onRemove,
  });

  final List<String> queries;
  final String? activeQuery;
  final YoutubeSearchHistoryStatus Function(String query) statusFor;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent',
              style: theme.textTheme.labelMedium?.copyWith(
                color: pal.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: queries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final q = queries[i];
                  final status = statusFor(q);
                  final isActive = activeQuery == q;
                  final effectiveStatus = isActive &&
                          status == YoutubeSearchHistoryStatus.idle
                      ? YoutubeSearchHistoryStatus.loading
                      : status;

                  return InputChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: _HistoryPillIcon(
                      query: q,
                      status: effectiveStatus,
                      accent: pal.accent,
                    ),
                    label: Text(
                      q,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: effectiveStatus ==
                            YoutubeSearchHistoryStatus.loading
                        ? null
                        : () => onTap(q),
                    onDeleted: effectiveStatus ==
                            YoutubeSearchHistoryStatus.loading
                        ? null
                        : () => onRemove(q),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPillIcon extends StatelessWidget {
  const _HistoryPillIcon({
    required this.query,
    required this.status,
    required this.accent,
  });

  final String query;
  final YoutubeSearchHistoryStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (status) {
      case YoutubeSearchHistoryStatus.loading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        );
      case YoutubeSearchHistoryStatus.success:
        return Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary);
      case YoutubeSearchHistoryStatus.empty:
        return Icon(
          Icons.playlist_remove,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        );
      case YoutubeSearchHistoryStatus.failed:
        return Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error);
      case YoutubeSearchHistoryStatus.idle:
        return Icon(
          isYoutubeChannelSearchQuery(query)
              ? Icons.account_circle_outlined
              : Icons.history,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
        );
    }
  }
}

enum _YoutubeSearchMenuAction {
  bookmark,
  playNext,
  addToQueue,
  playOnly,
  download,
}

class _YoutubeSearchResultTile extends StatelessWidget {
  const _YoutubeSearchResultTile({
    required this.track,
    required this.downloaded,
    required this.bookmarked,
    required this.job,
    required this.onTap,
    required this.onMenuAction,
  });

  final YoutubeTrack track;
  final bool downloaded;
  final bool bookmarked;
  final YoutubeDownloadJob? job;
  final VoidCallback onTap;
  final ValueChanged<_YoutubeSearchMenuAction> onMenuAction;

  bool get _downloadInProgress {
    final active = job;
    return active != null &&
        active.state != YoutubeDownloadState.failed &&
        active.state != YoutubeDownloadState.cancelled &&
        active.state != YoutubeDownloadState.complete;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: track.thumbnailUrl != null
            ? Image.network(
                track.thumbnailUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.music_video_outlined),
              )
            : const Icon(Icons.music_video_outlined),
        title: Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.duration != null
              ? '${track.artist} · ${formatYoutubeDurationMs(track.duration!.inMilliseconds)}'
              : track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bookmarked)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.bookmark,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (downloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              )
            else if (_downloadInProgress)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: job!.state == YoutubeDownloadState.downloading
                      ? CircularProgressIndicator(
                          value: job!.progress,
                          strokeWidth: 2,
                        )
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            PopupMenuButton<_YoutubeSearchMenuAction>(
              icon: Icon(Icons.more_vert, color: pal.onScaffold),
              tooltip: 'More options',
              onSelected: onMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _YoutubeSearchMenuAction.bookmark,
                  child: _SearchMenuRow(
                    icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    label: bookmarked ? 'Remove bookmark' : 'Bookmark',
                  ),
                ),
                const PopupMenuItem(
                  value: _YoutubeSearchMenuAction.playNext,
                  child: _SearchMenuRow(
                    icon: Icons.queue_play_next_rounded,
                    label: 'Play next',
                  ),
                ),
                const PopupMenuItem(
                  value: _YoutubeSearchMenuAction.addToQueue,
                  child: _SearchMenuRow(
                    icon: Icons.playlist_add_rounded,
                    label: 'Add to queue',
                  ),
                ),
                const PopupMenuItem(
                  value: _YoutubeSearchMenuAction.playOnly,
                  child: _SearchMenuRow(
                    icon: Icons.music_note_rounded,
                    label: 'Play this track only',
                  ),
                ),
                PopupMenuItem(
                  value: _YoutubeSearchMenuAction.download,
                  enabled: !_downloadInProgress,
                  child: _SearchMenuRow(
                    icon: downloaded
                        ? Icons.download_done_rounded
                        : Icons.download_outlined,
                    label: downloaded ? 'Download again' : 'Download',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMenuRow extends StatelessWidget {
  const _SearchMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _YoutubeLibraryFolderHeader extends StatelessWidget {
  const _YoutubeLibraryFolderHeader({
    required this.directoryPath,
    required this.summaryLine,
    required this.loading,
  });

  final String? directoryPath;
  final String? summaryLine;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final path = directoryPath?.trim();
    final summary = summaryLine?.trim();

    if ((path == null || path.isEmpty) && (summary == null || summary.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null && path.isNotEmpty)
            Text(
              path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          if (summary != null && summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              loading ? 'Scanning folder…' : summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class YoutubeLibraryTab extends StatefulWidget {
  const YoutubeLibraryTab({
    super.key,
    required this.player,
    this.searchController,
  });

  final PlayerController player;

  /// Hub search field — filters [YoutubeLibraryCatalog] tracks when set.
  final TextEditingController? searchController;

  @override
  State<YoutubeLibraryTab> createState() => _YoutubeLibraryTabState();
}

class _YoutubeLibraryTabState extends State<YoutubeLibraryTab> {
  bool _scanning = false;
  VoidCallback? _youtubeSettingsListener;

  @override
  void initState() {
    super.initState();
    YoutubeDownloadManager.instance.lastCompletedJob.addListener(
      _onDownloadCompleted,
    );
    _youtubeSettingsListener = () => unawaited(_refreshStorageFolder());
    YoutubeSettingsStore.revision.addListener(_youtubeSettingsListener!);
    unawaited(_refreshStorageFolder());
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.lastCompletedJob.removeListener(
      _onDownloadCompleted,
    );
    if (_youtubeSettingsListener != null) {
      YoutubeSettingsStore.revision.removeListener(_youtubeSettingsListener!);
    }
    super.dispose();
  }

  void _onDownloadCompleted() {
    if (YoutubeDownloadManager.instance.lastCompletedJob.value == null) return;
    unawaited(YoutubeLibraryCatalog.instance.reload());
  }

  Future<void> _refreshStorageFolder() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await YoutubeLibraryCatalog.instance.reload();
    } catch (e, st) {
      debugPrint('YoutubeLibraryTab scan: $e\n$st');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<TrackItem> _filterTracks(List<TrackItem> tracks) {
    final q = widget.searchController?.text.trim().toLowerCase() ?? '';
    if (q.isEmpty) return tracks;
    return tracks.where((t) {
      if (t.title.toLowerCase().contains(q)) return true;
      if (t.artist.toLowerCase().contains(q)) return true;
      if (t.metaLine.toLowerCase().contains(q)) return true;
      final path = t.filePath?.toLowerCase() ?? '';
      return path.contains(q);
    }).toList(growable: false);
  }

  Widget _buildLibraryBody(
    BuildContext context,
    ThemeData theme,
    AppPalette pal,
    YoutubeLibraryCatalog catalog,
    List<TrackItem> filtered,
  ) {
    final query = widget.searchController?.text.trim() ?? '';

    if (catalog.tracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshStorageFolder,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Downloaded YouTube audio appears here.\n'
                    'Place .m4a, .webm, or .mp3 files in your YouTube folder, '
                    'pull down to refresh, or open Find to download tracks.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshStorageFolder,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.3,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    query.isEmpty
                        ? 'No downloads match.'
                        : 'No downloads match “$query”.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshStorageFolder,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final track = filtered[i];
          return YoutubeTrackTile(
            track: track,
            player: widget.player,
            allTracks: filtered,
            listIndex: i,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final searchListenable = widget.searchController;

    Widget catalogBody() {
      return ListenableBuilder(
        listenable: YoutubeLibraryCatalog.instance,
        builder: (context, _) {
          final catalog = YoutubeLibraryCatalog.instance;
          final filtered = _filterTracks(catalog.tracks);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const YoutubeActiveDownloadsBar(),
              _YoutubeLibraryFolderHeader(
                directoryPath: catalog.storageDirectoryPath,
                summaryLine: catalog.scanSummaryLine,
                loading: catalog.loading || _scanning,
              ),
              if (catalog.loading || _scanning)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _buildLibraryBody(
                  context,
                  theme,
                  pal,
                  catalog,
                  filtered,
                ),
              ),
            ],
          );
        },
      );
    }

    if (searchListenable == null) {
      return catalogBody();
    }

    return AnimatedBuilder(
      animation: searchListenable,
      builder: (context, _) => catalogBody(),
    );
  }
}

/// Saved YouTube search bookmarks — filtered by the hub search field.
class YoutubeBookmarksTab extends StatefulWidget {
  const YoutubeBookmarksTab({super.key, this.searchController});

  final TextEditingController? searchController;

  @override
  State<YoutubeBookmarksTab> createState() => _YoutubeBookmarksTabState();
}

class _YoutubeBookmarksTabState extends State<YoutubeBookmarksTab> {
  List<YoutubeTrack> _bookmarks = const [];
  var _loading = true;
  Set<String> _downloadedVideoIds = const {};
  VoidCallback? _bookmarkRevisionListener;

  @override
  void initState() {
    super.initState();
    YoutubeDownloadManager.instance.addListener(_onDownloadsChanged);
    _bookmarkRevisionListener = () => unawaited(_reloadBookmarks());
    YoutubeBookmarkStore.revision.addListener(_bookmarkRevisionListener!);
    unawaited(_reloadBookmarks());
    unawaited(_refreshDownloadedIds());
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.removeListener(_onDownloadsChanged);
    if (_bookmarkRevisionListener != null) {
      YoutubeBookmarkStore.revision.removeListener(_bookmarkRevisionListener!);
    }
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshDownloadedIds());
  }

  Future<void> _reloadBookmarks() async {
    final tracks = await YoutubeBookmarkStore.loadAll();
    if (!mounted) return;
    setState(() {
      _bookmarks = tracks;
      _loading = false;
    });
  }

  Future<void> _refreshDownloadedIds() async {
    final ids = await YoutubeTrackStore.instance.downloadedVideoIds();
    if (!mounted) return;
    setState(() => _downloadedVideoIds = ids);
  }

  List<YoutubeTrack> _filteredBookmarks() {
    final q = widget.searchController?.text.trim().toLowerCase() ?? '';
    if (q.isEmpty) return _bookmarks;
    return _bookmarks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  Future<void> _playBookmark(int index, List<YoutubeTrack> visible) async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    try {
      await playYoutubeSearchResult(
        context: context,
        player: player,
        results: visible,
        index: index,
      );
    } catch (e, st) {
      debugPrint('YoutubeBookmarksTab._playBookmark: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play: $e')),
      );
    }
  }

  Future<void> _handleMenuAction(
    _YoutubeSearchMenuAction action,
    int index,
    List<YoutubeTrack> visible,
  ) async {
    if (!mounted || index < 0 || index >= visible.length) return;
    final yt = visible[index];
    final player = PlayerController.of(context);

    switch (action) {
      case _YoutubeSearchMenuAction.bookmark:
        final added = await YoutubeBookmarkStore.toggle(yt);
        if (!mounted) return;
        ActionPillToast.show(
          context,
          added ? 'Bookmarked' : 'Bookmark removed',
          icon: added ? Icons.bookmark : Icons.bookmark_border,
          uppercaseLabel: true,
        );
        return;

      case _YoutubeSearchMenuAction.download:
        if (_downloadedVideoIds.contains(yt.videoId)) return;
        try {
          await YoutubeDownloadManager.instance.enqueue(yt);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloading "${yt.title}"')),
          );
        } on StateError catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
        return;

      case _YoutubeSearchMenuAction.playNext:
      case _YoutubeSearchMenuAction.addToQueue:
      case _YoutubeSearchMenuAction.playOnly:
        final item = await trackItemForYoutubeSearchTrack(yt);
        if (!mounted) return;
        if (item == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not queue this track')),
          );
          return;
        }
        player.setPlaybackPathKeyScope(null, reloadQueue: false);
        switch (action) {
          case _YoutubeSearchMenuAction.playNext:
            final queued = await player.playTrackNext(
              item,
              playbackOriginTab: LibraryTabId.youtubeSearch,
            );
            if (!mounted) return;
            ActionPillToast.show(
              context,
              queued ? 'Queued as next' : 'Already in queue',
              icon: Icons.queue_play_next_rounded,
              uppercaseLabel: true,
            );
          case _YoutubeSearchMenuAction.addToQueue:
            final queued = await player.addToPlaylistIfAbsent(item);
            if (!mounted) return;
            ActionPillToast.show(
              context,
              queued ? 'Added to queue' : 'Already in queue',
              icon: Icons.playlist_add_rounded,
              uppercaseLabel: true,
            );
          case _YoutubeSearchMenuAction.playOnly:
            await player.setPlaylistAndPlay(
              [item],
              playbackOriginTab: LibraryTabId.youtubeSearch,
            );
          case _YoutubeSearchMenuAction.bookmark:
          case _YoutubeSearchMenuAction.download:
            break;
        }
    }
  }

  Widget _buildBody(ThemeData theme, AppPalette pal) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: pal.accent),
      );
    }

    final visible = _filteredBookmarks();
    final query = widget.searchController?.text.trim() ?? '';

    if (_bookmarks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Bookmarked videos from Find appear here.\n'
            'Use ⋮ on a search result and choose Bookmark.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary,
            ),
          ),
        ),
      );
    }

    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            query.isEmpty
                ? 'No bookmarks match.'
                : 'No bookmarks match “$query”.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: pal.dividerOnHero.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, i) {
        final t = visible[i];
        final downloaded = _downloadedVideoIds.contains(t.videoId);
        final job = YoutubeDownloadManager.instance.jobForVideoId(t.videoId);
        return _YoutubeSearchResultTile(
          track: t,
          downloaded: downloaded,
          bookmarked: true,
          job: job,
          onTap: () => unawaited(_playBookmark(i, visible)),
          onMenuAction: (action) =>
              unawaited(_handleMenuAction(action, i, visible)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final searchListenable = widget.searchController;

    Widget body() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const YoutubeActiveDownloadsBar(),
          Expanded(child: _buildBody(theme, pal)),
        ],
      );
    }

    if (searchListenable == null) {
      return body();
    }

    return AnimatedBuilder(
      animation: searchListenable,
      builder: (context, _) => body(),
    );
  }
}
