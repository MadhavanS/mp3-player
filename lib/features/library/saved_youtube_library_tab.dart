import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../platform/youtube_platform_support.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/saved_youtube_audio_store.dart';
import '../../services/saved_youtube_links_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';
import '../player/track_overflow_actions.dart';
import '../youtube/saved_youtube_audio_info.dart';
import '../youtube/youtube_save_audio_dialog.dart';
import 'library_screen.dart';

/// Library tab listing saved YouTube audio files or bookmarked stream links.
class SavedYoutubeLibraryTab extends StatefulWidget {
  const SavedYoutubeLibraryTab({
    super.key,
    required this.savedAudio,
    required this.playbackOriginTab,
    required this.searchQuery,
    required this.scrollController,
    this.scrollAnchorKey,
    required this.onPlayTracks,
    required this.onTrackOverflow,
    required this.isCurrentTrack,
  });

  final bool savedAudio;
  final LibraryTabId playbackOriginTab;
  final LibrarySearchQuery searchQuery;
  final ScrollController scrollController;
  final GlobalKey? scrollAnchorKey;
  final void Function(List<TrackItem> tracks, int startIndex) onPlayTracks;
  final void Function(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    TrackOverflowQueueContext? outsideQueue,
  }) onTrackOverflow;
  final bool Function(PlayerController player, TrackItem track) isCurrentTrack;

  @override
  State<SavedYoutubeLibraryTab> createState() => _SavedYoutubeLibraryTabState();
}

class _SavedYoutubeLibraryTabState extends State<SavedYoutubeLibraryTab> {
  Future<List<TrackItem>>? _tracksFuture;
  int _tracksFutureStoreRev = -1;

  ValueNotifier<int> get _storeRevision => widget.savedAudio
      ? SavedYoutubeAudioStore.revision
      : SavedYoutubeLinksStore.revision;

