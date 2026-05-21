import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../theme/album_art_title_color.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';
import '../../widgets/daisy_background.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/player_adaptive_controls.dart';
import '../../widgets/track_album_art.dart';
import '../shell/now_playing_escape_bridge.dart';
import 'edit_track_tags_sheet.dart';
import 'mini_player_bar.dart';
import 'site_rename_standalone_dialog.dart';
import 'sleep_timer_control.dart';
import 'track_overflow_actions.dart';

/// Silver full-art player: ink, inactive seek track, timestamps, disabled icons.
const Color _kSilverInk = Color(0xFF0A0A0A);
const Color _kSilverTimeGray = Color(0xFFA8A49E);
const Color _kSilverIconDisabled = Color(0xFFB8B4AE);
const Color _kLeahPinkActive = Color(0xFF9C3F6E);
const Color _kLeahPinkSoft = Color(0xFFE7B5CC);

// Ivy liquid-glass colors (neutral achromatic, reference-style)
const Color _kIvyInk = Color(0xFF1C1C1E);
/// Muted chrome (sliders, inactive icons) — not for body text on glass.
const Color _kIvyMuted = Color(0xFFAEAEB2);
/// Artist / secondary labels on frosted light backgrounds.
const Color _kIvySecondaryText = Color(0xFF48484A);
/// Inactive Ivy icons (shuffle/repeat off, favourite off, sleep off).
const Color _kIvyInactiveIcon = Color(0xFFC8C8CE);
const Color _kIvyIconDisabled = Color(0xFFC7C7CC);

