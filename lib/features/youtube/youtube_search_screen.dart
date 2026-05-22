import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../features/player/mini_player_bar.dart';
import '../../features/player/now_playing_screen.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../models/youtube_channel_ref.dart';
import '../../services/saved_youtube_audio_store.dart';
import '../../services/youtube_audio_download_controller.dart';
import '../../services/youtube_channel_resolver.dart';
import '../../services/saved_youtube_links_store.dart';
import '../../services/youtube_search_history_store.dart';
import '../../services/youtube_search_service.dart';
import 'saved_youtube_audio_info.dart';
import 'youtube_save_audio_dialog.dart';
import '../../theme/app_theme.dart';
import '../../util/format_bytes.dart';
import '../../widgets/action_pill_toast.dart';
import '../../widgets/daisy_background.dart';

/// Online YouTube search (via [ytClient]) with playback through [PlayerController].
class YoutubeSearchScreen extends StatefulWidget {
  const YoutubeSearchScreen({
    super.key,
    required this.onBack,
    this.initialChannel,
  });

  final VoidCallback onBack;

  /// When set, opens on the Search tab with this channel selected and uploads listed.
  final YoutubeChannelRef? initialChannel;

  @override
  State<YoutubeSearchScreen> createState() => _YoutubeSearchScreenState();
}

