import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../theme/app_theme.dart';
import '../player/track_overflow_actions.dart';
import 'library_files_explorer.dart';

/// Full-screen Files browser (opened from drawer). Not embedded in Library tabs.
class LibraryFilesPage extends StatefulWidget {
  const LibraryFilesPage({
    super.key,
    required this.musicRoots,
    required this.onOverflow,
  });

  final List<String> musicRoots;

  final Future<void> Function(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    LibraryTabId? playbackOriginTab,
    TrackOverflowQueueContext? outsideQueue,
  }) onOverflow;

  @override
  State<LibraryFilesPage> createState() => _LibraryFilesPageState();
}

class _LibraryFilesPageState extends State<LibraryFilesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  InputDecoration _searchDecoration(AppPalette pal, ThemeData theme) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return InputDecoration(
      hintText: 'Search folders & titles',
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: pal.textMuted.withValues(alpha: 0.72),
      ),
      isDense: true,
      filled: true,
      fillColor: pal.onScaffold.withValues(alpha: 0.1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: pal.textMuted.withValues(alpha: 0.9),
        size: 22,
      ),
      suffixIcon: hasQuery
          ? IconButton(
              tooltip: 'Clear search',
              icon: Icon(
                Icons.close_rounded,
                color: pal.onScaffold.withValues(alpha: 0.75),
                size: 20,
              ),
              onPressed: () {
                _searchController.clear();
                FocusScope.of(context).unfocus();
              },
            )
          : null,
    );
  }

  Future<void> _onSongChosenFromExplorer(Set<String>? pathKeys) async {
    if (!context.mounted) return;
    Navigator.of(context).pop(pathKeys);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final q = _searchController.text.trim();

    return Scaffold(
      backgroundColor: pal.scaffoldBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Close',
                    color: pal.onScaffold,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      keyboardType: TextInputType.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: pal.onScaffold,
                        fontSize: 15,
                      ),
                      decoration: _searchDecoration(pal, theme),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LibraryFilesExplorer(
                musicRoots: widget.musicRoots,
                query: q,
                onOverflow: widget.onOverflow,
                onSongChosenFromExplorer: _onSongChosenFromExplorer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
