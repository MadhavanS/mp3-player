import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../models/youtube_page_id.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/daisy_background.dart';
import '../../help/search_help_text.dart';
import '../catalog/youtube_library_catalog.dart';
import '../youtube_home_store.dart';
import 'youtube_search_screen.dart';

/// YouTube section (sidebar): downloaded library + Find, with shared search state.
class YoutubeHubScreen extends StatefulWidget {
  const YoutubeHubScreen({super.key, required this.onOpenDrawer});

  final VoidCallback onOpenDrawer;

  @override
  State<YoutubeHubScreen> createState() => YoutubeHubScreenState();
}

class YoutubeHubScreenState extends State<YoutubeHubScreen>
    with TickerProviderStateMixin {
  static const List<YoutubePageId> _pages = [
    YoutubePageId.library,
    YoutubePageId.find,
    YoutubePageId.bookmarks,
  ];

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<YoutubeSearchTabState> _findTabKey = GlobalKey();
  bool _findSearchBusy = false;
  Timer? _searchPersistDebounce;

  YoutubePageId get _currentPage =>
      _pages[_tabController.index.clamp(0, _pages.length - 1)];

  bool get _onFindPage => _currentPage == YoutubePageId.find;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _pages.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_onSearchTextChanged);
    unawaited(_loadPersistedState());
    if (!kIsWeb) {
      unawaited(YoutubeLibraryCatalog.instance.reload());
    }
  }

  Future<void> _loadPersistedState() async {
    final results = await Future.wait([
      YoutubeHomeStore.loadDefaultPage(),
      YoutubeHomeStore.loadSearchText(),
    ]);
    if (!mounted) return;
    final defaultPage = results[0] as YoutubePageId;
    final searchText = results[1] as String;
    if (searchText.isNotEmpty) {
      _searchController.text = searchText;
    }
    final ix = _pages.indexOf(defaultPage);
    if (ix >= 0 && _tabController.index != ix) {
      _tabController.index = ix;
    }
    setState(() {});
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {}); // Refresh search hint and library filter.
    }
  }

  void _onSearchTextChanged() {
    _onSearchTextChangedForTabs();
    _searchPersistDebounce?.cancel();
    _searchPersistDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(YoutubeHomeStore.saveSearchText(_searchController.text));
    });
  }

  /// Opens a sub-page (e.g. after download FAB or Now Playing return).
  void switchToPage(YoutubePageId page) {
    if (!mounted) return;
    final ix = _pages.indexOf(page);
    if (ix < 0) return;
    if (_tabController.index != ix) {
      _tabController.index = ix;
    }
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    unawaited(YoutubeHomeStore.saveSearchText(''));
    if (_onFindPage) {
      _findTabKey.currentState?.clearResults();
    }
    setState(() {});
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Library tab filters downloads locally; Find tab searches YouTube online.
  void _submitSearch() {
    if (_onFindPage) {
      unawaited(_findTabKey.currentState?.runSearch());
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String get _searchHint {
    switch (_currentPage) {
      case YoutubePageId.find:
        return SearchHelpText.youtubeFindFieldHint;
      case YoutubePageId.bookmarks:
        return SearchHelpText.youtubeBookmarksFieldHint;
      case YoutubePageId.library:
        return SearchHelpText.youtubeLibraryFieldHint;
    }
  }

  InputDecoration _searchDecoration(AppPalette pal, ThemeData theme) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final showSuffix = hasQuery || (_onFindPage && _findSearchBusy);
    return InputDecoration(
      hintText: _searchHint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: pal.textMuted.withValues(alpha: 0.72),
      ),
      isDense: true,
      filled: true,
      fillColor: pal.onScaffold.withValues(alpha: 0.1),
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
              width: hasQuery && _onFindPage && _findSearchBusy ? 88 : 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_onFindPage && _findSearchBusy)
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
                      onPressed: _clearSearch,
                    ),
                ],
              ),
            )
          : null,
    );
  }

  void _onSearchTextChangedForTabs() {
    if (!_onFindPage) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchPersistDebounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);

    return DaisyBackground(
      baseColor: pal.scaffoldBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    color: pal.onScaffold,
                    tooltip: 'Open menu',
                    onPressed: widget.onOpenDrawer,
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _searchController,
                      builder: (context, _) {
                        return TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitSearch(),
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: pal.onScaffold,
                            fontSize: 15,
                          ),
                          decoration: _searchDecoration(pal, theme),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: switch (_currentPage) {
                      YoutubePageId.find => 'Search YouTube',
                      YoutubePageId.bookmarks => 'Filter bookmarks',
                      YoutubePageId.library => 'Filter downloads',
                    },
                    onPressed:
                        _onFindPage && _findSearchBusy ? null : _submitSearch,
                    icon: Icon(Icons.search_rounded, color: pal.onScaffold),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: pal.onScaffold,
              unselectedLabelColor: pal.textMuted,
              indicatorColor: context.controlAccent,
              dividerColor: pal.dividerOnHero.withValues(alpha: 0.35),
              tabs: [for (final p in _pages) Tab(text: p.title)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _KeepAliveTab(
                    child: YoutubeLibraryTab(
                      player: player,
                      searchController: _searchController,
                    ),
                  ),
                  _KeepAliveTab(
                    child: YoutubeSearchTab(
                      key: _findTabKey,
                      searchController: _searchController,
                      onSearchingChanged: (busy) {
                        if (!mounted) return;
                        setState(() => _findSearchBusy = busy);
                      },
                    ),
                  ),
                  _KeepAliveTab(
                    child: YoutubeBookmarksTab(
                      searchController: _searchController,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
