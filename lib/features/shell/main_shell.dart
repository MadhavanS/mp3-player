import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/file_path_mtime_sort.dart';
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
  const MainShell({
    super.key,
    required this.themeSetting,
    required this.onThemeSettingChanged,
  });

  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;

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

  /// Merges unique MP3 paths from all roots, then sorts by file last-modified (newest first).
  Future<List<String>> _collectMp3Paths(List<String> roots) async {
    final seen = <String>{};
    final out = <String>[];
    for (final root in roots) {
      final files = await scanMp3Files(root, recursive: true);
      for (final f in files) {
        if (seen.add(f)) out.add(f);
      }
    }
    await sortPathsByModifiedNewestFirst(out);
    return out;
  }

  Future<void> _scanFoldersAndSetPlaylist(
    List<String> paths, {
    required bool playAfter,
    int startIndex = 0,
    bool preservePlaybackAfterRescan = false,
  }) async {
    final player = PlayerController.of(context);
    final pathToPreserve =
        preservePlaybackAfterRescan ? player.currentTrack?.filePath : null;
    final wasPlaying = preservePlaybackAfterRescan && player.isPlaying;
    final playbackPosition =
        preservePlaybackAfterRescan ? player.position : Duration.zero;

    if (paths.isEmpty) {
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
      await player.setPlaylist([], startIndex: 0);
      return;
    }

    final tracks = files.map(TrackItem.fromFilePath).toList();
    var resolvedStart = startIndex.clamp(0, tracks.length - 1);
    if (pathToPreserve != null) {
      final idx = tracks.indexWhere((t) => t.filePath == pathToPreserve);
      if (idx >= 0) resolvedStart = idx;
    }

    await player.setPlaylist(tracks, startIndex: resolvedStart);

    if (preservePlaybackAfterRescan && pathToPreserve != null && tracks.isNotEmpty) {
      final atPath = tracks[resolvedStart].filePath;
      if (atPath == pathToPreserve && playbackPosition > Duration.zero) {
        await player.seek(playbackPosition);
      }
    }

    if (playAfter) {
      await player.play();
    } else if (preservePlaybackAfterRescan) {
      if (wasPlaying) {
        await player.play();
      } else {
        await player.pause();
      }
    }

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

  Future<void> _refreshLibraryScan() async {
    if (_folderPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add music folders in Settings first.',
          ),
        ),
      );
      return;
    }
    await _scanFoldersAndSetPlaylist(
      _folderPaths,
      playAfter: false,
      preservePlaybackAfterRescan: true,
    );
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

        final pal = context.palette;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: pal.scaffoldBackground,
          drawer: Drawer(
            backgroundColor: pal.surface,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Text(
                      'MP3 Player',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: pal.primary,
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
                            onRefreshLibrary:
                                _folderPaths.isEmpty || _scanning
                                    ? null
                                    : () {
                                        unawaited(_refreshLibraryScan());
                                      },
                          )
                        : SettingsScreen(
                            folderPaths: _folderPaths,
                            onFoldersChanged: _onFoldersChanged,
                            onOpenDrawer: _openDrawer,
                            themeSetting: widget.themeSetting,
                            onThemeSettingChanged: widget.onThemeSettingChanged,
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0x33000000)),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.palette.surface,
                      ),
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
