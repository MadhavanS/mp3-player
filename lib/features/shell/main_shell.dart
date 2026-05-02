import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/mp3_scanner.dart';
import '../../services/saved_music_folders.dart';
import '../../services/track_metadata.dart';
import '../../theme/app_theme.dart';
import '../library/library_screen.dart';
import '../player/mini_player_bar.dart';
import '../player/now_playing_screen.dart';
import '../settings/settings_screen.dart';

enum _ShellPage { library, settings }

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _ShellPage _page = _ShellPage.library;
  List<String> _folderPaths = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreFoldersAndScan();
    });
  }

  Future<void> _restoreFoldersAndScan() async {
    final paths = await SavedMusicFolders.load();
    if (!mounted) return;
    setState(() => _folderPaths = List<String>.from(paths));
    if (paths.isEmpty) return;
    await _scanFoldersAndSetPlaylist(paths, playAfter: false);
  }

  /// Merges MP3 paths from all roots; order is stable (by folder order, then scan order).
  Future<List<String>> _collectMp3Paths(List<String> roots) async {
    final seen = <String>{};
    final out = <String>[];
    for (final root in roots) {
      final files = await scanMp3Files(root, recursive: true);
      for (final f in files) {
        if (seen.add(f)) out.add(f);
      }
    }
    return out;
  }

  Future<void> _scanFoldersAndSetPlaylist(
    List<String> paths, {
    required bool playAfter,
    int startIndex = 0,
  }) async {
    if (paths.isEmpty) {
      final player = PlayerController.of(context);
      await player.setPlaylist([], startIndex: 0);
      return;
    }

    setState(() => _scanning = true);
    List<String> files;
    try {
      files = await _collectMp3Paths(paths);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No .mp3 files found in the saved folders.'),
        ),
      );
      final player = PlayerController.of(context);
      await player.setPlaylist([], startIndex: 0);
      return;
    }

    final player = PlayerController.of(context);
    final tracks = files.map(TrackItem.fromFilePath).toList();
    await player.setPlaylist(tracks, startIndex: startIndex.clamp(0, tracks.length - 1));
    if (playAfter) await player.play();

    if (!kIsWeb && mounted) {
      enrichPlaylistTracks(
        tracks: tracks,
        onTrackUpdated: player.updateTrackByPath,
      ).catchError((Object e, StackTrace st) {
        debugPrint('enrichPlaylistTracks: $e\n$st');
      });
    }
  }

  Future<void> _onFoldersChanged(List<String> paths) async {
    await SavedMusicFolders.save(paths);
    if (!mounted) return;
    setState(() => _folderPaths = List<String>.from(paths));
    await _scanFoldersAndSetPlaylist(paths, playAfter: false);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _goLibrary() {
    setState(() => _page = _ShellPage.library);
  }

  void _goSettings() {
    setState(() => _page = _ShellPage.settings);
  }

  void _openNowPlaying() {
    final player = PlayerController.of(context);
    if (player.currentTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing is playing right now.')),
      );
      return;
    }
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

  void _onDrawerNowPlaying() {
    Navigator.pop(context);
    _openNowPlaying();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.currentTrack;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.navy,
          drawer: Drawer(
            backgroundColor: AppColors.surface,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Text(
                      'MP3 Player',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.library_music_rounded),
                    title: const Text('Library'),
                    selected: _page == _ShellPage.library,
                    onTap: () {
                      Navigator.pop(context);
                      _goLibrary();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.play_circle_rounded),
                    title: const Text('Now playing'),
                    enabled: current != null,
                    onTap: current == null ? null : _onDrawerNowPlaying,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_rounded),
                    title: const Text('Settings'),
                    selected: _page == _ShellPage.settings,
                    onTap: () {
                      Navigator.pop(context);
                      _goSettings();
                    },
                  ),
                ],
              ),
            ),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: _page == _ShellPage.library
                        ? LibraryScreen(
                            folderPaths: _folderPaths,
                            onOpenDrawer: _openDrawer,
                          )
                        : SettingsScreen(
                            folderPaths: _folderPaths,
                            onFoldersChanged: _onFoldersChanged,
                            onOpenDrawer: _openDrawer,
                          ),
                  ),
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
        );
      },
    );
  }
}
