import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../services/mp3_scanner.dart';
import '../../services/storage_access.dart';
import '../../services/track_metadata.dart';
import '../player/mini_player_bar.dart';
import '../player/now_playing_screen.dart';

const String kLibraryMainTitle = 'Poll, Top Tracks this Week';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _folderPath;
  bool _scanning = false;

  String get _playingSourceSubtitle {
    if (_folderPath != null) {
      return '${p.basename(_folderPath!)}, All Genres';
    }
    return 'Choose a music folder';
  }

  Future<void> _pickAndScanFolder() async {
    final allowed = await ensureCanReadMusicFiles(context);
    if (!allowed || !mounted) return;

    final picked = await pickMusicDirectory();
    if (!mounted || picked == null) return;

    final normalized = _normalizePickPath(picked);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This folder cannot be read as a file path yet. Try another folder or a device where the picker returns a path.',
          ),
        ),
      );
      return;
    }

    setState(() => _scanning = true);
    List<String> files;
    try {
      files = await scanMp3Files(normalized, recursive: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No .mp3 files found in that folder.')),
      );
      return;
    }

    final player = PlayerController.of(context);
    final tracks = files.map(TrackItem.fromFilePath).toList();

    setState(() => _folderPath = normalized);
    await player.setPlaylist(tracks, startIndex: 0);
    await player.play();

    if (!kIsWeb && mounted) {
      enrichPlaylistTracks(
        tracks: tracks,
        onTrackUpdated: player.updateTrackByPath,
      ).catchError((Object e, StackTrace st) {
        debugPrint('enrichPlaylistTracks: $e\n$st');
      });
    }
  }

  String? _normalizePickPath(String raw) {
    if (raw.startsWith('content:')) return null;
    if (raw.startsWith('file:')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  Future<void> _selectTrack(int i) async {
    final player = PlayerController.of(context);
    if (i < 0 || i >= player.playlist.length) return;
    await player.jumpToIndex(i);
  }

  void _openNowPlaying() {
    final player = PlayerController.of(context);
    final track = player.currentTrack;
    if (track == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NowPlayingScreen(
              sourceTitle: 'Playing from',
              sourceSubtitle: _playingSourceSubtitle,
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
    final canPop = Navigator.canPop(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.playlist;
        final current = player.currentTrack;

        return Scaffold(
          backgroundColor: AppColors.navy,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                      child: Row(
                        children: [
                          if (canPop)
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                              color: AppColors.textOnNavy,
                              onPressed: () => Navigator.maybePop(context),
                            )
                          else
                            const SizedBox(width: 48),
                          Expanded(
                            child: Text(
                              kLibraryMainTitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.textOnNavy,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open_rounded),
                            color: AppColors.textOnNavy,
                            tooltip: 'Choose music folder',
                            onPressed: _scanning ? null : _pickAndScanFolder,
                          ),
                        ],
                      ),
                    ),
                    if (_folderPath != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Text(
                          p.basename(_folderPath!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textMuted.withOpacity(0.95),
                          ),
                        ),
                      ),
                    Expanded(child: _buildListBody(theme, tracks, player)),
                    if (current != null)
                      MiniPlayerBar(
                        controller: player,
                        onTap: _openNowPlaying,
                      ),
                  ],
                ),
                if (_scanning)
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x33000000)),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.surface),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListBody(ThemeData theme, List<TrackItem> tracks, PlayerController player) {
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 56,
                color: AppColors.textOnNavy.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No tracks yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textOnNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the folder icon to choose a directory. MP3 files are listed recursively.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _scanning ? null : _pickAndScanFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Choose folder'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: Color(0x22FFFFFF),
        indent: 88,
      ),
      itemBuilder: (context, i) {
        final track = tracks[i];
        final selected = i == player.currentIndex;
        return _TrackTile(
          track: track,
          selected: selected,
          onTap: () => _selectTrack(i),
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final TrackItem track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? Colors.white.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TrackListArt(track: track),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${track.metaLine} · ${track.genres}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted.withOpacity(0.9),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textOnNavy,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary.withOpacity(0.95),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                color: AppColors.textOnNavy.withOpacity(0.8),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackListArt extends StatelessWidget {
  const _TrackListArt({required this.track});

  final TrackItem track;

  @override
  Widget build(BuildContext context) {
    final bytes = track.albumArtBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          bytes,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _gradientBox(),
        ),
      );
    }
    return _gradientBox();
  }

  Widget _gradientBox() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: track.artColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
