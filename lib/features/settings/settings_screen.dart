import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/storage_access.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.folderPaths,
    required this.onFoldersChanged,
    required this.onOpenDrawer,
    required this.themeSetting,
    required this.onThemeSettingChanged,
  });

  final List<String> folderPaths;
  final Future<void> Function(List<String> paths) onFoldersChanged;
  final VoidCallback onOpenDrawer;
  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;

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
                        return ListTile(
                          onTap: _busy
                              ? null
                              : () => widget.onThemeSettingChanged(s),
                          leading: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: selected ? pal.primary : pal.onScaffold.withValues(alpha: 0.45),
                          ),
                          title: Text(
                            s.label,
                            style: TextStyle(
                              color: pal.onScaffold,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            s.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: pal.onScaffold.withValues(alpha: 0.65),
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
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
                          foregroundColor: pal.primary,
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
