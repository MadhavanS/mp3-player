import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Returns trimmed name, or null if cancelled.
///
/// [TextEditingController] lives in dialog [State] so it is disposed after the
/// route is removed (not when [showDialog]'s future completes), avoiding
/// "used after being disposed" when dismissing with the IME still animating.
Future<String?> showCreatePlaylistNameDialog(BuildContext context) {
  final pal = context.palette;
  final textTheme = Theme.of(context).textTheme;
  return showDialog<String>(
    context: context,
    builder: (_) => _CreatePlaylistNameDialogContent(
      pal: pal,
      textTheme: textTheme,
    ),
  );
}

class _CreatePlaylistNameDialogContent extends StatefulWidget {
  const _CreatePlaylistNameDialogContent({
    required this.pal,
    required this.textTheme,
  });

  final AppPalette pal;
  final TextTheme textTheme;

  @override
  State<_CreatePlaylistNameDialogContent> createState() =>
      _CreatePlaylistNameDialogContentState();
}

class _CreatePlaylistNameDialogContentState
    extends State<_CreatePlaylistNameDialogContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final theme = widget.textTheme;
    return AlertDialog(
      backgroundColor: pal.surface,
      title: Text(
        'Create playlist',
        style: theme.titleLarge?.copyWith(
          color: pal.textPrimary,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: theme.bodyMedium?.copyWith(
            color: pal.textMuted,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: pal.dividerOnHero),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: context.controlAccent,
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: (v) {
          final t = v.trim();
          if (t.isNotEmpty) Navigator.of(context).pop(t);
        },
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isNotEmpty) Navigator.of(context).pop(t);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