class _YoutubeSearchScreenState extends State<YoutubeSearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _channelController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final TabController _tabController;

  YoutubeChannelRef? _selectedChannel;
  List<YoutubeChannelRef> _channelSuggestions = [];
  String? _channelSearchHint;
  Timer? _channelDebounce;
  int _latestChannelRequest = 0;

  List<TrackItem> _results = [];
  List<String> _suggestions = [];
  List<TrackItem> _savedAudio = [];
  List<TrackItem> _savedLinks = [];
  bool _searching = false;
  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  String? _errorMessage;

  /// Last query that produced [_results] (for related suggestions).
  String _submittedQuery = '';

  List<YoutubeSearchHistoryEntry> _searchHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_reloadSavedLibraries());
    unawaited(_loadSearchHistory());
    SavedYoutubeAudioStore.revision.addListener(_onSavedStoresChanged);
    SavedYoutubeLinksStore.revision.addListener(_onSavedStoresChanged);
    YoutubeSearchHistoryStore.revision.addListener(_onSearchHistoryChanged);
    final initial = widget.initialChannel;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectChannel(initial);
      });
    }
  }

  void _onSavedStoresChanged() => unawaited(_reloadSavedLibraries());

  void _onSearchHistoryChanged() => unawaited(_loadSearchHistory());

  Future<void> _loadSearchHistory() async {
    final items = await YoutubeSearchHistoryStore.load();
    if (!mounted) return;
    setState(() => _searchHistory = items);
  }

  @override
  void dispose() {
    SavedYoutubeAudioStore.revision.removeListener(_onSavedStoresChanged);
    SavedYoutubeLinksStore.revision.removeListener(_onSavedStoresChanged);
    YoutubeSearchHistoryStore.revision.removeListener(_onSearchHistoryChanged);
    _tabController.dispose();
    _debounce?.cancel();
    _channelDebounce?.cancel();
    _queryController.dispose();
    _channelController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectChannel(YoutubeChannelRef channel) {
    setState(() {
      _selectedChannel = channel;
      _channelController.text = channel.title;
      _channelSuggestions = [];
      _channelSearchHint = null;
    });
    unawaited(_runSearch());
  }

  void _clearChannel() {
    setState(() {
      _selectedChannel = null;
      _channelController.clear();
      _channelSuggestions = [];
      _channelSearchHint = null;
    });
  }

  Future<void> _saveTrackAudio(TrackItem track) async {
    final ok = await showYoutubeSaveAudioDialog(context, track);
    if (!mounted) return;
    if (ok) await _reloadSavedLibraries();
  }

  Future<void> _reloadSavedLibraries() async {
    final audio = await SavedYoutubeAudioStore.load();
    final links = await SavedYoutubeLinksStore.load();
    if (!mounted) return;
    setState(() {
      _savedAudio = audio;
      _savedLinks = links;
    });
  }

  List<String> get _relevantSuggestions {
    final q = _queryController.text.trim();
    if (q.isEmpty || _suggestions.isEmpty) return [];
    final ql = q.toLowerCase();
    return _suggestions.where((s) {
      final sl = s.toLowerCase();
      if (sl.contains(ql) || ql.contains(sl)) return true;
      final qWords = ql.split(RegExp(r'\s+')).where((w) => w.length > 1);
      return qWords.every((w) => sl.contains(w));
    }).take(8).toList();
  }

  Future<void> _runSearch([String? query]) async {
    if (query != null) {
      _queryController.text = query;
      _queryController.selection = TextSelection.fromPosition(
        TextPosition(offset: _queryController.text.length),
      );
    }

    final q = _queryController.text.trim();
    _latestSuggestionRequest++;
    _debounce?.cancel();

    final channel = _selectedChannel;

    if (q.isEmpty && channel == null) {
      setState(() {
        _results = [];
        _suggestions = [];
        _submittedQuery = '';
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _errorMessage = null;
      _submittedQuery = q;
    });
    _focusNode.unfocus();

    final List<TrackItem> results;
    if (channel != null) {
      results = await YoutubeSearchService.instance.searchVideosInChannel(
        channelId: channel.id,
        query: q,
      );
    } else {
      results = await YoutubeSearchService.instance.searchVideos(q);
    }
    if (!mounted) return;

    setState(() {
      _searching = false;
      _results = results;
      if (results.isEmpty) {
        _errorMessage = channel != null
            ? (q.isEmpty
                ? 'No uploads found for this channel.'
                : 'No matches in this channel. Try another term.')
            : 'No results. Check your connection or try another query.';
      }
    });

    unawaited(
      YoutubeSearchHistoryStore.recordSearch(
        query: q,
        channelId: channel?.id,
        channelTitle: channel?.title,
      ),
    );
    unawaited(_refreshSuggestionsForQuery(q));
  }

  Future<void> _applyHistoryEntry(YoutubeSearchHistoryEntry entry) async {
    final cid = entry.channelId?.trim() ?? '';
    if (cid.isNotEmpty) {
      setState(() {
        _selectedChannel = YoutubeChannelRef(
          id: cid,
          title: entry.channelTitle?.trim().isNotEmpty == true
              ? entry.channelTitle!.trim()
              : cid,
        );
        _channelController.text = _selectedChannel!.title;
        _channelSuggestions = [];
        _channelSearchHint = null;
      });
    } else {
      _clearChannel();
    }
    _queryController.text = entry.query;
    _queryController.selection = TextSelection.fromPosition(
      TextPosition(offset: _queryController.text.length),
    );
    await _runSearch();
  }

  Future<void> _refreshSuggestionsForQuery(String query) async {
    final requestId = ++_latestSuggestionRequest;
    final items =
        await YoutubeSearchService.instance.querySuggestions(query);
    if (!mounted ||
        requestId != _latestSuggestionRequest ||
        _queryController.text.trim() != query) {
      return;
    }
    setState(() => _suggestions = items);
  }

  Future<void> _onSearchQueueAction(
    _SearchQueueAction action,
    List<TrackItem> all,
    int index,
  ) async {
    if (index < 0 || index >= all.length) return;
    final track = all[index];
    final player = PlayerController.of(context);

    switch (action) {
      case _SearchQueueAction.playNext:
        final next = await player.playTrackNext(
          track,
          playbackOriginTab: LibraryTabId.onlineSearch,
        );
        if (!mounted) return;
        ActionPillToast.show(
          context,
          next ? 'Queued as next' : 'Already playing',
          icon: Icons.queue_play_next_rounded,
        );
      case _SearchQueueAction.addToQueue:
        final added = await player.addToPlaylistIfAbsent(track);
        if (!mounted) return;
        ActionPillToast.show(
          context,
          added ? 'Added to queue' : 'Already in queue',
          icon: Icons.queue_music_rounded,
        );
      case _SearchQueueAction.playFromHere:
        await _playTracks(all.sublist(index), 0);
      case _SearchQueueAction.playOnlyThis:
        await _playTracks([track], 0);
    }
  }

  Future<void> _playTracks(List<TrackItem> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    final player = PlayerController.of(context);
    try {
      await player.setPlaylistAndPlay(
        tracks,
        startIndex: startIndex.clamp(0, tracks.length - 1),
        playbackOriginTab: LibraryTabId.onlineSearch,
      );
    } catch (_) {
      if (!mounted) return;
      ActionPillToast.show(context, 'Could not start playback');
    }
  }

  void _openNowPlaying() {
    final player = PlayerController.of(context);
    if (player.currentTrack == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NowPlayingScreen(
              onCollapse: () => Navigator.of(context).pop(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);
    final relevant = _relevantSuggestions;

    return Scaffold(
      backgroundColor: pal.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Online search'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Search'),
            Tab(
              text: _savedAudio.isEmpty
                  ? 'Saved audio'
                  : 'Saved audio (${_savedAudio.length})',
            ),
            Tab(
              text: _savedLinks.isEmpty
                  ? 'Saved links'
                  : 'Saved links (${_savedLinks.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: DaisyBackground(
              baseColor: pal.scaffoldBackground,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSearchTab(context, theme, pal, relevant),
                  _SavedTracksTab(
                    emptyMessage:
                        'No saved audio yet.\nUse Save audio in Now Playing.',
                    tracks: _savedAudio,
                    leadingIcon: Icons.download_done_rounded,
                    onPlay: (track, index, all) =>
                        _playTracks(all, index),
                    onRemove: (id) async {
                      await SavedYoutubeAudioStore.remove(id);
                      await _reloadSavedLibraries();
                    },
                    onSaveAudio: (track) =>
                        showYoutubeSaveAudioDialog(context, track),
                    showSaveAudioAction: false,
                  ),
                  _SavedTracksTab(
                    emptyMessage:
                        'No saved links yet.\nBookmark a track in Now Playing.',
                    tracks: _savedLinks,
                    leadingIcon: Icons.bookmark_rounded,
                    onPlay: (track, index, all) =>
                        _playTracks(all, index),
                    onRemove: (id) async {
                      await SavedYoutubeLinksStore.remove(id);
                      await _reloadSavedLibraries();
                    },
                    onSaveAudio: kIsWeb
                        ? null
                        : (track) => _saveTrackAudio(track),
                    showSaveAudioAction: false,
                  ),
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: YoutubeAudioDownloadController.instance,
            builder: (context, _) {
              final dl = YoutubeAudioDownloadController.instance;
              if (!dl.isRunning) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: dl.progress?.clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dl.status,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pal.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) {
              if (player.currentTrack == null) {
                return const SizedBox.shrink();
              }
              return MiniPlayerBar(
                controller: player,
                onTap: _openNowPlaying,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab(
    BuildContext context,
    ThemeData theme,
    AppPalette pal,
    List<String> relevant,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Material(
            color: pal.onScaffold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            child: TextField(
              controller: _channelController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Channel: @name, UC…, or channel URL',
                prefixIcon: const Icon(Icons.account_circle_outlined),
                suffixIcon: (_selectedChannel != null ||
                        _channelController.text.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearChannel,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                if (_selectedChannel != null &&
                    value.trim() != _selectedChannel!.title) {
                  setState(() => _selectedChannel = null);
                }
                setState(() {});
                _channelDebounce?.cancel();
                final requestId = ++_latestChannelRequest;
                if (value.trim().isEmpty) {
                  setState(() {
                    _channelSuggestions = [];
                    _channelSearchHint = null;
                  });
                  return;
                }
                _channelDebounce = Timer(
                  const Duration(milliseconds: 800),
                  () async {
                    final resolver = YoutubeChannelResolver.instance;
                    if (YoutubeChannelResolver.isDirectChannelInput(value)) {
                      final resolved =
                          await resolver.resolveChannelInput(value);
                      if (!mounted ||
                          requestId != _latestChannelRequest ||
                          _channelController.text != value) {
                        return;
                      }
                      if (resolved != null) {
                        _selectChannel(resolved);
                        return;
                      }
                      setState(() {
                        _channelSearchHint = resolver.lastChannelSearchError;
                        _channelSuggestions = [];
                      });
                      return;
                    }

                    final suggestions =
                        await resolver.searchChannels(value);
                    if (!mounted ||
                        requestId != _latestChannelRequest ||
                        _channelController.text != value) {
                      return;
                    }
                    setState(() {
                      _channelSuggestions = suggestions;
                      _channelSearchHint = resolver.lastChannelSearchError ??
                          (suggestions.isEmpty && value.trim().length >= 3
                              ? 'No channels found — try @handle or UC id'
                              : null);
                    });
                  },
                );
              },
              onSubmitted: (value) async {
                final resolver = YoutubeChannelResolver.instance;
                final resolved = await resolver.resolveChannelInput(value);
                if (!mounted) return;
                if (resolved != null) {
                  _selectChannel(resolved);
                  return;
                }
                setState(() {
                  _channelSearchHint = resolver.lastChannelSearchError ??
                      'Could not resolve channel';
                });
              },
            ),
          ),
        ),
        if (_selectedChannel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.verified_outlined, size: 18),
                label: Text('In: ${_selectedChannel!.title}'),
                onDeleted: _clearChannel,
              ),
            ),
          ),
        if (_channelSearchHint != null && _selectedChannel == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              _channelSearchHint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted,
              ),
            ),
          ),
        if (_channelSuggestions.isNotEmpty && _selectedChannel == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _channelSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final ch = _channelSuggestions[i];
                  return ActionChip(
                    avatar: ch.thumbnailUrl != null
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(ch.thumbnailUrl!),
                          )
                        : null,
                    label: Text(ch.title),
                    onPressed: () => _selectChannel(ch),
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            color: pal.onScaffold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            child: TextField(
              controller: _queryController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _selectedChannel != null
                    ? 'Search in ${_selectedChannel!.title}…'
                    : 'Search songs on YouTube…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _queryController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _queryController.clear();
                          setState(() {
                            _results = [];
                            _suggestions = [];
                            _submittedQuery = '';
                            _errorMessage = null;
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 14,
                ),
              ),
              onChanged: (value) {
                setState(() {});
                _debounce?.cancel();
                final requestId = ++_latestSuggestionRequest;
                if (value.trim().isEmpty) {
                  setState(() => _suggestions = []);
                  return;
                }
                _debounce = Timer(
                  const Duration(milliseconds: 350),
                  () async {
                    final items = await YoutubeSearchService.instance
                        .querySuggestions(value);
                    if (!mounted ||
                        requestId != _latestSuggestionRequest ||
                        _queryController.text != value) {
                      return;
                    }
                    setState(() => _suggestions = items);
                  },
                );
              },
              onSubmitted: (_) => _runSearch(),
            ),
          ),
        ),
        if (relevant.isNotEmpty)
          _SuggestionStrip(
            title: _results.isEmpty
                ? 'Suggestions'
                : 'Related to your search',
            suggestions: relevant,
            onTap: _runSearch,
          ),
        if (relevant.isEmpty &&
            _queryController.text.trim().isEmpty &&
            _searchHistory.isNotEmpty)
          _SearchHistoryStrip(
            entries: _searchHistory,
            onTap: (e) => unawaited(_applyHistoryEntry(e)),
          ),
        Expanded(child: _buildResultsBody(context, theme, pal)),
      ],
    );
  }

  Widget _buildResultsBody(
    BuildContext context,
    ThemeData theme,
    AppPalette pal,
  ) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary,
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final channel = _selectedChannel;
      return Center(
        child: Text(
          _submittedQuery.isEmpty
              ? (channel != null
                  ? 'Search within ${channel.title}, or press Search to browse uploads.'
                  : 'Search for music to stream from YouTube.')
              : 'No results for “$_submittedQuery”.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: pal.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = _results[index];
        return _YoutubeResultTile(
          track: track,
          onTap: () => _playTracks(_results, index),
          onQueueAction: (action) =>
              unawaited(_onSearchQueueAction(action, _results, index)),
        );
      },
    );
  }
}

