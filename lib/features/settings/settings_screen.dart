import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as p;

import '../../services/library_tabs_store.dart';
import '../../services/recent_list_limits_store.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/storage_access.dart';
import '../../theme/accent_color_option.dart';
import '../../theme/app_font_option.dart';
import '../../theme/app_theme.dart';
import '../../theme/player_chrome_background.dart';

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

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsSection { menu, appearance, musicFolders, recentLists }

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  List<LibraryTabRow>? _libraryTabRows;
  _SettingsSection _section = _SettingsSection.menu;
  late final TextEditingController _recentlyAddedLimitController;
  late final TextEditingController _recentlyPlayedLimitController;
  int _recentlyAddedLimit = RecentListLimitsStore.defaultLimit;
  int _recentlyPlayedLimit = RecentListLimitsStore.defaultLimit;

  @override
  void initState() {
    super.initState();
    _recentlyAddedLimitController = TextEditingController();
    _recentlyPlayedLimitController = TextEditingController();
    unawaited(_loadLibraryTabRows());
    unawaited(_loadRecentListLimits());
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

  Future<void> _persistLibraryTabRows(List<LibraryTabRow> rows) async {
    await LibraryTabsStore.saveConfig(rows);
    final next = await LibraryTabsStore.loadConfig();
    if (mounted) setState(() => _libraryTabRows = next);
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

  void _onLibraryTabsReorder(int oldIndex, int newIndex) {
    final rows = _libraryTabRows;
    if (rows == null) return;
    final next = List<LibraryTabRow>.from(rows);
    var ni = newIndex;
    if (ni > oldIndex) ni -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(ni, item);
    unawaited(_persistLibraryTabRows(next));
  }

  void _setLibraryTabEnabled(int index, bool enabled) {
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
    unawaited(_persistLibraryTabRows(next));
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

  Future<void> _addFolder() async {
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
    var selected = widget.playerChromeCustomBackground ?? pal.scaffoldBackground;
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
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: Icon(
            Icons.palette_outlined,
            color: pal.onScaffold.withValues(alpha: 0.88),
            size: 28,
          ),
          title: Text(
            'Appearance',
            style: theme.textTheme.titleMedium?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Theme and accent color',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.95),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: pal.textMuted.withValues(alpha: 0.75),
          ),
          onTap: () => _goToSection(_SettingsSection.appearance),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: Icon(
            Icons.folder_special_outlined,
            color: pal.onScaffold.withValues(alpha: 0.88),
            size: 28,
          ),
          title: Text(
            'Music folders',
            style: theme.textTheme.titleMedium?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Scan paths and Library tabs',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.95),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: pal.textMuted.withValues(alpha: 0.75),
          ),
          onTap: () => _goToSection(_SettingsSection.musicFolders),
        ),
        Divider(height: 1, color: pal.dividerOnHero),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: Icon(
            Icons.history_toggle_off_rounded,
            color: pal.onScaffold.withValues(alpha: 0.88),
            size: 28,
          ),
          title: Text(
            'Recent lists',
            style: theme.textTheme.titleMedium?.copyWith(
              color: pal.onScaffold,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'RecentlyAdded and RecentlyPlayed count',
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.95),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: pal.textMuted.withValues(alpha: 0.75),
          ),
          onTap: () => _goToSection(_SettingsSection.recentLists),
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
        if (widget.themeSetting == AppThemeSetting.player ||
            widget.themeSetting == AppThemeSetting.playerSoft ||
            widget.themeSetting == AppThemeSetting.silver) ...[
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
                onPressed: _busy ? null : _openPlayerChromeBackgroundColorDialog,
                icon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: widget.playerChromeCustomBackground ??
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
                                  : o.swatchColor,
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
                                : o.swatchColor,
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
        const SizedBox(height: 16),
        Text(
          'Library tabs',
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.onScaffold,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose which tabs appear on the Library screen and drag to reorder them.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: pal.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 12),
        if (_libraryTabRows == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: context.controlAccent),
            ),
          )
        else
          SizedBox(
            height: _libraryTabRows!.length * 72.0,
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _libraryTabRows!.length,
              onReorder: _busy ? (_, __) {} : _onLibraryTabsReorder,
              itemBuilder: (ctx, i) {
                final row = _libraryTabRows![i];
                final enabledCount = _libraryTabRows!
                    .where((r) => r.enabled)
                    .length;
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
                        color: pal.onScaffold.withValues(alpha: 0.5),
                      ),
                    ),
                    title: Text(
                      row.id.shortTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: pal.onScaffold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: row.enabled,
                      onChanged: _busy || lastEnabled
                          ? null
                          : (v) => _setLibraryTabEnabled(i, v),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
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
    };

    return ColoredBox(
      color: pal.scaffoldBackground,
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