  /// Stable across parent [PlayerController] rebuilds; refresh when store rev bumps.
  Future<List<TrackItem>> _tracksLoadFuture() {
    final rev = _storeRevision.value;
    if (_tracksFuture != null && _tracksFutureStoreRev == rev) {
      return _tracksFuture!;
    }
    _tracksFutureStoreRev = rev;
    _tracksFuture = widget.savedAudio
        ? SavedYoutubeAudioStore.load()
        : SavedYoutubeLinksStore.load();
    return _tracksFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: _storeRevision,
      builder: (context, _) {
        return FutureBuilder<List<TrackItem>>(
          future: _tracksLoadFuture(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(color: context.controlAccent),
              );
            }
            var tracks = snap.data ?? [];
            if (widget.searchQuery.isNotEmpty) {
              tracks = tracks
                  .where((t) => widget.searchQuery.matchesTrack(t))
                  .toList();
            }

            if (tracks.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    widget.savedAudio
                        ? (widget.searchQuery.isNotEmpty
                            ? 'No saved audio matches your search.'
                            : 'No saved audio yet.\nSave tracks from Online search or Now Playing.')
                        : (widget.searchQuery.isNotEmpty
                            ? 'No saved links match your search.'
                            : 'No saved links yet.\nBookmark tracks from Now Playing.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: pal.textMuted,
                    ),
                  ),
                ),
              );
            }

            return ListView.separated(
              controller: widget.scrollController,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: tracks.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: pal.dividerOnHero, indent: 88),
              itemBuilder: (context, i) {
                final track = tracks[i];
                final plIndex = player.playlist.indexWhere(
                  (t) => _sameTrackIdentity(t, track),
                );
                final selected = widget.isCurrentTrack(player, track);
                final attachKey =
                    selected && widget.scrollAnchorKey != null;

                return Material(
                  key: attachKey ? widget.scrollAnchorKey : null,
                  color: selected
                      ? pal.onScaffold.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onPlayTracks(tracks, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TrackAlbumArt(
                            track: track,
                            display: TrackArtDisplay.list,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _metaLine(track, widget.savedAudio),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: pal.textMuted.withValues(alpha: 0.9),
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: pal.onScaffold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: pal.textSecondary.withValues(
                                      alpha: 0.95,
                                    ),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _SavedYoutubeLibraryOverflowMenu(
                            pal: pal,
                            track: track,
                            savedAudio: widget.savedAudio,
                            onTrackOverflow: (action) {
                              widget.onTrackOverflow(
                                context,
                                player,
                                plIndex >= 0 ? plIndex : -1,
                                action,
                                outsideQueue: plIndex < 0
                                    ? TrackOverflowQueueContext(
                                        tracks: tracks,
                                        index: i,
                                        playbackOriginTab:
                                            widget.playbackOriginTab,
                                      )
                                    : null,
                              );
                            },
                            onInfo: () => widget.savedAudio
                                ? showSavedYoutubeAudioInfoDialog(
                                    context,
                                    track,
                                  )
                                : showSavedYoutubeLinkInfoDialog(
                                    context,
                                    track,
                                  ),
                            onSaveAudio: !widget.savedAudio && !kIsWeb
                                ? () => showYoutubeSaveAudioDialog(
                                      context,
                                      track,
                                    )
                                : null,
                            onRemove: () async {
                              final id = track.youtubeVideoId?.trim() ?? '';
                              if (id.isEmpty) return;
                              if (widget.savedAudio) {
                                await SavedYoutubeAudioStore.remove(id);
                              } else {
                                await SavedYoutubeLinksStore.remove(id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static bool _sameTrackIdentity(TrackItem a, TrackItem b) {
    final ya = a.youtubeVideoId?.trim();
    final yb = b.youtubeVideoId?.trim();
    if (ya != null && ya.isNotEmpty && yb != null && yb.isNotEmpty) {
      return ya == yb;
    }
    final fa = a.filePath?.trim();
    final fb = b.filePath?.trim();
    if (fa != null && fa.isNotEmpty && fb != null && fb.isNotEmpty) {
      return fa == fb;
    }
    return a.title == b.title && a.artist == b.artist;
  }

  static String _metaLine(TrackItem track, bool savedAudio) {
    if (savedAudio) {
      final fp = track.filePath?.trim();
      if (fp != null && fp.isNotEmpty && !kIsWeb) {
        return 'Saved on device';
      }
      return 'Saved audio';
    }
    return 'Stream link · ${track.metaLine}';
  }
}

/// Single ⋮ menu: queue actions + saved-link/audio actions.
class _SavedYoutubeLibraryOverflowMenu extends StatelessWidget {
  const _SavedYoutubeLibraryOverflowMenu({
    required this.pal,
    required this.track,
    required this.savedAudio,
    required this.onTrackOverflow,
    required this.onInfo,
    this.onSaveAudio,
    required this.onRemove,
  });

  final AppPalette pal;
  final TrackItem track;
  final bool savedAudio;
  final ValueChanged<TrackOverflowAction> onTrackOverflow;
  final VoidCallback onInfo;
  final Future<void> Function()? onSaveAudio;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final iconFg = pal.onScaffold.withValues(alpha: 0.8);
    final channelId = track.youtubeChannelId?.trim() ?? '';

    return PopupMenuButton<_SavedYoutubeLibraryMenuValue>(
      tooltip: 'Track options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      icon: Icon(Icons.more_vert_rounded, color: iconFg, size: 24),
      onSelected: (value) async {
        switch (value) {
          case _SavedYoutubeLibraryMenuOverflow(:final action):
            onTrackOverflow(action);
          case _SavedYoutubeLibraryMenuInfo():
            onInfo();
          case _SavedYoutubeLibraryMenuSaveAudio():
            final save = onSaveAudio;
            if (save != null) await save();
          case _SavedYoutubeLibraryMenuRemove():
            onRemove();
        }
      },
      itemBuilder: (context) {
        final videoId = track.youtubeVideoId?.trim() ?? '';
        final savedOnDevice = !savedAudio &&
            videoId.isNotEmpty &&
            SavedYoutubeAudioStore.isSaved(videoId);

        // Saved audio: [SavedYoutubeAudioStore.remove] already deletes the file.
        final overflow = trackOverflowPopupMenuEntries(
          enableDeleteFromDevice:
              !savedAudio && trackCanDeleteFromDevice(track),
          enableFavorite: false,
          enableYoutubeChannelBrowse: channelId.isNotEmpty &&
              YoutubePlatformSupport.isOnlinePlaybackSupported,
        );

        final items = <PopupMenuEntry<_SavedYoutubeLibraryMenuValue>>[];
        for (final entry in overflow) {
          if (entry is PopupMenuItem<TrackOverflowAction>) {
            final action = entry.value;
            if (action == null) continue;
            items.add(
              PopupMenuItem(
                value: _SavedYoutubeLibraryMenuOverflow(action),
                enabled: entry.enabled,
                child: entry.child ?? const SizedBox.shrink(),
              ),
            );
          } else if (entry is PopupMenuDivider) {
            items.add(const PopupMenuDivider());
          }
        }

        items.add(const PopupMenuDivider());
        items.add(
          PopupMenuItem(
            value: const _SavedYoutubeLibraryMenuInfo(),
            child: ListTile(
              leading: Icon(
                savedAudio
                    ? Icons.info_outline_rounded
                    : Icons.link_rounded,
              ),
              title: Text(savedAudio ? 'Audio info' : 'Link info'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        );
        if (onSaveAudio != null) {
          items.add(
            PopupMenuItem(
              value: const _SavedYoutubeLibraryMenuSaveAudio(),
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
                dense: true,
              ),
            ),
          );
        }
        items.add(
          PopupMenuItem(
            value: const _SavedYoutubeLibraryMenuRemove(),
            child: ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: Text(savedAudio ? 'Delete from device' : 'Remove'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        );
        return items;
      },
    );
  }
}

sealed class _SavedYoutubeLibraryMenuValue {
  const _SavedYoutubeLibraryMenuValue();
}

final class _SavedYoutubeLibraryMenuOverflow
    extends _SavedYoutubeLibraryMenuValue {
  const _SavedYoutubeLibraryMenuOverflow(this.action);
  final TrackOverflowAction action;
}

final class _SavedYoutubeLibraryMenuInfo extends _SavedYoutubeLibraryMenuValue {
  const _SavedYoutubeLibraryMenuInfo();
}

final class _SavedYoutubeLibraryMenuSaveAudio
    extends _SavedYoutubeLibraryMenuValue {
  const _SavedYoutubeLibraryMenuSaveAudio();
}

final class _SavedYoutubeLibraryMenuRemove
    extends _SavedYoutubeLibraryMenuValue {
  const _SavedYoutubeLibraryMenuRemove();
}