class _SearchHistoryStrip extends StatelessWidget {
  const _SearchHistoryStrip({
    required this.entries,
    required this.onTap,
  });

  final List<YoutubeSearchHistoryEntry> entries;
  final void Function(YoutubeSearchHistoryEntry entry) onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent searches',
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
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 18),
                  label: Text(
                    e.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => onTap(e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.title,
    required this.suggestions,
    required this.onTap,
  });

  final String title;
  final List<String> suggestions;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
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
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = suggestions[i];
                return ActionChip(
                  label: Text(
                    s,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => onTap(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedTracksTab extends StatelessWidget {
  const _SavedTracksTab({
    required this.emptyMessage,
    required this.tracks,
    required this.leadingIcon,
    required this.onPlay,
    required this.onRemove,
    this.onSaveAudio,
    this.showSaveAudioAction = true,
  });

  final String emptyMessage;
  final List<TrackItem> tracks;
  final IconData leadingIcon;
  final void Function(TrackItem track, int index, List<TrackItem> all) onPlay;
  final Future<void> Function(String videoId) onRemove;
  final Future<void> Function(TrackItem track)? onSaveAudio;
  final bool showSaveAudioAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: pal.textMuted),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: SavedYoutubeAudioStore.revision,
      builder: (context, _) {
        return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final id = track.youtubeVideoId ?? '';
        return _SavedTrackTile(
          track: track,
          leadingIcon: leadingIcon,
          isDeviceAudio:
              track.filePath != null && track.filePath!.isNotEmpty,
          onPlay: () => onPlay(track, index, tracks),
          onRemove: id.isEmpty ? null : () => onRemove(id),
          onShowInfo: () {
            if (track.filePath != null && track.filePath!.isNotEmpty) {
              return showSavedYoutubeAudioInfoDialog(context, track);
            }
            return showSavedYoutubeLinkInfoDialog(context, track);
          },
          onSaveAudio: onSaveAudio != null ? () => onSaveAudio!(track) : null,
          showSaveAudioAction: showSaveAudioAction,
        );
      },
    );
      },
    );
  }
}

