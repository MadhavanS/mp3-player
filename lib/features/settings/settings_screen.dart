import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/storage_access.dart';
import '../../theme/accent_color_option.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.folderPaths,
    required this.onFoldersChanged,
    required this.onOpenDrawer,
    required this.themeSetting,
    required this.onThemeSettingChanged,
    required this.accentColorOption,
    required this.onAccentColorOptionChanged,
  });

  final List<String> folderPaths;
  final Future<void> Function(List<String> paths) onFoldersChanged;
  final VoidCallback onOpenDrawer;
  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;
  final AppAccentColorOption accentColorOption;
  final ValueChanged<AppAccentColorOption> onAccentColorOptionChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final paths = widget.folderPaths;

    return ColoredBox(
      color: pal.scaffoldBackground,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        color: pal.onScaffold,
                        tooltip: 'Open menu',
                        onPressed: widget.onOpenDrawer,
                      ),
                      Expanded(
                        child: Text(
                          'Settings',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: pal.onScaffold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Text(
                        'Theme',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatic follows the device clock (light 6:00 a.m.–7:59 p.m., dark otherwise).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pal.onScaffold.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...AppThemeSetting.values.map((s) {
                        final selected = widget.themeSetting == s;
                        final swatches = s.previewSwatches(DateTime.now());
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: pal.surface.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => widget.onThemeSettingChanged(s),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.circle_outlined,
                                        color: selected
                                            ? context.controlAccent
                                            : pal.onScaffold
                                                .withValues(alpha: 0.45),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.label,
                                            style: TextStyle(
                                              color: pal.onScaffold,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            s.subtitle,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: pal.onScaffold
                                                  .withValues(alpha: 0.65),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: SizedBox(
                                              height: 10,
                                              child: Row(
                                                children: [
                                                  for (final c in swatches)
                                                    Expanded(
                                                      child:
                                                          DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: c,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      Text(
                        'Accent color',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Play / pause, notification pills, shuffle and repeat highlights, and key list accents.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pal.onScaffold.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...AppAccentColorOption.values.map((o) {
                        final selected = widget.accentColorOption == o;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: pal.surface.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => widget.onAccentColorOptionChanged(o),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    12, 12, 12, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.circle_outlined,
                                        color: selected
                                            ? context.controlAccent
                                            : pal.onScaffold
                                                .withValues(alpha: 0.45),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            o.label,
                                            style: TextStyle(
                                              color: pal.onScaffold,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            o.subtitle,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: pal.onScaffold
                                                  .withValues(alpha: 0.65),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: SizedBox(
                                              height: 10,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: o.swatchColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      Divider(color: pal.dividerOnHero),
                      const SizedBox(height: 16),
                      Text(
                        'Music folders',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0x33000000)),
                  child: Center(
                    child: CircularProgressIndicator(color: pal.surface),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