String _formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key, required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double? _dragPositionFraction;
  double _pullDismissPx = 0;
  bool _collapseRequested = false;

  @override
  void initState() {
    super.initState();
    NowPlayingRouteMark.enter();
  }

  @override
  void dispose() {
    NowPlayingRouteMark.leave();
    super.dispose();
  }

  void _safeCollapse() {
    if (_collapseRequested || !mounted) return;
    if (NowPlayingEscDuplicatePopGuard.blockShortcutCollapse) return;
    _collapseRequested = true;
    widget.onCollapse();
  }

  void _resetPullDismiss() => _pullDismissPx = 0;

  bool get _desktopNowPlayingEscDismiss =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Desktop has no system back gesture; offer Escape like many full-screen UIs.
  ///
  /// On Windows, Escape is handled by [MadPlayerApp]'s global key handler so it can
  /// return to Queue vs Songs without double-popping (CallbackShortcuts + global would
  /// each call [Navigator.pop] and black out the window).
  Widget _wrapDesktopEscDismiss({required Widget child}) {
    if (!_desktopNowPlayingEscDismiss) return child;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return Focus(autofocus: true, child: child);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _safeCollapse,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  void _onPullDownUpdate(double deltaDown) {
    if (deltaDown <= 0) return;
    _pullDismissPx += deltaDown;
    if (_pullDismissPx >= 56) {
      _resetPullDismiss();
      _safeCollapse();
    }
  }

  bool _onScrollOverscroll(ScrollNotification n) {
    if (_collapseRequested) return false;
    if (n is! OverscrollNotification || n.metrics.axis != Axis.vertical) {
      return false;
    }
    if (n.metrics.extentBefore > 0) {
      return false;
    }
    final o = n.overscroll;
    if (o.abs() < 40) {
      return false;
    }
    _safeCollapse();
    return true;
  }

  /// Pull down at scroll top (before/without overscroll) to dismiss—handles platforms
  /// where [OverscrollNotification] is sparse or missing.
  bool _onScrollPullAtTop(ScrollNotification n) {
    if (_collapseRequested || n is! ScrollUpdateNotification) {
      return false;
    }
    final m = n.metrics;
    if (m.axis != Axis.vertical || m.extentBefore > 0) {
      return false;
    }
    final delta = n.scrollDelta;
    if (delta == null) {
      return false;
    }
    if (m.pixels <= 0 && delta < 0) {
      _onPullDownUpdate(-delta);
      return false;
    }
    if (delta > 0 && m.pixels <= 0) {
      _resetPullDismiss();
    }
    return false;
  }

  bool _onScrollForDismiss(ScrollNotification n) {
    if (_onScrollOverscroll(n)) return true;
    _onScrollPullAtTop(n);
    return false;
  }

  void _showTagSheet(PlayerController player) {
    final t = player.currentTrack;
    if (t == null || t.filePath == null || t.filePath!.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      showDragHandle: false,
      builder: (ctx) => EditTrackTagsSheet(track: t),
    );
  }

  void _openTagEditor(PlayerController player) => _showTagSheet(player);

  Future<void> _onSoftBlurTailOverflowSelected(
    PlayerController player,
    String value,
  ) async {
    if (!value.startsWith('ta:')) return;
    final action = TrackOverflowAction.values.byName(value.substring(3));
    await applyTrackOverflowAction(
      context,
      player,
      player.currentIndex,
      action,
      playbackOriginTab: player.playbackOriginTab,
    );
  }

  List<PopupMenuEntry<String>> _softBlurRestMenuEntries(TrackItem track) {
    final out = <PopupMenuEntry<String>>[];
    for (final e in trackOverflowPopupMenuEntries(
      enableDeleteFromDevice: trackCanDeleteFromDevice(track),
      enableFavorite: false,
      isFavorite: false,
    )) {
      if (e is PopupMenuItem<TrackOverflowAction>) {
        final a = e.value;
        if (a == null) continue;
        out.add(
          PopupMenuItem<String>(
            value: 'ta:${a.name}',
            child: e.child ?? const SizedBox.shrink(),
          ),
        );
      } else if (e is PopupMenuDivider) {
        out.add(const PopupMenuDivider());
      }
    }
    return out;
  }

  Widget _softBlurTailOverflowMenu({
    required PlayerController player,
    required TrackItem track,
    required Color actionColor,
  }) {
    final ivy = context.appliedThemePalette == AppThemePalette.ivy;
    final silver = context.appliedThemePalette == AppThemePalette.silver;
    
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(
        ivy
            ? Icons.more_horiz_rounded
            : (silver ? Icons.more_vert : Icons.more_vert_rounded),
        color: ivy ? context.controlAccent : actionColor,
        size: silver ? 34 : 24,
      ),
      itemBuilder: (ctx) => _softBlurRestMenuEntries(track),
      onSelected: (v) => unawaited(_onSoftBlurTailOverflowSelected(player, v)),
    );
  }

  void _notifyShuffle(PlayerController player) {
    if (player.playlist.length < 2) return;
    player.toggleShuffle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ActionPillToast.showUsingRootNavigator(
        player.shuffleEnabled ? 'Shuffle on' : 'Shuffle off',
        icon: Icons.shuffle_rounded,
        uppercaseLabel: true,
      );
    });
  }

  void _notifyRepeat(PlayerController player) {
    player.cycleRepeatMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mode = player.repeatMode;
      final msg = switch (mode) {
        PlaylistRepeatMode.off => 'Repeat off',
        PlaylistRepeatMode.all => 'Repeat all',
        PlaylistRepeatMode.one => 'Repeat current',
      };
      final icon = mode == PlaylistRepeatMode.one
          ? Icons.repeat_one_rounded
          : Icons.repeat_rounded;
      ActionPillToast.showUsingRootNavigator(
        msg,
        icon: icon,
        uppercaseLabel: true,
      );
    });
  }

  Widget _favoriteButton(AppPalette pal, TrackItem cur) {
    final path = cur.filePath ?? '';
    final canFav = path.isNotEmpty;
    unawaited(FavoriteSongsStore.ensureLoaded());
    return ListenableBuilder(
      listenable: FavoriteSongsStore.revision,
      builder: (context, _) {
        final isFav = canFav && FavoriteSongsStore.isFavorite(path);
        final silver = _isSilverNp(context);
        final leah = _isLeahNp(context);
        final ivy = _isIvyNp(context);
        final julia = context.appliedThemePalette == AppThemePalette.julia;
        final favIcon = isFav
            ? (silver ? Icons.favorite : Icons.favorite_rounded)
            : (julia ? Icons.heart_broken : Icons.heart_broken_rounded);
        return IconButton(
          iconSize: silver ? 36 : 28,
          tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.82,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Icon(
              favIcon,
              key: ValueKey<bool>(isFav),
              color: !canFav
                  ? (silver
                        ? _kSilverIconDisabled.withValues(alpha: 0.55)
                        : (leah
                              ? _kLeahPinkSoft.withValues(alpha: 0.5)
                              : ivy
                              ? _kIvyIconDisabled
                              : pal.textSecondary.withValues(alpha: 0.35)))
                  : isFav
                  ? (silver
                        ? _kSilverInk
                        : (leah
                              ? _kLeahPinkActive
                              : context.controlAccent))
                  : (silver
                        ? _kSilverTimeGray
                        : (leah
                              ? _kLeahPinkSoft
                              : ivy
                              ? _kIvyInactiveIcon
                              : (julia
                                    ? pal.onScaffold.withValues(alpha: 0.9)
                                    : pal.textSecondary.withValues(
                                        alpha: 0.55,
                                      )))),
            ),
          ),
          onPressed: !canFav
              ? null
              : () async {
                  final nowFav = await FavoriteSongsStore.toggleFavorite(path);
                  if (!context.mounted) return;
                  ActionPillToast.showUsingRootNavigator(
                    nowFav ? 'Favourited' : 'Removed from favourites',
                    icon: nowFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    uppercaseLabel: true,
                  );
                },
        );
      },
    );
  }

  Widget _footerTrackTools(
    BuildContext context,
    AppPalette pal,
    PlayerController player,
  ) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final cur = player.currentTrack;
        if (cur == null) return const SizedBox.shrink();

        final canEdit = cur.filePath != null && cur.filePath!.isNotEmpty;
        final isJulia = context.appliedThemePalette == AppThemePalette.julia;

        final footerChrome = context.usesPlayerChrome;
        final navIconColor = footerChrome ? pal.onScaffold : pal.textPrimary;
        return Material(
          color: footerChrome ? pal.scaffoldBackground : pal.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, thickness: 1, color: pal.dividerOnHero),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: footerChrome ? 'Collapse' : 'Back to library',
                        iconSize: 28,
                        icon: Icon(
                          footerChrome
                              ? Icons.expand_more_rounded
                              : Icons.arrow_back_rounded,
                          color: navIconColor,
                        ),
                        onPressed: _safeCollapse,
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit tags & cover',
                              iconSize: 28,
                              icon: Icon(
                                Icons.edit_note_rounded,
                                color: canEdit
                                    ? context.controlAccent
                                    : pal.textSecondary.withValues(alpha: 0.45),
                              ),
                              onPressed: canEdit
                                  ? () => _openTagEditor(player)
                                  : null,
                            ),
                            SleepTimerControl(
                              player: player,
                              iconColor: context.controlAccent,
                            ),
                            IconButton(
                              tooltip: 'Add to playlist',
                              iconSize: 28,
                              icon: Icon(
                                Icons.playlist_add_rounded,
                                color: canEdit
                                    ? context.controlAccent
                                    : pal.textSecondary.withValues(alpha: 0.45),
                              ),
                              onPressed: canEdit
                                  ? () {
                                      unawaited(
                                        applyTrackOverflowAction(
                                          context,
                                          player,
                                          player.currentIndex,
                                          TrackOverflowAction.addToPlaylist,
                                          playbackOriginTab:
                                              player.playbackOriginTab,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                            IconButton(
                              tooltip: 'Auto update tags',
                              iconSize: 28,
                              icon: Icon(
                                Icons.auto_fix_high_outlined,
                                color: canEdit
                                    ? context.controlAccent
                                    : pal.textSecondary.withValues(alpha: 0.45),
                              ),
                              onPressed: canEdit && !kIsWeb
                                  ? () => showStandaloneSiteRenameDialog(
                                      context,
                                      cur,
                                    )
                                  : null,
                            ),
                            if (isJulia) ...[
                              const SizedBox(width: 2),
                              _favoriteButton(pal, cur),
                            ],
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: FavoriteSongsStore.revision,
                        builder: (context, _) {
                          final ivy = context.appliedThemePalette == AppThemePalette.ivy;
                          final p = cur.filePath ?? '';
                          final favOk = trackCanToggleFavorite(cur);
                          final isFav =
                              favOk && FavoriteSongsStore.isFavorite(p);
                          return PopupMenuButton<TrackOverflowAction>(
                            tooltip: 'Track options',
                            padding: EdgeInsets.zero,
                            position: PopupMenuPosition.under,
                            constraints: const BoxConstraints(
                              minWidth: 200,
                              maxWidth: 248,
                            ),
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: ivy
                                  ? context.controlAccent
                                  : navIconColor,
                            ),
                            onSelected: (action) {
                              unawaited(
                                applyTrackOverflowAction(
                                  context,
                                  player,
                                  player.currentIndex,
                                  action,
                                  playbackOriginTab: player.playbackOriginTab,
                                ),
                              );
                            },
                            itemBuilder: (context) =>
                                trackOverflowPopupMenuEntries(
                                  enableDeleteFromDevice:
                                      trackCanDeleteFromDevice(cur),
                                  enableFavorite: favOk,
                                  isFavorite: isFav,
                                ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _softRoundControl({
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    double size = 56,
    double iconSize = 28,
    bool filled = false,
    bool silverInkRings = false,
    bool liquidGlass = false,
  }) {
    if (liquidGlass) {
      return LiquidGlassCircleButton(
        icon: icon,
        onPressed: onPressed,
        size: size,
        iconSize: iconSize,
        iconColor: color,
        disabledColor: color.withValues(alpha: 0.38),
        prominence: filled ? 0.72 : 0.52,
      );
    }
    if (silverInkRings) {
      final ring = onPressed == null ? _kSilverIconDisabled : _kSilverInk;
      final ink = onPressed == null ? _kSilverIconDisabled : _kSilverInk;
      return SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: filled && onPressed != null
                ? _kSilverInk.withValues(alpha: 0.08)
                : null,
            side: BorderSide(color: ring, width: 1.75),
            shape: const CircleBorder(),
          ),
          iconSize: iconSize,
          color: ink,
          icon: Icon(icon),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: filled ? color.withValues(alpha: 0.18) : null,
          side: BorderSide(color: color.withValues(alpha: 0.8), width: 1.6),
          shape: const CircleBorder(),
        ),
        iconSize: iconSize,
        color: color,
        icon: Icon(icon),
      ),
    );
  }

  bool _isSilverNp(BuildContext context) =>
      context.appliedThemePalette == AppThemePalette.silver;

  bool _isLeahNp(BuildContext context) =>
      context.appliedThemePalette == AppThemePalette.leah;

  bool _isDaisyNp(BuildContext context) =>
      context.appliedThemePalette == AppThemePalette.daisy;

  bool _isIvyNp(BuildContext context) =>
      context.appliedThemePalette == AppThemePalette.ivy;

  /// Daisy full-art controls sit on warm paper. Inactive toggles (shuffle/repeat
  /// off) must read clearly softer than ink — blend toward [AppPalette.surface],
  /// not only [textMuted], or they still look “on” in screenshots.
  ({Color active, Color off, Color disabled}) _daisyNpIconStates(
    AppPalette pal,
  ) {
    const active = Color(0xFF2B2117);
    final off = Color.lerp(pal.textMuted, pal.surface, 0.46)!;
    final disabled = Color.lerp(pal.textMuted, pal.surface, 0.72)!;
    return (active: active, off: off, disabled: disabled);
  }

  Color _fullArtSeekAccent(BuildContext context, AppPalette pal) {
    if (_isSilverNp(context)) return _kSilverInk;
    if (_isLeahNp(context)) return _kLeahPinkActive;
    return context.controlAccent;
  }

  double _fullArtHeroWidth(BuildContext context) {
    final raw = (MediaQuery.sizeOf(context).width - 48).clamp(220.0, 360.0);
    // Silver uses the same wide slot as Leah; artwork scales up via FittedBox below.
    return raw;
  }

  PlayerSliderAppearance _npSliderAppearance(BuildContext context) {
    if (_isSilverNp(context)) return PlayerSliderAppearance.silver;
    if (_isIvyNp(context)) return PlayerSliderAppearance.ivy;
    return PlayerSliderAppearance.softBlur;
  }

  TextStyle _fullArtTimeLabelStyle(
    BuildContext context,
    ThemeData theme,
    AppPalette pal,
    Color accent,
  ) {
    if (_isSilverNp(context)) {
      return theme.textTheme.labelSmall!.copyWith(
        color: _kSilverTimeGray,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );
    }
    if (_isLeahNp(context)) {
      return theme.textTheme.labelSmall!.copyWith(
        color: _kLeahPinkActive,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      );
    }
    if (_isIvyNp(context)) {
      return theme.textTheme.labelSmall!.copyWith(
        color: accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );
    }
    return theme.textTheme.labelSmall!.copyWith(
      color: accent.withValues(alpha: 0.95),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  TextStyle _fullArtTrackTitleStyle(
    BuildContext context,
    ThemeData theme,
    AppPalette pal,
  ) {
    if (_isSilverNp(context)) {
      return theme.textTheme.headlineSmall!.copyWith(
        color: pal.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 24,
        height: 1.25,
      );
    }
    if (_isLeahNp(context)) {
      return theme.textTheme.headlineSmall!.copyWith(
        color: _kLeahPinkActive,
        fontWeight: FontWeight.w700,
        fontSize: 28,
        height: 1.25,
      );
    }
    if (_isIvyNp(context)) {
      return theme.textTheme.headlineSmall!.copyWith(
        color: _kIvyInk,
        fontWeight: FontWeight.w700,
        fontSize: 28,
        height: 1.25,
      );
    }
    return theme.textTheme.headlineSmall!.copyWith(
      color: pal.onScaffold,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
  }

  TextStyle _fullArtTrackSecondaryStyle(
    BuildContext context,
    ThemeData theme,
    AppPalette pal, {
    required double fontSize,
    required double onScaffoldAlpha,
    bool albumMeta = false,
  }) {
    if (_isSilverNp(context)) {
      return theme.textTheme.titleMedium!.copyWith(
        color: pal.textPrimary,
        fontWeight: FontWeight.w500,
        fontSize: fontSize + 1,
      );
    }
    if (_isLeahNp(context)) {
      return theme.textTheme.titleMedium!.copyWith(
        color: _kLeahPinkActive.withValues(alpha: 0.94),
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
      );
    }
    if (_isIvyNp(context)) {
      return theme.textTheme.titleMedium!.copyWith(
        color: albumMeta ? _kIvyInk : _kIvySecondaryText,
        fontWeight: albumMeta ? FontWeight.w600 : FontWeight.w500,
        fontSize: fontSize,
      );
    }
    return theme.textTheme.titleMedium!.copyWith(
      color: pal.onScaffold.withValues(alpha: onScaffoldAlpha),
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  Widget _buildSoftBlurVolumeBar(
    BuildContext context, {
    required AppPalette pal,
    required PlayerController player,
    required double artWidth,
  }) {
    final accent = _fullArtSeekAccent(context, pal);
    final ivy = _isIvyNp(context);
    final iconTint = _isLeahNp(context)
        ? _kLeahPinkSoft
        : ivy
        ? accent.withValues(alpha: 0.75)
        : accent.withValues(alpha: 0.9);
    final volumeRow = Row(
      children: [
        Icon(
          Icons.volume_down_outlined,
          color: iconTint,
          size: _isSilverNp(context) ? 34 : 23,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: StreamBuilder<double>(
              stream: player.volumeStream,
              initialData: player.volume,
              builder: (context, snap) {
                final v = (snap.data ?? 1.0).clamp(0.0, 1.0);
                return PlayerAdaptiveSlider(
                  value: v,
                  onChanged: (nv) => unawaited(player.setVolume(nv)),
                  appearance: _npSliderAppearance(context),
                  activeColor: accent,
                  inactiveColor: ivy
                      ? _kIvyMuted.withValues(alpha: 0.45)
                      : null,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          Icons.volume_up_outlined,
          color: iconTint,
          size: _isSilverNp(context) ? 34 : 23,
        ),
      ],
    );
    return Center(
      child: SizedBox(
        width: artWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
          child: volumeRow,
        ),
      ),
    );
  }

  /// Silver: no circular chrome; sharp Material icons (not *_rounded).
  Widget _buildSilverFlatTransportContent(
    BuildContext context, {
    required PlayerController player,
    required Color accent,
    required Color muted,
    required Color shuffleOff,
  }) {
    final flat = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      minimumSize: const Size(54, 58),
      foregroundColor: accent,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          style: flat,
          onPressed: player.playlist.length < 2
              ? null
              : () => _notifyShuffle(player),
          icon: Icon(
            Icons.shuffle,
            size: 38,
            color: player.playlist.length < 2
                ? shuffleOff
                : (player.shuffleEnabled ? accent : muted),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Previous track',
          style: flat,
          onPressed: () => player.skipPrevious(),
          icon: Icon(Icons.skip_previous, size: 42, color: accent),
        ),
        const SizedBox(width: 12),
        ListenableBuilder(
          listenable: player,
          builder: (context, _) => IconButton(
            tooltip: player.isPlaying ? 'Pause' : 'Play',
            style: flat,
            onPressed: () => player.togglePlayPause(),
            icon: Icon(
              player.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 38,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ListenableBuilder(
          listenable: player,
          builder: (context, _) => IconButton(
            tooltip: 'Next track',
            style: flat,
            onPressed: player.canSkipNext ? () => player.skipNext() : null,
            icon: Icon(
              Icons.skip_next,
              size: 42,
              color: player.canSkipNext ? accent : shuffleOff,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Repeat mode',
          style: flat,
          onPressed: () => _notifyRepeat(player),
          icon: Icon(
            player.repeatMode == PlaylistRepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            size: 38,
            color: player.repeatMode == PlaylistRepeatMode.off
                ? shuffleOff
                : accent,
          ),
        ),
      ],
    );
  }

  Widget _buildSoftBlurTransportRow(
    BuildContext context, {
    required AppPalette pal,
    required PlayerController player,
    required double artWidth,
  }) {
    final accent = _fullArtSeekAccent(context, pal);
    final silver = _isSilverNp(context);
    final leah = _isLeahNp(context);
    final ivy = _isIvyNp(context);
    final muted = silver
        ? _kSilverTimeGray
        : leah
        ? _kLeahPinkSoft
        : ivy
        ? _kIvyMuted
        : pal.onScaffold.withValues(alpha: 0.5);
    final shuffleOff = silver
        ? _kSilverIconDisabled
        : ivy
        ? _kIvyInactiveIcon
        : muted;
    if (silver) {
      return SizedBox(
        width: artWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: _buildSilverFlatTransportContent(
            context,
            player: player,
            accent: accent,
            muted: muted,
            shuffleOff: shuffleOff,
          ),
        ),
      );
    }
    if (ivy) {
      final shuffleActive = player.playlist.length >= 2 && player.shuffleEnabled;
      final repeatActive = player.repeatMode != PlaylistRepeatMode.off;
      return SizedBox(
        width: artWidth,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LiquidGlassRingIconButton(
              icon: Icons.shuffle,
              onPressed: player.playlist.length < 2
                  ? null
                  : () => _notifyShuffle(player),
              size: 48,
              iconSize: 22,
              accentColor: accent,
              inactiveColor: shuffleOff,
              disabledColor: _kIvyIconDisabled,
              highlighted: false,
              active: shuffleActive,
            ),
            LiquidGlassCircleButton(
              icon: Icons.skip_previous,
              onPressed: () => player.skipPrevious(),
              size: 56,
              iconSize: 26,
              iconColor: _kIvyInk,
              disabledColor: _kIvyIconDisabled,
              highlighted: false,
            ),
            ListenableBuilder(
              listenable: player,
              builder: (context, _) => LiquidGlassCircleButton(
                icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: () => player.togglePlayPause(),
                size: 82,
                iconSize: 36,
                iconColor: Colors.white,
                disabledColor: _kIvyIconDisabled,
                highlighted: true, // This will trigger the dark capsule "Sattes" look
              ),
            ),
            ListenableBuilder(
              listenable: player,
              builder: (context, _) => LiquidGlassCircleButton(
                icon: Icons.skip_next,
                onPressed: player.canSkipNext ? () => player.skipNext() : null,
                size: 56,
                iconSize: 26,
                iconColor: _kIvyInk,
                disabledColor: _kIvyIconDisabled,
                highlighted: false,
              ),
            ),
            LiquidGlassRingIconButton(
              icon: player.repeatMode == PlaylistRepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
              onPressed: () => _notifyRepeat(player),
              size: 48,
              iconSize: 22,
              accentColor: accent,
              inactiveColor: shuffleOff,
              disabledColor: _kIvyIconDisabled,
              highlighted: false,
              active: repeatActive,
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: artWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Shuffle',
            iconSize: 28,
            onPressed: player.playlist.length < 2
                ? null
                : () => _notifyShuffle(player),
            icon: Icon(
              Icons.shuffle_rounded,
              color: player.playlist.length < 2
                  ? shuffleOff
                  : (player.shuffleEnabled ? accent : muted),
            ),
          ),
          _softRoundControl(
            icon: Icons.skip_previous_rounded,
            onPressed: () => player.skipPrevious(),
            color: accent,
            size: 60,
            iconSize: 30,
            silverInkRings: false,
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => _softRoundControl(
              icon: player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onPressed: () => player.togglePlayPause(),
              color: accent,
              size: 80,
              iconSize: 38,
              filled: true,
              silverInkRings: false,
            ),
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => _softRoundControl(
              icon: Icons.skip_next_rounded,
              onPressed: player.canSkipNext ? () => player.skipNext() : null,
              color: player.canSkipNext
                  ? accent
                  : accent.withValues(alpha: 0.38),
              size: 60,
              iconSize: 30,
              silverInkRings: false,
            ),
          ),
          IconButton(
            tooltip: 'Repeat mode',
            iconSize: 28,
            onPressed: () => _notifyRepeat(player),
            icon: Icon(
              player.repeatMode == PlaylistRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: player.repeatMode == PlaylistRepeatMode.off
                  ? shuffleOff
                  : accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftBlurTopSection(
    BuildContext context, {
    required ThemeData theme,
    required AppPalette pal,
    required PlayerController player,
    required TrackItem track,
  }) {
    final canEdit = track.filePath != null && track.filePath!.isNotEmpty;
    final albumName = track.metaLine.trim();
    final showAlbum = albumName.isNotEmpty && albumName.toLowerCase() != 'mp3';
    final artistName = track.artist.trim();
    final showArtist =
        artistName.isNotEmpty && artistName.toLowerCase() != 'unknown artist';
    final silver = _isSilverNp(context);
    final leah = _isLeahNp(context);
    final ivy = _isIvyNp(context);
    final actionColor = silver
        ? _kSilverInk
        : leah
        ? _kLeahPinkSoft
        : ivy
        ? context.controlAccent
        : pal.onScaffold.withValues(alpha: 0.92);
    final accent = _fullArtSeekAccent(context, pal);
    final artWidth = _fullArtHeroWidth(context);
    final topIconEnabled = silver ? _kSilverInk : actionColor;
    final topIconDisabled = silver
        ? _kSilverIconDisabled
        : leah
        ? _kLeahPinkSoft.withValues(alpha: 0.6)
        : ivy
        ? _kIvyIconDisabled
        : pal.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: artWidth,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Collapse',
                iconSize: silver ? 36 : null,
                onPressed: _safeCollapse,
                icon: Icon(
                  silver
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_down_rounded,
                  color: topIconEnabled,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Edit tags & cover',
                iconSize: silver ? 36 : null,
                onPressed: canEdit ? () => _openTagEditor(player) : null,
                icon: Icon(
                  silver ? Icons.edit_note : Icons.edit_note_rounded,
                  color: canEdit ? topIconEnabled : topIconDisabled,
                ),
              ),
              SleepTimerControl(
                player: player,
                iconColor: ivy ? _kIvyInactiveIcon : topIconEnabled,
                iconSize: silver ? 34 : 28,
              ),
              _favoriteButton(pal, track),
              IconButton(
                tooltip: 'Clean site-style name',
                iconSize: silver ? 34 : null,
                onPressed: canEdit && !kIsWeb
                    ? () => showStandaloneSiteRenameDialog(context, track)
                    : null,
                icon: Icon(
                  Icons.auto_fix_high_outlined,
                  color: canEdit ? topIconEnabled : topIconDisabled,
                ),
              ),
              _softBlurTailOverflowMenu(
                player: player,
                track: track,
                actionColor: topIconEnabled,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: artWidth,
          height: artWidth,
          child: FittedBox(
            fit: BoxFit.contain,
            child: TrackAlbumArt(
              track: track,
              display: TrackArtDisplay.full,
              showShadow: false,
              cornerRadius: _isSilverNp(context) ? 14 : 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: artWidth,
          child: _MarqueeText(
            track.title,
            textAlign: TextAlign.center,
            style: _fullArtTrackTitleStyle(context, theme, pal),
          ),
        ),
        if (showArtist) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: artWidth,
            child: _MarqueeText(
              artistName,
              textAlign: TextAlign.center,
              style: _fullArtTrackSecondaryStyle(
                context,
                theme,
                pal,
                fontSize: 16,
                onScaffoldAlpha: 0.88,
              ),
            ),
          ),
        ],
        if (showAlbum) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: artWidth,
            child: _MarqueeText(
              albumName,
              textAlign: TextAlign.center,
              style: _fullArtTrackSecondaryStyle(
                context,
                theme,
                pal,
                fontSize: 15,
                onScaffoldAlpha: 0.82,
                albumMeta: true,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: artWidth,
          child: StreamBuilder<Duration>(
            stream: player.audioPlayer.positionStream,
            builder: (context, posSnap) {
              return StreamBuilder<Duration?>(
                stream: player.audioPlayer.durationStream,
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? player.duration;
                  final pos = posSnap.data ?? player.position;
                  final totalMs = dur?.inMilliseconds ?? 0;
                  final posMs = pos.inMilliseconds;
                  final sliderValue =
                      _dragPositionFraction ??
                      (totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0);
                  final seekColumn = Column(
                    children: [
                      PlayerAdaptiveSlider(
                        value: sliderValue.clamp(0.0, 1.0),
                        appearance: _npSliderAppearance(context),
                        activeColor: accent,
                        inactiveColor: ivy
                            ? _kIvyMuted.withValues(alpha: 0.45)
                            : null,
                        onChanged: totalMs > 0
                            ? (v) => setState(() => _dragPositionFraction = v)
                            : null,
                        onChangeEnd: totalMs > 0
                            ? (v) {
                                player.seek(
                                  Duration(
                                    milliseconds: (v * totalMs).round(),
                                  ),
                                );
                                setState(() => _dragPositionFraction = null);
                              }
                            : null,
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDuration(pos),
                            style: _fullArtTimeLabelStyle(
                              context,
                              theme,
                              pal,
                              accent,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            dur != null ? _formatDuration(dur) : '--:--',
                            style: _fullArtTimeLabelStyle(
                              context,
                              theme,
                              pal,
                              accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                  return seekColumn;
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildDaisyTopSection(
    BuildContext context, {
    required ThemeData theme,
    required AppPalette pal,
    required PlayerController player,
    required TrackItem track,
  }) {
    final artWidth = _fullArtHeroWidth(context);
    final accent = const Color(0xFF2B2117);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: artWidth,
          height: artWidth,
          child: FittedBox(
            fit: BoxFit.contain,
            child: TrackAlbumArt(
              track: track,
              display: TrackArtDisplay.full,
              showShadow: false,
              cornerRadius: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: artWidth,
          child: Row(
            children: [
              _favoriteButton(pal, track),
              const SizedBox(width: 8),
              Expanded(
                child: _MarqueeText(
                  track.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded, color: accent),
                itemBuilder: (_) => _softBlurRestMenuEntries(track),
                onSelected: (v) =>
                    unawaited(_onSoftBlurTailOverflowSelected(player, v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: artWidth,
          child: StreamBuilder<Duration>(
            stream: player.audioPlayer.positionStream,
            builder: (context, posSnap) {
              return StreamBuilder<Duration?>(
                stream: player.audioPlayer.durationStream,
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? player.duration;
                  final pos = posSnap.data ?? player.position;
                  final totalMs = dur?.inMilliseconds ?? 0;
                  final posMs = pos.inMilliseconds;
                  final sliderValue =
                      _dragPositionFraction ??
                      (totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0);
                  return Column(
                    children: [
                      PlayerAdaptiveSlider(
                        value: sliderValue.clamp(0.0, 1.0),
                        appearance: PlayerSliderAppearance.daisy,
                        activeColor: accent,
                        inactiveColor: accent.withValues(alpha: 0.35),
                        onChanged: totalMs > 0
                            ? (v) => setState(() => _dragPositionFraction = v)
                            : null,
                        onChangeEnd: totalMs > 0
                            ? (v) {
                                player.seek(
                                  Duration(
                                    milliseconds: (v * totalMs).round(),
                                  ),
                                );
                                setState(() => _dragPositionFraction = null);
                              }
                            : null,
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDuration(pos),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            dur != null ? _formatDuration(dur) : '--:--',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildDaisyTransportRow(
    PlayerController player,
    double width,
    AppPalette pal,
  ) {
    final ink = _daisyNpIconStates(pal);
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Shuffle',
            iconSize: 26,
            onPressed: player.playlist.length < 2
                ? null
                : () => _notifyShuffle(player),
            icon: Icon(
              Icons.shuffle_rounded,
              color: player.playlist.length < 2
                  ? ink.disabled
                  : (player.shuffleEnabled ? ink.active : ink.off),
            ),
          ),
          IconButton(
            tooltip: 'Previous track',
            iconSize: 34,
            onPressed: () => player.skipPrevious(),
            icon: Icon(Icons.skip_previous_rounded, color: ink.active),
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => IconButton(
              tooltip: player.isPlaying ? 'Pause' : 'Play',
              iconSize: 44,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x00000000),
                side: BorderSide(color: ink.active, width: 1.2),
                fixedSize: const Size(84, 84),
              ),
              onPressed: () => player.togglePlayPause(),
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: ink.active,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => IconButton(
              tooltip: player.canSkipNext ? 'Next track' : 'End of playlist',
              iconSize: 34,
              onPressed: player.canSkipNext ? () => player.skipNext() : null,
              icon: Icon(
                Icons.skip_next_rounded,
                color: player.canSkipNext ? ink.active : ink.disabled,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Repeat mode',
            iconSize: 26,
            onPressed: () => _notifyRepeat(player),
            icon: Icon(
              player.repeatMode == PlaylistRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: player.repeatMode == PlaylistRepeatMode.off
                  ? ink.off
                  : ink.active,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaisyFooterTools(
    BuildContext context, {
    required AppPalette pal,
    required PlayerController player,
    required TrackItem track,
    required double width,
  }) {
    final canEdit = track.filePath != null && track.filePath!.isNotEmpty;
    final ink = _daisyNpIconStates(pal);
    // Left column lines up with the shuffle control above (same bar width).
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back to library',
            iconSize: 30,
            onPressed: _safeCollapse,
            icon: Icon(Icons.chevron_left_rounded, color: ink.active),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Edit tags & cover',
                  iconSize: 28,
                  icon: Icon(
                    Icons.edit_note_rounded,
                    color: canEdit ? ink.active : ink.disabled,
                  ),
                  onPressed: canEdit ? () => _openTagEditor(player) : null,
                ),
                const SizedBox(width: 10),
                SleepTimerControl(
                  player: player,
                  iconColor: ink.active,
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Add to playlist',
                  iconSize: 28,
                  icon: Icon(
                    Icons.playlist_add_rounded,
                    color: canEdit ? ink.active : ink.disabled,
                  ),
                  onPressed: canEdit
                      ? () {
                          unawaited(
                            applyTrackOverflowAction(
                              context,
                              player,
                              player.currentIndex,
                              TrackOverflowAction.addToPlaylist,
                              playbackOriginTab: player.playbackOriginTab,
                            ),
                          );
                        }
                      : null,
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Auto update tags',
                  iconSize: 28,
                  icon: Icon(
                    Icons.auto_fix_high_outlined,
                    color: canEdit ? ink.active : ink.disabled,
                  ),
                  onPressed: canEdit && !kIsWeb
                      ? () => showStandaloneSiteRenameDialog(context, track)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.currentTrack;
        if (track == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _safeCollapse();
          });
          return const SizedBox.shrink();
        }

        final playerChrome = context.usesPlayerChrome;
        final fullArtNp = context.usesFullArtNowPlayingLayout;
        final daisyNp = _isDaisyNp(context);
        final pageBg = playerChrome ? pal.scaffoldBackground : pal.surface;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(MiniPlayerBar.topSheetRadius),
          ),
          child: Scaffold(
            backgroundColor: pageBg,
            body: _wrapDesktopEscDismiss(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DaisyBackground(
                        baseColor: pageBg,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScrollForDismiss,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: ListenableBuilder(
                                    listenable: player,
                                    builder: (context, _) {
                                      final t = player.currentTrack;
                                      if (t == null) {
                                        return const SizedBox.shrink();
                                      }
                                      if (daisyNp) {
                                        return _buildDaisyTopSection(
                                          context,
                                          theme: theme,
                                          pal: pal,
                                          player: player,
                                          track: t,
                                        );
                                      }
                                      if (fullArtNp) {
                                        return _buildSoftBlurTopSection(
                                          context,
                                          theme: theme,
                                          pal: pal,
                                          player: player,
                                          track: t,
                                        );
                                      }
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Center(
                                            child: _NowPlayingAlbumArtCard(
                                              playerChrome: playerChrome,
                                              theme: theme,
                                              track: t,
                                              artwork: TrackAlbumArt(
                                                track: t,
                                                display:
                                                    TrackArtDisplay.nowPlaying,
                                                showShadow: false,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          StreamBuilder<Duration>(
                                            stream: player
                                                .audioPlayer
                                                .positionStream,
                                            builder: (context, posSnap) {
                                              return StreamBuilder<Duration?>(
                                                stream: player
                                                    .audioPlayer
                                                    .durationStream,
                                                builder: (context, durSnap) {
                                                  final dur =
                                                      durSnap.data ??
                                                      player.duration;
                                                  final pos =
                                                      posSnap.data ??
                                                      player.position;
                                                  final totalMs =
                                                      dur?.inMilliseconds ?? 0;
                                                  final posMs =
                                                      pos.inMilliseconds;
                                                  final sliderValue =
                                                      _dragPositionFraction ??
                                                      (totalMs > 0
                                                          ? (posMs / totalMs)
                                                                .clamp(0.0, 1.0)
                                                          : 0.0);

                                                  return Row(
                                                    children: [
                                                      Text(
                                                        _formatDuration(pos),
                                                        style: theme
                                                            .textTheme
                                                            .labelSmall,
                                                      ),
                                                      Expanded(
                                                        child: PlayerAdaptiveSlider(
                                                          value: sliderValue
                                                              .clamp(0.0, 1.0),
                                                          appearance:
                                                              PlayerSliderAppearance
                                                                  .softBlur,
                                                          activeColor: context
                                                              .controlAccent,
                                                          onChanged: totalMs > 0
                                                              ? (v) => setState(
                                                                  () =>
                                                                      _dragPositionFraction =
                                                                          v,
                                                                )
                                                              : null,
                                                          onChangeEnd:
                                                              totalMs > 0
                                                              ? (v) {
                                                                  player.seek(
                                                                    Duration(
                                                                      milliseconds:
                                                                          (v * totalMs)
                                                                              .round(),
                                                                    ),
                                                                  );
                                                                  setState(
                                                                    () =>
                                                                        _dragPositionFraction =
                                                                            null,
                                                                  );
                                                                }
                                                              : null,
                                                        ),
                                                      ),
                                                      Text(
                                                        dur != null
                                                            ? _formatDuration(
                                                                dur,
                                                              )
                                                            : '--:--',
                                                        style: theme
                                                            .textTheme
                                                            .labelSmall,
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          if (playerChrome)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Shuffle',
                                                  icon: Icon(
                                                    Icons.shuffle_rounded,
                                                    color: player.shuffleEnabled
                                                        ? context.controlAccent
                                                        : pal.textSecondary
                                                              .withValues(
                                                                alpha: 0.55,
                                                              ),
                                                  ),
                                                  onPressed:
                                                      player.playlist.length < 2
                                                      ? null
                                                      : () => _notifyShuffle(
                                                          player,
                                                        ),
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  iconSize: 36,
                                                  icon: const Icon(
                                                    Icons.skip_previous_rounded,
                                                  ),
                                                  color: pal.textPrimary,
                                                  onPressed: () =>
                                                      player.skipPrevious(),
                                                ),
                                                const SizedBox(width: 16),
                                                ListenableBuilder(
                                                  listenable: player,
                                                  builder: (context, _) {
                                                    final playing =
                                                        player.isPlaying;
                                                    return IconButton.filled(
                                                      tooltip: playing
                                                          ? 'Pause'
                                                          : 'Play',
                                                      iconSize: 36,
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: context
                                                            .controlAccent,
                                                        foregroundColor:
                                                            Colors.white,
                                                        fixedSize: const Size(
                                                          76,
                                                          76,
                                                        ),
                                                      ),
                                                      onPressed: () => player
                                                          .togglePlayPause(),
                                                      icon: Icon(
                                                        playing
                                                            ? Icons
                                                                  .pause_rounded
                                                            : Icons
                                                                  .play_arrow_rounded,
                                                      ),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 16),
                                                ListenableBuilder(
                                                  listenable: player,
                                                  builder: (context, _) {
                                                    final canNext =
                                                        player.canSkipNext;
                                                    return IconButton(
                                                      tooltip: canNext
                                                          ? 'Next track'
                                                          : 'End of playlist',
                                                      iconSize: 36,
                                                      icon: const Icon(
                                                        Icons.skip_next_rounded,
                                                      ),
                                                      color: canNext
                                                          ? pal.textPrimary
                                                          : pal.textSecondary
                                                                .withValues(
                                                                  alpha: 0.38,
                                                                ),
                                                      onPressed: canNext
                                                          ? () => player
                                                                .skipNext()
                                                          : null,
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  tooltip: 'Repeat mode',
                                                  icon: Icon(
                                                    player.repeatMode ==
                                                            PlaylistRepeatMode
                                                                .one
                                                        ? Icons
                                                              .repeat_one_rounded
                                                        : Icons.repeat_rounded,
                                                    color:
                                                        player.repeatMode ==
                                                            PlaylistRepeatMode
                                                                .off
                                                        ? pal.textSecondary
                                                              .withValues(
                                                                alpha: 0.55,
                                                              )
                                                        : context.controlAccent,
                                                  ),
                                                  onPressed: () =>
                                                      _notifyRepeat(player),
                                                ),
                                              ],
                                            )
                                          else ...[
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Shuffle',
                                                  icon: Icon(
                                                    Icons.shuffle_rounded,
                                                    color: player.shuffleEnabled
                                                        ? context.controlAccent
                                                        : pal.textSecondary
                                                              .withValues(
                                                                alpha: 0.55,
                                                              ),
                                                  ),
                                                  onPressed:
                                                      player.playlist.length < 2
                                                      ? null
                                                      : () => _notifyShuffle(
                                                          player,
                                                        ),
                                                ),
                                                const SizedBox(width: 24),
                                                IconButton(
                                                  tooltip: 'Repeat mode',
                                                  icon: Icon(
                                                    player.repeatMode ==
                                                            PlaylistRepeatMode
                                                                .one
                                                        ? Icons
                                                              .repeat_one_rounded
                                                        : Icons.repeat_rounded,
                                                    color:
                                                        player.repeatMode ==
                                                            PlaylistRepeatMode
                                                                .off
                                                        ? pal.textSecondary
                                                              .withValues(
                                                                alpha: 0.55,
                                                              )
                                                        : context.controlAccent,
                                                  ),
                                                  onPressed: () =>
                                                      _notifyRepeat(player),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                IconButton(
                                                  iconSize: 36,
                                                  icon: const Icon(
                                                    Icons.skip_previous_rounded,
                                                  ),
                                                  color: pal.textPrimary,
                                                  onPressed: () =>
                                                      player.skipPrevious(),
                                                ),
                                                const SizedBox(width: 20),
                                                ListenableBuilder(
                                                  listenable: player,
                                                  builder: (context, _) {
                                                    final playing =
                                                        player.isPlaying;
                                                    return IconButton.filled(
                                                      tooltip: playing
                                                          ? 'Pause'
                                                          : 'Play',
                                                      iconSize: 40,
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: context
                                                            .controlAccent,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              20,
                                                            ),
                                                        elevation: 0,
                                                      ),
                                                      onPressed: () => player
                                                          .togglePlayPause(),
                                                      icon: Icon(
                                                        playing
                                                            ? Icons
                                                                  .pause_rounded
                                                            : Icons
                                                                  .play_arrow_rounded,
                                                      ),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 20),
                                                ListenableBuilder(
                                                  listenable: player,
                                                  builder: (context, _) {
                                                    final canNext =
                                                        player.canSkipNext;
                                                    return IconButton(
                                                      tooltip: canNext
                                                          ? 'Next track'
                                                          : 'End of playlist',
                                                      iconSize: 36,
                                                      icon: const Icon(
                                                        Icons.skip_next_rounded,
                                                      ),
                                                      color: canNext
                                                          ? pal.textPrimary
                                                          : pal.textSecondary
                                                                .withValues(
                                                                  alpha: 0.38,
                                                                ),
                                                      onPressed: canNext
                                                          ? () => player
                                                                .skipNext()
                                                          : null,
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (fullArtNp)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: ListenableBuilder(
                                    listenable: player,
                                    builder: (context, _) {
                                      if (player.currentTrack == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final artWidth = _fullArtHeroWidth(
                                        context,
                                      );
                                      if (daisyNp) {
                                        final bottomInset =
                                            MediaQuery.viewPaddingOf(
                                              context,
                                            ).bottom;
                                        final t = player.currentTrack;
                                        return Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            24,
                                            0,
                                            24,
                                            0,
                                          ),
                                          child: Column(
                                            children: [
                                              const SizedBox(height: 18),
                                              _buildDaisyTransportRow(
                                                player,
                                                artWidth,
                                                pal,
                                              ),
                                              const SizedBox(height: 20),
                                              if (t != null)
                                                _buildDaisyFooterTools(
                                                  context,
                                                  pal: pal,
                                                  player: player,
                                                  track: t,
                                                  width: artWidth,
                                                ),
                                              const Spacer(),
                                              SizedBox(
                                                height: 16 + bottomInset,
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      final silverNp =
                                          context.appliedThemePalette ==
                                          AppThemePalette.silver;
                                      final bottomInset =
                                          MediaQuery.viewPaddingOf(
                                            context,
                                          ).bottom;
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          24,
                                          0,
                                          24,
                                          0,
                                        ),
                                        child: Column(
                                          children: [
                                            if (silverNp)
                                              const SizedBox(height: 8)
                                            else
                                              const Spacer(flex: 2),
                                            _buildSoftBlurTransportRow(
                                              context,
                                              pal: pal,
                                              player: player,
                                              artWidth: artWidth,
                                            ),
                                            SizedBox(
                                              height: silverNp ? 10 : 16,
                                            ),
                                            _buildSoftBlurVolumeBar(
                                              context,
                                              pal: pal,
                                              player: player,
                                              artWidth: artWidth,
                                            ),
                                            const Spacer(),
                                            SizedBox(height: 12 + bottomInset),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (!fullArtNp)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: ListenableBuilder(
                                    listenable: player,
                                    builder: (context, _) {
                                      return _UpNextPanel(
                                        next: player.upcomingTrack,
                                        pal: pal,
                                        theme: theme,
                                        repeatMode: player.repeatMode,
                                        queueLength: player.playlist.length,
                                        playerChrome: playerChrome,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!fullArtNp) _footerTrackTools(context, pal, player),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Frosted glass frame (blur + translucent gradient) around artwork and metadata.
class _NowPlayingAlbumArtCard extends StatefulWidget {
  const _NowPlayingAlbumArtCard({
    required this.playerChrome,
    required this.theme,
    required this.track,
    required this.artwork,
  });

  final bool playerChrome;
  final ThemeData theme;
  final TrackItem track;
  final Widget artwork;

  @override
  State<_NowPlayingAlbumArtCard> createState() =>
      _NowPlayingAlbumArtCardState();
}

class _NowPlayingAlbumArtCardState extends State<_NowPlayingAlbumArtCard> {
  bool get _darkFrosted => widget.theme.brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final accent = context.controlAccent;
    final titleColor = tuneTitleColorForFrostedCard(accent, _darkFrosted);
    
    final outerR = widget.playerChrome ? 32.0 : 24.0;
    final isDark = widget.theme.brightness == Brightness.dark;
    final blurSigma = widget.playerChrome ? 26.0 : 18.0;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.white.withValues(alpha: 0.82);
    final glassBottom = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.68);

    final theme = widget.theme;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      height: 1.25,
      color: titleColor,
    );
    final artistStyle = theme.textTheme.bodyMedium?.copyWith(
      color: titleColor.withValues(alpha: isDark ? 0.78 : 0.72),
    );
    final albumStyle = theme.textTheme.bodySmall?.copyWith(
      color: titleColor.withValues(alpha: isDark ? 0.66 : 0.62),
      fontWeight: FontWeight.w500,
    );
    final artistName = widget.track.artist.trim();
    final showArtist =
        artistName.isNotEmpty && artistName.toLowerCase() != 'unknown artist';
    final albumName = widget.track.metaLine.trim();
    final showAlbum = albumName.isNotEmpty && albumName.toLowerCase() != 'mp3';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.playerChrome ? 0.42 : 0.24,
              ),
              blurRadius: widget.playerChrome ? 28 : 20,
              offset: Offset(0, widget.playerChrome ? 12 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(outerR),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(outerR),
                border: Border.all(width: 1, color: borderColor),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [glassTop, glassBottom],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MarqueeText(
                      widget.track.title,
                      style: titleStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Center(child: widget.artwork),
                    const SizedBox(height: 12),
                    if (showArtist)
                      _MarqueeText(
                        artistName,
                        style: artistStyle,
                        textAlign: TextAlign.center,
                      ),
                    if (showAlbum) ...[
                      const SizedBox(height: 4),
                      _MarqueeText(
                        albumName,
                        style: albumStyle,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText(
    this.text, {
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
    }
  }

  Future<void> _startIfNeeded() async {
    if (!mounted || !_controller.hasClients || _running) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    _running = true;
    while (mounted && _controller.hasClients) {
      final extent = _controller.position.maxScrollExtent;
      if (extent <= 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted || !_controller.hasClients) break;
      await _controller.animateTo(
        extent,
        duration: Duration(milliseconds: (1400 + extent * 6).round()),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || !_controller.hasClients) break;
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    _running = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final fs = style?.fontSize ?? 14;
    final h = style?.height ?? 1.25;
    final lineHeight = fs * h + 4;
    return SizedBox(
      height: lineHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textAlign: widget.textAlign,
                  style: style,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Julia (non-Leah): frosted “Up next” row matching hero glass + primary-tinted labels.
class _UpNextGlassTrackCard extends StatelessWidget {
  const _UpNextGlassTrackCard({
    required this.pal,
    required this.theme,
    required this.track,
  });

  final AppPalette pal;
  final ThemeData theme;
  final TrackItem track;

  static const _r = 22.0;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);
    final glassTop = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.white.withValues(alpha: 0.78);
    final glassBottom = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.62);

    final accent = context.controlAccent;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: accent,
      fontSize: 15,
    );
    final artistStyle = theme.textTheme.bodySmall?.copyWith(
      color: accent.withValues(alpha: 0.78),
      fontSize: 13,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_r),
              border: Border.all(width: 1, color: borderColor),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [glassTop, glassBottom],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TrackAlbumArt(track: track, display: TrackArtDisplay.list),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: artistStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpNextPanel extends StatelessWidget {
  const _UpNextPanel({
    required this.next,
    required this.pal,
    required this.theme,
    required this.repeatMode,
    required this.queueLength,
    required this.playerChrome,
  });

  final TrackItem? next;
  final AppPalette pal;
  final ThemeData theme;
  final PlaylistRepeatMode repeatMode;
  final int queueLength;
  final bool playerChrome;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: pal.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: pal.textPrimary,
    );
    final artistStyle = theme.textTheme.bodyMedium?.copyWith(
      color: pal.textSecondary,
    );

    Widget upNextInner() {
      if (next != null && playerChrome) {
        return _UpNextGlassTrackCard(pal: pal, theme: theme, track: next!);
      }
      if (next != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TrackAlbumArt(track: next!, display: TrackArtDisplay.list),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    next!.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    next!.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: artistStyle,
                  ),
                ],
              ),
            ),
          ],
        );
      }
      if (repeatMode == PlaylistRepeatMode.one &&
          queueLength > 0 &&
          next == null) {
        return Text(
          'This track repeats when it finishes.',
          style: artistStyle?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
          ),
        );
      }
      if (queueLength <= 1) {
        return Text(
          'Only one song in queue.',
          style: artistStyle?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
          ),
        );
      }
      return Text(
        'No more tracks queued.',
        style: artistStyle?.copyWith(
          color: pal.textMuted.withValues(alpha: 0.95),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Up next', style: labelStyle),
              const SizedBox(height: 12),
              upNextInner(),
            ],
          ),
        ),
      ),
    );
  }
}
