import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../theme/app_theme.dart';
import '../catalog/youtube_library_catalog.dart';
import '../catalog/youtube_storage_scan.dart';
import '../download/youtube_download_job.dart';
import '../download/youtube_download_manager.dart';
import '../models/youtube_track.dart';
import '../search/youtube_channel_browse.dart';
import '../search/youtube_channel_query.dart';
import '../search/youtube_search_history_status.dart';
import '../search/youtube_search_history_store.dart';
import '../search/youtube_search_service.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_duration_format.dart';
import '../youtube_track_delete.dart';
import 'youtube_delete_confirm.dart';
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
      _ownedQueryController = TextEditingController();
    }
    YoutubeDownloadManager.instance.addListener(_onDownloadsChanged);
    unawaited(_refreshDownloadedIds());
    unawaited(_loadSearchHistory());
  }

  Future<void> _loadSearchHistory() async {
    final history = await YoutubeSearchHistoryStore.load();
    if (!mounted) return;
    setState(() => _searchHistory = history);
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.removeListener(_onDownloadsChanged);
    _ownedQueryController?.dispose();
    super.dispose();
  }

  void _setSearching(bool value) {
    widget.onSearchingChanged?.call(value);
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshDownloadedIds());
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
                        decoration: InputDecoration(
                          hintText: '@channel · title or artist',
                          isDense: true,
                          filled: true,
                          fillColor: pal.onScaffold.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => unawaited(runSearch()),
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
          job: job,
          onDownload: () => unawaited(_download(t)),
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

class _YoutubeSearchResultTile extends StatelessWidget {
  const _YoutubeSearchResultTile({
    required this.track,
    required this.downloaded,
    required this.job,
    required this.onDownload,
  });

  final YoutubeTrack track;
  final bool downloaded;
  final YoutubeDownloadJob? job;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
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
        trailing: _SearchDownloadTrailing(
          downloaded: downloaded,
          job: job,
          onDownload: onDownload,
        ),
      ),
    );
  }
}

class _SearchDownloadTrailing extends StatelessWidget {
  const _SearchDownloadTrailing({
    required this.downloaded,
    required this.job,
    required this.onDownload,
  });

  final bool downloaded;
  final YoutubeDownloadJob? job;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (downloaded) {
      return Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    final active = job;
    if (active != null &&
        active.state != YoutubeDownloadState.failed &&
        active.state != YoutubeDownloadState.cancelled &&
        active.state != YoutubeDownloadState.complete) {
      return SizedBox(
        width: 36,
        height: 36,
        child: active.state == YoutubeDownloadState.downloading
            ? CircularProgressIndicator(value: active.progress, strokeWidth: 2.5)
            : const CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    if (active?.state == YoutubeDownloadState.failed) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Retry download',
        onPressed: () => YoutubeDownloadManager.instance.retry(active!.videoId),
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Download',
      onPressed: onDownload,
    );
  }
}

class YoutubeLibraryTab extends StatefulWidget {
  const YoutubeLibraryTab({
    super.key,
    required this.player,
    this.onOpenSearch,
  });

  final PlayerController player;
  final VoidCallback? onOpenSearch;

  @override
  State<YoutubeLibraryTab> createState() => _YoutubeLibraryTabState();
}

class _YoutubeLibraryTabState extends State<YoutubeLibraryTab> {
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    YoutubeDownloadManager.instance.lastCompletedJob.addListener(
      _onDownloadCompleted,
    );
    unawaited(_refreshStorageFolder());
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.lastCompletedJob.removeListener(
      _onDownloadCompleted,
    );
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
      await scanYoutubeStorageFolder();
    } catch (e, st) {
      debugPrint('YoutubeLibraryTab scan: $e\n$st');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _openSearch(BuildContext context) {
    final open = widget.onOpenSearch;
    if (open != null) {
      open();
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const YoutubeSearchScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return ListenableBuilder(
      listenable: YoutubeLibraryCatalog.instance,
      builder: (context, _) {
        final catalog = YoutubeLibraryCatalog.instance;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const YoutubeActiveDownloadsBar(),
                if (catalog.loading || _scanning)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: catalog.tracks.isEmpty
                      ? RefreshIndicator(
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
                                      'pull down to refresh, or open the Find tab to download tracks.',
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
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshStorageFolder,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: catalog.tracks.length,
                            itemBuilder: (context, i) {
                              final track = catalog.tracks[i];
                              return YoutubeTrackTile(
                                track: track,
                                player: widget.player,
                                allTracks: catalog.tracks,
                                onDelete: (t) async {
                                  final path = t.filePath;
                                  if (path == null) return;
                                  if (!context.mounted) return;
                                  final ok = await confirmDeleteYoutubeDownload(
                                    context,
                                    t,
                                  );
                                  if (!ok || !context.mounted) return;
                                  await deleteYoutubeDownload(
                                    player: widget.player,
                                    filePath: path,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Deleted "${t.title}"'),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openSearch(context),
                icon: const Icon(Icons.search),
                label: const Text('Find'),
              ),
            ),
          ],
        );
      },
    );
  }
}
