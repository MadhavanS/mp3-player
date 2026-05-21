import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/daisy_background.dart';
import 'search_help_text.dart';

/// Scrollable help topics (search syntax, multi-select, etc.).
class HelpContent extends StatelessWidget {
  const HelpContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final ivy = context.appliedThemePalette == AppThemePalette.ivy;
    final ink = ivy ? const Color(0xFF1C1C1E) : pal.onScaffold;
    final secondary = ivy
        ? const Color(0xFF48484A)
        : pal.textSecondary.withValues(alpha: 0.95);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text(
          'Quick reference for search filters and library actions.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        _HelpSection(
          title: 'Library search',
          titleColor: ink,
          children: [
            _HelpPoint(
              body:
                  'On Songs, Favourites, Recently added, Recently played, and Now playing list, type at least ${SearchHelpText.libraryMinChars} characters to filter.',
              bodyColor: secondary,
              theme: theme,
            ),
            _HelpPoint(
              label: 'Field hint',
              body: SearchHelpText.libraryTrackFieldHint,
              bodyColor: secondary,
              theme: theme,
              monospace: true,
            ),
            _HelpPoint(
              label: 's:',
              body: 'Search song title (example: s:love)',
              bodyColor: secondary,
              theme: theme,
            ),
            _HelpPoint(
              label: 'a:',
              body: 'Search artist (example: a:beatles)',
              bodyColor: secondary,
              theme: theme,
            ),
            _HelpPoint(
              label: 'm:',
              body: 'Search album / movie line (example: m:jazz)',
              bodyColor: secondary,
              theme: theme,
            ),
            _HelpPoint(
              body:
                  'With no prefix, the same ${SearchHelpText.libraryMinChars}-character minimum applies and matches title (and filename on some tabs).',
              bodyColor: secondary,
              theme: theme,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _HelpSection(
          title: 'Playlists tab',
          titleColor: ink,
          children: [
            _HelpPoint(
              label: 'Field hint',
              body: SearchHelpText.playlistTabFieldHint,
              bodyColor: secondary,
              theme: theme,
              monospace: true,
            ),
            _HelpPoint(
              body:
                  'Filters your saved playlist names. Minimum ${SearchHelpText.libraryMinChars} characters.',
              bodyColor: secondary,
              theme: theme,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _HelpSection(
          title: 'Files browser',
          titleColor: ink,
          children: [
            _HelpPoint(
              label: 'Field hint',
              body: SearchHelpText.filesFieldHint,
              bodyColor: secondary,
              theme: theme,
              monospace: true,
            ),
            _HelpPoint(
              body:
                  'Narrows folders and track titles while you browse music on disk.',
              bodyColor: secondary,
              theme: theme,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _HelpSection(
          title: 'Songs multi-select',
          titleColor: ink,
          children: [
            _HelpPoint(
              body:
                  'On the Songs tab, tap the checklist icon in the top bar or long-press a song to select multiple tracks.',
              bodyColor: secondary,
              theme: theme,
            ),
            _HelpPoint(
              body:
                  'Use Play to start the selection in list order, or Playlist to create or add to a user playlist.',
              bodyColor: secondary,
              theme: theme,
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-screen help opened from the side menu.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return DaisyBackground(
      baseColor: pal.scaffoldBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: pal.onScaffold,
                    tooltip: 'Back',
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      'Help',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: pal.onScaffold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: HelpContent()),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.titleColor,
    required this.children,
  });

  final String title;
  final Color titleColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class _HelpPoint extends StatelessWidget {
  const _HelpPoint({
    required this.body,
    required this.bodyColor,
    required this.theme,
    this.label,
    this.monospace = false,
  });

  final String? label;
  final String body;
  final Color bodyColor;
  final ThemeData theme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final accent = context.controlAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Icon(
              Icons.circle,
              size: 6,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  body,
                  style: (monospace
                          ? theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            )
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                    color: bodyColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
