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
  });

  final List<String> folderPaths;
  final Future<void> Function(List<String> paths) onFoldersChanged;
  final VoidCallback onOpenDrawer;

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
    final paths = widget.folderPaths;

    return ColoredBox(
      color: AppColors.navy,
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
                        color: AppColors.textOnNavy,
                        tooltip: 'Open menu',
                        onPressed: widget.onOpenDrawer,
                      ),
                      Expanded(
                        child: Text(
                          'Music folders',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppColors.textOnNavy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Add directories to scan for MP3 files. Paths are saved and loaded when you open the app.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary.withOpacity(0.95),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: paths.isEmpty
                      ? Center(
                          child: Text(
                            'No folders yet. Tap the button below to add one.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppColors.textOnNavy.withOpacity(0.75),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: paths.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: Color(0x22FFFFFF),
                          ),
                          itemBuilder: (context, i) {
                            final path = paths[i];
                            return ListTile(
                              title: Text(
                                p.basename(path),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppColors.textOnNavy,
                                ),
                              ),
                              subtitle: Text(
                                path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted.withOpacity(0.9),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                color: AppColors.textOnNavy.withOpacity(0.85),
                                tooltip: 'Remove folder',
                                onPressed: _busy ? null : () => _removeAt(i),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _addFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add folder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            if (_busy)
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
  }
}
