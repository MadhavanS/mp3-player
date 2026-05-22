import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact strip shown on the library when no music folders are configured.
class LibrarySetupBanner extends StatelessWidget {
  const LibrarySetupBanner({
    super.key,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: context.controlAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onOpenSettings,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  color: context.controlAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add your music folders',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Settings → Music folders → choose a folder with MP3s',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pal.textSecondary.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: pal.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-tab empty state when the library has no songs yet.
class LibrarySetupEmptyState extends StatelessWidget {
  const LibrarySetupEmptyState({
    super.key,
    required this.hasMusicFolders,
    required this.onOpenSettings,
  });

  final bool hasMusicFolders;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    final title = hasMusicFolders
        ? 'No songs found yet'
        : 'Your library is empty';
    final body = hasMusicFolders
        ? 'No MP3 files were found in your saved folders. Add another folder '
            'in Settings, or move music into an existing folder and refresh.'
        : 'MadPlayer needs at least one folder that contains your MP3 files. '
            'We will scan it and list every song in your library.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasMusicFolders
                  ? Icons.audio_file_outlined
                  : Icons.library_music_outlined,
              size: 56,
              color: pal.onScaffold.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: pal.onScaffold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: pal.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            if (!hasMusicFolders) ...[
              const SizedBox(height: 20),
              _SetupStepsList(pal: pal, theme: theme),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_rounded),
              label: Text(
                hasMusicFolders ? 'Open Music folders' : 'Add music folders',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupStepsList extends StatelessWidget {
  const _SetupStepsList({required this.pal, required this.theme});

  final AppPalette pal;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Open Settings from the menu (☰)',
      'Tap Music folders',
      'Tap Add folder and pick a folder with MP3 files',
      'Return to Library — your songs appear after scanning',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.controlAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.controlAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    steps[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: pal.onScaffold.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