class _SavedTrackTile extends StatelessWidget {
  const _SavedTrackTile({
    required this.track,
    required this.leadingIcon,
    required this.isDeviceAudio,
    required this.onPlay,
    this.onRemove,
    this.onSaveAudio,
    this.onShowInfo,
    this.showSaveAudioAction = false,
  });

  final TrackItem track;
  final IconData leadingIcon;
  final bool isDeviceAudio;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;
  final Future<void> Function()? onSaveAudio;
  final Future<void> Function()? onShowInfo;
  final bool showSaveAudioAction;

  bool get _canPlay =>
      track.isPlayable &&
      (isDeviceAudio
          ? (track.filePath?.trim().isNotEmpty ?? false)
          : track.isYoutubeStream);

  Widget _subtitle(BuildContext context, ThemeData theme, AppPalette pal) {
    final fp = track.filePath?.trim();
    if (isDeviceAudio && fp != null && fp.isNotEmpty) {
      return FutureBuilder<int?>(
        future: _fileSizeBytes(fp),
        builder: (context, snap) {
          final sizeLabel =
              snap.data != null ? _formatBytes(snap.data!) : '…';
          return Text(
            '${track.artist} · $sizeLabel · Saved on device',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: pal.textMuted),
          );
        },
      );
    }
    return Text(
      '${track.artist} · Stream link · ${track.metaLine}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: pal.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);

    return Material(
      color: pal.onScaffold.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        enabled: _canPlay,
        onTap: _canPlay ? onPlay : null,
        onLongPress: onRemove,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _Thumbnail(url: track.thumbnailUrl),
        ),
        title: Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: _subtitle(context, theme, pal),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSaveAudio != null && showSaveAudioAction)
              IconButton(
                tooltip: 'Save audio',
                icon: const Icon(Icons.download_rounded),
                onPressed: () => onSaveAudio!(),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) async {
                switch (value) {
                  case 'info':
                    await onShowInfo?.call();
                  case 'download':
                    await onSaveAudio?.call();
                  case 'delete':
                    onRemove?.call();
                  case 'play':
                    if (_canPlay) onPlay();
                }
              },
              itemBuilder: (context) {
                final videoId = track.youtubeVideoId?.trim() ?? '';
                final savedOnDevice = !isDeviceAudio &&
                    videoId.isNotEmpty &&
                    SavedYoutubeAudioStore.isSaved(videoId);
                return [
                  PopupMenuItem(
                    value: 'play',
                    enabled: _canPlay,
                    child: const ListTile(
                      leading: Icon(Icons.play_arrow_rounded),
                      title: Text('Play'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (onSaveAudio != null && !isDeviceAudio)
                    PopupMenuItem(
                      value: 'download',
                      enabled: !savedOnDevice,
                      child: ListTile(
                        leading: Icon(
                          savedOnDevice
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                        ),
                        title: Text(
                          savedOnDevice
                              ? 'Already saved on device'
                              : 'Save audio to device',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (onShowInfo != null)
                    PopupMenuItem(
                      value: 'info',
                      child: ListTile(
                        leading: Icon(
                          isDeviceAudio
                              ? Icons.info_outline_rounded
                              : Icons.link_rounded,
                        ),
                        title:
                            Text(isDeviceAudio ? 'Audio info' : 'Link info'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (onRemove != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                        title: Text('Delete'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ];
              },
            ),
            Icon(leadingIcon, color: context.controlAccent, size: 22),
          ],
        ),
      ),
    );
  }

  static Future<int?> _fileSizeBytes(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.length();
    } catch (_) {
      return null;
    }
  }

  static String _formatBytes(int bytes) => formatFileSize(bytes);
}

enum _SearchQueueAction {
  playNext,
  addToQueue,
  playFromHere,
  playOnlyThis,
}

class _YoutubeResultTile extends StatelessWidget {
  const _YoutubeResultTile({
    required this.track,
    required this.onTap,
    required this.onQueueAction,
  });

  final TrackItem track;
  final VoidCallback onTap;
  final void Function(_SearchQueueAction action) onQueueAction;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);

    return Material(
      color: pal.onScaffold.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _Thumbnail(url: track.thumbnailUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: pal.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.artist} · ${track.metaLine}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pal.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SearchQueueAction>(
                tooltip: 'Queue options',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: pal.textMuted,
                  size: 22,
                ),
                onSelected: onQueueAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SearchQueueAction.playNext,
                    child: ListTile(
                      leading: Icon(Icons.queue_play_next_rounded, size: 22),
                      title: Text('Play next'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  PopupMenuItem(
                    value: _SearchQueueAction.addToQueue,
                    child: ListTile(
                      leading: Icon(Icons.queue_music_rounded, size: 22),
                      title: Text('Add to queue'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  PopupMenuItem(
                    value: _SearchQueueAction.playFromHere,
                    child: ListTile(
                      leading: Icon(Icons.playlist_play_rounded, size: 22),
                      title: Text('Play from here'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  PopupMenuItem(
                    value: _SearchQueueAction.playOnlyThis,
                    child: ListTile(
                      leading: Icon(Icons.music_note_rounded, size: 22),
                      title: Text('Play this song only'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Play',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: context.controlAccent,
                  size: 32,
                ),
                onPressed: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url, this.size = 56});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    if (u == null || u.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: context.palette.onScaffold.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded, color: context.palette.textMuted),
      );
    }
    return Image.network(
      u,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: context.palette.onScaffold.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded, color: context.palette.textMuted),
      ),
    );
  }
}
