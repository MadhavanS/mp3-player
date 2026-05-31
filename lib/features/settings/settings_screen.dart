import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../platform/windows_window.dart';
import '../../services/library_tabs_store.dart';
import '../../services/recent_list_limits_store.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/songs_alpha_index_store.dart';
import '../../services/storage_access.dart';
import '../../theme/accent_color_option.dart';
import '../../theme/app_font_option.dart';
import '../../theme/app_theme.dart';
import '../../theme/player_chrome_background.dart';
import '../../widgets/daisy_background.dart';
import '../../widgets/player_adaptive_controls.dart';
import '../help/help_screen.dart';
import 'sound_settings_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.folderPaths,
    required this.onFoldersChanged,
    required this.onOpenDrawer,
    required this.themeSetting,
    required this.onThemeSettingChanged,
    required this.fontOption,
    required this.onFontOptionChanged,
    required this.accentColorOption,
    required this.customAccentColor,
    required this.onAccentColorOptionChanged,
    required this.onCustomAccentColorChanged,
    required this.playerChromeBackgroundKind,
    required this.playerChromeCustomBackground,
    required this.onPlayerChromeBackgroundKindChanged,
    required this.onPlayerChromeCustomBackgroundChanged,
    required this.onEraseAllAppData,
  });

  final List<String> folderPaths;
  final Future<void> Function(List<String> paths) onFoldersChanged;
  final VoidCallback onOpenDrawer;
  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;
  final AppFontOption fontOption;
  final ValueChanged<AppFontOption> onFontOptionChanged;
  final AppAccentColorOption accentColorOption;
  final Color customAccentColor;
  final ValueChanged<AppAccentColorOption> onAccentColorOptionChanged;
  final ValueChanged<Color> onCustomAccentColorChanged;
  final PlayerChromeBackgroundKind playerChromeBackgroundKind;
  final Color? playerChromeCustomBackground;
  final ValueChanged<PlayerChromeBackgroundKind>
  onPlayerChromeBackgroundKindChanged;
  final ValueChanged<Color> onPlayerChromeCustomBackgroundChanged;
  final Future<void> Function() onEraseAllAppData;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsSection {
  menu,
  appearance,
  musicFolders,
  recentLists,
  sound,
  experiments,
  storage,
  help,
  windows,
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  List<LibraryTabRow>? _libraryTabRows;
  _SettingsSection _section = _SettingsSection.menu;
  late final TextEditingController _recentlyAddedLimitController;
  late final TextEditingController _recentlyPlayedLimitController;
  int _recentlyAddedLimit = RecentListLimitsStore.defaultLimit;
  int _recentlyPlayedLimit = RecentListLimitsStore.defaultLimit;
  bool _windowsAlwaysOnTop = false;
  bool _windowsWindowPrefsLoaded = false;
  bool _songsAlphaIndexExperiment = false;

  static bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _recentlyAddedLimitController = TextEditingController();
    _recentlyPlayedLimitController = TextEditingController();
    unawaited(_loadLibraryTabRows());
    unawaited(_loadRecentListLimits());
    unawaited(_loadWindowsWindowPrefs());
    unawaited(_loadSongsAlphaExperiment());
  }

  Future<void> _loadSongsAlphaExperiment() async {
    final on = await SongsAlphaIndexStore.loadExperimentEnabled();
    if (mounted) setState(() => _songsAlphaIndexExperiment = on);
  }

  Future<void> _loadWindowsWindowPrefs() async {
    if (!_isWindowsDesktop) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _windowsAlwaysOnTop = prefs.getBool(kWindowsAlwaysOnTopPrefKey) ?? false;
      _windowsWindowPrefsLoaded = true;
    });
  }

  @override
  void dispose() {
    _recentlyAddedLimitController.dispose();
    _recentlyPlayedLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadLibraryTabRows() async {
    final rows = await LibraryTabsStore.loadConfig();
    if (mounted) setState(() => _libraryTabRows = rows);
  }

  Future<void> _persistLibraryTabRows(
    List<LibraryTabRow> rows, {
    VoidCallback? onUpdated,
  }) async {
    await LibraryTabsStore.saveConfig(rows);
    final next = await LibraryTabsStore.loadConfig();
    if (mounted) setState(() => _libraryTabRows = next);
    onUpdated?.call();
  }

  String _libraryTabsSummary() {
    final rows = _libraryTabRows;
    if (rows == null) return 'Loading…';
    final enabled = rows.where((r) => r.enabled).length;
    return '$enabled of ${rows.length} tabs enabled';
  }

  Future<void> _loadRecentListLimits() async {
    final added = await RecentListLimitsStore.loadRecentlyAddedLimit();
    final played = await RecentListLimitsStore.loadRecentlyPlayedLimit();
    if (!mounted) return;
    setState(() {
      _recentlyAddedLimit = added;
      _recentlyPlayedLimit = played;
      _recentlyAddedLimitController.text = added.toString();
      _recentlyPlayedLimitController.text = played.toString();
    });
  }

  int? _parseLimitOrNull(String raw) {
    final v = int.tryParse(raw.trim());
    if (v == null || v < 1) return null;
    return v > 500 ? 500 : v;
  }

  Future<void> _saveRecentListLimit({
    required bool forRecentlyAdded,
    required String raw,
  }) async {
    final parsed = _parseLimitOrNull(raw);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number from 1 to 500.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      if (forRecentlyAdded) {
        await RecentListLimitsStore.saveRecentlyAddedLimit(parsed);
        await RecentlyAddedStore.trimToConfiguredLimit();
      } else {
        await RecentListLimitsStore.saveRecentlyPlayedLimit(parsed);
        await RecentlyPlayedStore.trimToConfiguredLimit();
      }
      if (!mounted) return;
      setState(() {
        if (forRecentlyAdded) {
          _recentlyAddedLimit = parsed;
          _recentlyAddedLimitController.text = parsed.toString();
        } else {
          _recentlyPlayedLimit = parsed;
          _recentlyPlayedLimitController.text = parsed.toString();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forRecentlyAdded
                ? 'RecentlyAdded limit updated.'
                : 'RecentlyPlayed limit updated.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onLibraryTabsReorder(
    int oldIndex,
    int newIndex, {
    VoidCallback? onUpdated,
  }) {
    final rows = _libraryTabRows;
    if (rows == null) return;
    final next = List<LibraryTabRow>.from(rows);
    var ni = newIndex;
    if (ni > oldIndex) ni -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(ni, item);
    unawaited(_persistLibraryTabRows(next, onUpdated: onUpdated));
  }

  void _setLibraryTabEnabled(
    int index,
    bool enabled, {
    VoidCallback? onUpdated,
  }) {
    final rows = _libraryTabRows;
    if (rows == null) return;
    final next = List<LibraryTabRow>.from(rows);
    if (!enabled) {
      final nEnabled = next.where((r) => r.enabled).length;
      if (next[index].enabled && nEnabled <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keep at least one library tab enabled.'),
          ),
        );
        return;
      }
    }
    next[index] = LibraryTabRow(id: next[index].id, enabled: enabled);
    unawaited(_persistLibraryTabRows(next, onUpdated: onUpdated));
  }

  Future<void> _showLibraryTabsSettingsDialog() async {
    if (_libraryTabRows == null) await _loadLibraryTabRows();
    if (!mounted) return;

    final theme = Theme.of(context);
    final pal = context.palette;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void refreshDialog() => setDialogState(() {});

            return AlertDialog(
              backgroundColor: pal.surface,
              title: Text(
                'Library',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: pal.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose which tabs appear on the Library screen and drag to reorder them.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: pal.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLibraryTabsReorderList(
                        theme,
                        pal,
                        onUpdated: refreshDialog,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.controlAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Widget _buildLibraryTabsReorderList(
    ThemeData theme,
    AppPalette pal, {
    VoidCallback? onUpdated,
  }) {
    if (_libraryTabRows == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: context.controlAccent),
        ),
      );
    }

    final rows = _libraryTabRows!;
    return SizedBox(
      height: rows.length * 72.0,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: rows.length,
        onReorder: _busy
            ? (_, __) {}
            : (oldIndex, newIndex) => _onLibraryTabsReorder(
                oldIndex,
                newIndex,
                onUpdated: onUpdated,
              ),
        itemBuilder: (ctx, i) {
          final row = rows[i];
          final enabledCount = rows.where((r) => r.enabled).length;
          final lastEnabled = row.enabled && enabledCount <= 1;
          return Material(
            key: ValueKey(row.id.wireValue),
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 4,
              ),
              leading: ReorderableDragStartListener(
                index: i,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: pal.textMuted.withValues(alpha: 0.85),
                ),
              ),
              title: Text(
                row.id.shortTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: pal.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: PlayerAdaptiveSwitch(
                value: row.enabled,
                onChanged: _busy || lastEnabled
                    ? null
                    : (v) => _setLibraryTabEnabled(i, v, onUpdated: onUpdated),
                activeColor: context.controlAccent,
              ),
            ),
          );
        },
      ),
    );
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

  Future<void> _showContentUriFolderDialog() async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Folder not accessible'),
        content: const Text(
          'Please pick a folder from internal storage.\n\n'
          '• Tap ☰ in the picker\n'
          '• Choose "Internal storage" or your SD card\n'
          '• Avoid "Recent", "Downloads", or cloud folders',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (retry == true && mounted) {
      await _addFolder();
    }
  }

  Future<void> _addFolder() async {
    final allowed = await ensureCanReadMusicFiles(context);
    if (!allowed || !mounted) return;

    final picked = await pickMusicDirectory();
    if (!mounted || picked == null) return;

    final trimmed = picked.trim();
    if (trimmed.startsWith('content:')) {
      if (!mounted) return;
      await _showContentUriFolderDialog();
      return;
    }

    final normalized = _normalizePickPath(trimmed);
    if (normalized == null) {
      if (!mounted) return;
      await _showContentUriFolderDialog();
      return;
    }

    final next = List<String>.from(widget.folderPaths);
    if (next.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That folder is already in your list.')),
      );
      return;
    }
    next.add(normalized);

    setState(() => _busy = true);
    try {
      await widget.onFoldersChanged(next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAt(int index) async {
    if (index < 0 || index >= widget.folderPaths.length) return;
    final next = List<String>.from(widget.folderPaths)..removeAt(index);
    setState(() => _busy = true);
    try {
      await widget.onFoldersChanged(next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _appearanceDropdownDecoration(AppPalette pal) {
    return InputDecoration(
      filled: true,
      fillColor: pal.surface.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<void> _openCustomAccentDialog() async {
    if (!mounted || _busy) return;
    final pal = context.palette;
    var selected = widget.customAccentColor;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              backgroundColor: pal.surface,
              title: Text(
                'Custom accent',
                style: TextStyle(color: pal.textPrimary),
              ),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selected,
                  onColorChanged: (c) => setSt(() => selected = c),
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hsvWithHue,
                  pickerAreaBorderRadius: const BorderRadius.all(
                    Radius.circular(12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: pal.textSecondary),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    widget.onCustomAccentColorChanged(selected);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openPlayerChromeBackgroundColorDialog() async {
    if (!mounted || _busy) return;
    final pal = context.palette;
    var selected =
        widget.playerChromeCustomBackground ?? pal.scaffoldBackground;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              backgroundColor: pal.surface,
              title: Text(
                'App background color',
                style: TextStyle(color: pal.textPrimary),
              ),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selected,
                  onColorChanged: (c) => setSt(() => selected = c),
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hsvWithHue,
                  pickerAreaBorderRadius: const BorderRadius.all(
                    Radius.circular(12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: pal.textSecondary),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    widget.onPlayerChromeCustomBackgroundChanged(selected);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmEraseAllAppData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final pal = dialogContext.palette;
        return AlertDialog(
          backgroundColor: pal.surface,
          title: Text(
            'Erase all app data?',
            style: theme.textTheme.titleLarge?.copyWith(
              color: pal.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'This permanently deletes settings, music folders, playlists, '
            'favorites, playback history, metadata cache, and album-art cache '
            'on this device.\n\n'
            'Your MP3 files on storage are not deleted.\n\n'
            'MadPlayer will close. Reopen the app for a completely fresh start.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: pal.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Erase everything'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.onEraseAllAppData();
    } catch (e, st) {
      debugPrint('eraseAllAppData: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not erase app data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToSection(_SettingsSection section) {
    setState(() => _section = section);
  }

  void _goToMenu() {
    setState(() => _section = _SettingsSection.menu);
  }

  Widget _settingsHeader(ThemeData theme, AppPalette pal, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      child: Row(
        children: [
          if (_section == _SettingsSection.menu)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              color: pal.onScaffold,
              tooltip: 'Open menu',
              onPressed: widget.onOpenDrawer,
            )
          else
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: pal.onScaffold,
              tooltip: 'Back',
              onPressed: _goToMenu,
            ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: pal.onScaffold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsMenuTile({
    required AppPalette pal,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        leading: Icon(
          icon,
          color: pal.onScaffold.withValues(alpha: 0.88),
          size: 28,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.onScaffold,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: pal.textMuted.withValues(alpha: 0.75),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildMainMenu(ThemeData theme, AppPalette pal) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Pick a category to change theme, accent colors, or where your music is scanned.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: pal.textSecondary.withValues(alpha: 0.95),
            ),
          ),
        ),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Theme and accent color',
          onTap: () => _goToSection(_SettingsSection.appearance),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.folder_special_outlined,
          title: 'Music folders',
          subtitle: 'Scan paths and library options',
          onTap: () => _goToSection(_SettingsSection.musicFolders),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.history_toggle_off_rounded,
          title: 'Recent lists',
          subtitle: 'RecentlyAdded and RecentlyPlayed count',
          onTap: () => _goToSection(_SettingsSection.recentLists),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.graphic_eq_rounded,
          title: 'Sound',
          subtitle: 'Loudness boost and equalizer presets',
          onTap: () => _goToSection(_SettingsSection.sound),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.science_outlined,
          title: 'Experiments',
          subtitle: 'Optional library features in development',
          onTap: () => _goToSection(_SettingsSection.experiments),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.storage_outlined,
          title: 'Storage & data',
          subtitle: 'Clear caches and reset app to factory state',
          onTap: () => _goToSection(_SettingsSection.storage),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        _settingsMenuTile(
          pal: pal,
          theme: theme,
          icon: Icons.help_outline_rounded,
          title: 'Help',
          subtitle: 'Search filters and library tips',
          onTap: () => _goToSection(_SettingsSection.help),
        ),
        if (_isWindowsDesktop) ...[
          Divider(height: 1, color: pal.dividerOnHero),
          _settingsMenuTile(
            pal: pal,
            theme: theme,
            icon: Icons.desktop_windows_outlined,
            title: 'Windows',
            subtitle: 'Always on top and window size',
            onTap: () => _goToSection(_SettingsSection.windows),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWindowsDetail(ThemeData theme, AppPalette pal) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(
          'These options apply to the Windows desktop build only.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Always on top',
            style: theme.textTheme.titleSmall?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Keep MadPlayer above other windows',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.95),
            ),
          ),
          value: _windowsAlwaysOnTop,
          onChanged: !_windowsWindowPrefsLoaded || _busy
              ? null
              : (v) {
                  setState(() => _windowsAlwaysOnTop = v);
                  unawaited(setWindowsAlwaysOnTop(v));
                },
        ),
        const SizedBox(height: 12),
        Text(
          'The app opens in a tall, narrow window by default (similar to a phone '
          'in portrait). You can still resize it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRecentListsDetail(ThemeData theme, AppPalette pal) {
    Widget compactLimitRow({
      required String title,
      required TextEditingController controller,
      required VoidCallback onSave,
    }) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: pal.surface.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.dividerOnHero.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.onScaffold.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 86,
              child: TextField(
                controller: controller,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '30',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: pal.surface.withValues(alpha: 0.38),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: pal.dividerOnHero.withValues(alpha: 0.7),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: pal.dividerOnHero.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                onSubmitted: (_) => onSave(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Save',
              onPressed: _busy ? null : onSave,
              icon: Icon(
                Icons.check_circle_rounded,
                color: context.controlAccent,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(
          'Control how many songs are shown in RecentlyAdded and RecentlyPlayed. '
          'If count exceeds this value, oldest entries are removed.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Default value: 30',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 12),
        compactLimitRow(
          title: 'RecentlyAdded',
          controller: _recentlyAddedLimitController,
          onSave: () => unawaited(
            _saveRecentListLimit(
              forRecentlyAdded: true,
              raw: _recentlyAddedLimitController.text,
            ),
          ),
        ),
        const SizedBox(height: 10),
        compactLimitRow(
          title: 'RecentlyPlayed',
          controller: _recentlyPlayedLimitController,
          onSave: () => unawaited(
            _saveRecentListLimit(
              forRecentlyAdded: false,
              raw: _recentlyPlayedLimitController.text,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Current values: RecentlyAdded $_recentlyAddedLimit, RecentlyPlayed $_recentlyPlayedLimit',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  AppThemeSetting get _appearanceThemeDropdownValue {
    final s = widget.themeSetting;
    return appearanceThemeChoices.contains(s) ? s : AppThemeSetting.automatic;
  }

  Widget _buildAppearanceDetail(ThemeData theme, AppPalette pal) {
    final activePalette = context.appliedThemePalette;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(
          'Theme controls backgrounds; accent controls play buttons, '
          'toasts, sliders, and highlights.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Theme',
          style: theme.textTheme.titleSmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.92),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: _appearanceDropdownDecoration(pal).copyWith(
            labelText: 'App theme',
            labelStyle: TextStyle(
              color: pal.onScaffold.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AppThemeSetting>(
              value: _appearanceThemeDropdownValue,
              isExpanded: true,
              dropdownColor: pal.surface,
              style: TextStyle(color: pal.textPrimary, fontSize: 15),
              iconEnabledColor: pal.onScaffold.withValues(alpha: 0.85),
              items: [
                for (final s in appearanceThemeChoices)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) widget.onThemeSettingChanged(v);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.themeSetting.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.65),
          ),
        ),
        if (widget.themeSetting == AppThemeSetting.julia ||
            widget.themeSetting == AppThemeSetting.leah ||
            widget.themeSetting == AppThemeSetting.silver ||
            widget.themeSetting == AppThemeSetting.daisy ||
            widget.themeSetting == AppThemeSetting.ivy) ...[
          const SizedBox(height: 20),
          Text(
            'Background',
            style: theme.textTheme.titleSmall?.copyWith(
              color: pal.onScaffold.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Applies across the whole app. Separate from accent color.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.onScaffold.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: _appearanceDropdownDecoration(pal).copyWith(
              labelText: 'Background',
              labelStyle: TextStyle(
                color: pal.onScaffold.withValues(alpha: 0.72),
                fontSize: 13,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<PlayerChromeBackgroundKind>(
                value: widget.playerChromeBackgroundKind,
                isExpanded: true,
                dropdownColor: pal.surface,
                style: TextStyle(color: pal.textPrimary, fontSize: 15),
                iconEnabledColor: pal.onScaffold.withValues(alpha: 0.85),
                items: [
                  for (final k in PlayerChromeBackgroundKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) {
                          widget.onPlayerChromeBackgroundKindChanged(v);
                        }
                      },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppPalette.chromeBackgroundKindDetail(
              widget.playerChromeBackgroundKind,
              widget.themeSetting,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.onScaffold.withValues(alpha: 0.65),
            ),
          ),
          if (widget.playerChromeBackgroundKind ==
              PlayerChromeBackgroundKind.custom) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : _openPlayerChromeBackgroundColorDialog,
                icon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color:
                        widget.playerChromeCustomBackground ??
                        pal.scaffoldBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: pal.onScaffold.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                label: const Text('Choose background color'),
              ),
            ),
          ],
        ],
        const SizedBox(height: 22),
        Text(
          'Font',
          style: theme.textTheme.titleSmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.92),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: _appearanceDropdownDecoration(pal).copyWith(
            labelText: 'Player font',
            labelStyle: TextStyle(
              color: pal.onScaffold.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AppFontOption>(
              value: widget.fontOption,
              isExpanded: true,
              dropdownColor: pal.surface,
              style: TextStyle(color: pal.textPrimary, fontSize: 15),
              iconEnabledColor: pal.onScaffold.withValues(alpha: 0.85),
              items: [
                for (final o in AppFontOption.values)
                  DropdownMenuItem(value: o, child: Text(o.label)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) widget.onFontOptionChanged(v);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.fontOption.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Accent color',
          style: theme.textTheme.titleSmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.92),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: _appearanceDropdownDecoration(pal).copyWith(
            labelText: 'Accent',
            labelStyle: TextStyle(
              color: pal.onScaffold.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AppAccentColorOption>(
              value: widget.accentColorOption,
              isExpanded: true,
              dropdownColor: pal.surface,
              style: TextStyle(color: pal.textPrimary, fontSize: 15),
              iconEnabledColor: pal.onScaffold.withValues(alpha: 0.85),
              selectedItemBuilder: (context) {
                return [
                  for (final o in AppAccentColorOption.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: o == AppAccentColorOption.custom
                                  ? widget.customAccentColor
                                  : o.resolveColorForPalette(
                                      activePalette,
                                      customColor: widget.customAccentColor,
                                    ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: pal.onScaffold.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              o.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: pal.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ];
              },
              items: [
                for (final o in AppAccentColorOption.values)
                  DropdownMenuItem(
                    value: o,
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: o == AppAccentColorOption.custom
                                ? widget.customAccentColor
                                : o.resolveColorForPalette(
                                    activePalette,
                                    customColor: widget.customAccentColor,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: pal.onScaffold.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(o.label, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) widget.onAccentColorOptionChanged(v);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.accentColorOption.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.onScaffold.withValues(alpha: 0.65),
          ),
        ),
        if (widget.accentColorOption == AppAccentColorOption.custom) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.customAccentColor,
                  border: Border.all(
                    color: pal.onScaffold.withValues(alpha: 0.2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _openCustomAccentDialog,
                  icon: Icon(
                    Icons.color_lens_outlined,
                    size: 20,
                    color: context.controlAccent,
                  ),
                  label: const Text('Choose color'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMusicFoldersDetail(ThemeData theme, AppPalette pal) {
    final paths = widget.folderPaths;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(
          'Add directories to scan for MP3 files. Paths are saved and loaded when you open the app.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 12),
        if (paths.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No folders yet. Tap the button below to add one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: pal.onScaffold.withValues(alpha: 0.75),
              ),
            ),
          )
        else
          ...paths.asMap().entries.map((e) {
            final i = e.key;
            final path = e.value;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    p.basename(path),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: pal.onScaffold,
                    ),
                  ),
                  subtitle: Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: pal.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: pal.onScaffold.withValues(alpha: 0.85),
                    tooltip: 'Remove folder',
                    onPressed: _busy ? null : () => _removeAt(i),
                  ),
                ),
                Divider(height: 1, color: pal.dividerOnHero),
              ],
            );
          }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _addFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add folder'),
          style: FilledButton.styleFrom(
            backgroundColor: pal.surface,
            foregroundColor: context.controlAccent,
          ),
        ),
        const SizedBox(height: 28),
        Divider(color: pal.dividerOnHero),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.library_music_outlined,
            color: pal.onScaffold.withValues(alpha: 0.88),
          ),
          title: Text(
            'Library',
            style: theme.textTheme.titleMedium?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            _libraryTabsSummary(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.9),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: pal.textMuted.withValues(alpha: 0.75),
          ),
          onTap: _busy ? null : _showLibraryTabsSettingsDialog,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStorageDetail(ThemeData theme, AppPalette pal) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Erase everything MadPlayer stores on this device — the same as a '
          'clean install with no restored settings. Your music files on disk or '
          'SD card are not touched.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Removed:\n'
          '• Theme, accent, font, and sound settings\n'
          '• Music folder list and library metadata cache\n'
          '• Playlists, favorites, and recently played\n'
          '• Album-art and notification art caches\n'
          '• Android home-screen widget state',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.95),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_confirmEraseAllAppData()),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Erase all app data'),
        ),
        const SizedBox(height: 12),
        Text(
          'The app closes after a successful wipe. Reopen MadPlayer to set up '
          'from scratch.\n\n'
          'Tip: Android may restore old settings after reinstall if backup was '
          'enabled for a previous build. This option clears data without '
          'reinstalling.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: pal.textMuted.withValues(alpha: 0.9),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildExperimentsDetail(ThemeData theme, AppPalette pal) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'These options are off by default and may change or be removed later.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Songs tab: alphabet quick index',
            style: theme.textTheme.titleSmall?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            _songsAlphaIndexExperiment
                ? 'The A–Z rail and toggle appear under Library › Songs (sort menu).'
                : 'When enabled, you can turn on the A–Z side index from the Songs sort menu.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.95),
            ),
          ),
          value: _songsAlphaIndexExperiment,
          onChanged: _busy
              ? null
              : (v) async {
                  setState(() => _busy = true);
                  try {
                    await SongsAlphaIndexStore.saveExperimentEnabled(v);
                    if (mounted) setState(() => _songsAlphaIndexExperiment = v);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final title = switch (_section) {
      _SettingsSection.menu => 'Settings',
      _SettingsSection.appearance => 'Appearance',
      _SettingsSection.musicFolders => 'Music folders',
      _SettingsSection.recentLists => 'Recent lists',
      _SettingsSection.sound => 'Sound',
      _SettingsSection.experiments => 'Experiments',
      _SettingsSection.storage => 'Storage & data',
      _SettingsSection.help => 'Help',
      _SettingsSection.windows => 'Windows',
    };

    return DaisyBackground(
      baseColor: pal.scaffoldBackground,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _settingsHeader(theme, pal, title),
                Expanded(
                  child: switch (_section) {
                    _SettingsSection.menu => _buildMainMenu(theme, pal),
                    _SettingsSection.appearance => _buildAppearanceDetail(
                      theme,
                      pal,
                    ),
                    _SettingsSection.musicFolders => _buildMusicFoldersDetail(
                      theme,
                      pal,
                    ),
                    _SettingsSection.recentLists => _buildRecentListsDetail(
                      theme,
                      pal,
                    ),
                    _SettingsSection.sound => const SoundSettingsPanel(),
                    _SettingsSection.experiments => _buildExperimentsDetail(
                      theme,
                      pal,
                    ),
                    _SettingsSection.storage => _buildStorageDetail(theme, pal),
                    _SettingsSection.help => const HelpContent(),
                    _SettingsSection.windows => _buildWindowsDetail(theme, pal),
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
