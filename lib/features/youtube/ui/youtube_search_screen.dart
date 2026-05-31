import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../theme/app_theme.dart';
import '../catalog/youtube_library_catalog.dart';
import '../download/youtube_download_manager.dart';
import '../models/youtube_track.dart';
import '../search/youtube_search_service.dart';
import 'youtube_download_sheet.dart';
import 'youtube_track_tile.dart';

class YoutubeSearchScreen extends StatefulWidget {
  const YoutubeSearchScreen({super.key});

  @override
  State<YoutubeSearchScreen> createState() => _YoutubeSearchScreenState();
}

class _YoutubeSearchScreenState extends State<YoutubeSearchScreen> {
  final _queryController = TextEditingController();
  var _searching = false;
  List<YoutubeTrack> _results = const [];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _results = const [];
    });
    final results = await YoutubeSearchService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
    });
  }

  Future<void> _download(YoutubeTrack track) async {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find on YouTube'),
      ),
      body: Column(
        children: [
          const YoutubeActiveDownloadsBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      hintText: 'Search songs, artists…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_runSearch()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _searching ? null : () => unawaited(_runSearch()),
                  icon: _searching
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _searching ? 'Searching…' : 'Search for music to download',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: pal.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: pal.dividerOnHero.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (context, i) {
                      final t = _results[i];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: t.thumbnailUrl != null
                              ? Image.network(
                                  t.thumbnailUrl!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.music_video_outlined),
                                )
                              : const Icon(Icons.music_video_outlined),
                          title: Text(
                            t.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(t.artist, maxLines: 1),
                          trailing: IconButton(
                            icon: const Icon(Icons.download_outlined),
                            tooltip: 'Download',
                            onPressed: () => unawaited(_download(t)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class YoutubeLibraryTab extends StatelessWidget {
  const YoutubeLibraryTab({super.key, required this.player});

  final PlayerController player;

  Future<void> _openSearch(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const YoutubeSearchScreen()),
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
                if (catalog.loading)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: catalog.tracks.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Downloaded YouTube audio appears here.\n'
                              'Tap Find on YouTube to search and save tracks for offline playback.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: pal.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: catalog.tracks.length,
                          itemBuilder: (context, i) {
                            final track = catalog.tracks[i];
                            return YoutubeTrackTile(
                              track: track,
                              player: player,
                              allTracks: catalog.tracks,
                              onDelete: (t) async {
                                final path = t.filePath;
                                if (path == null) return;
                                await deleteYoutubeTrackByPath(path);
                                await YoutubeLibraryCatalog.instance.reload();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => unawaited(_openSearch(context)),
                icon: const Icon(Icons.add),
                label: const Text('Find on YouTube'),
              ),
            ),
          ],
        );
      },
    );
  }
}
