import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../util/format_bytes.dart';

Future<void> showSavedYoutubeAudioInfoDialog(
  BuildContext context,
  TrackItem track,
) async {
  final fp = track.filePath?.trim();
  if (fp == null || fp.isEmpty) return;

  int? sizeBytes;
  DateTime? modified;
  var exists = false;
  try {
    final f = File(fp);
    exists = await f.exists();
    if (exists) {
      sizeBytes = await f.length();
      modified = await f.lastModified();
    }
  } catch (_) {}

  if (!context.mounted) return;
  final pal = context.palette;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Saved audio info'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(track.title, style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              track.artist,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: pal.textMuted,
                  ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'File', value: p.basename(fp)),
            const SizedBox(height: 8),
            _InfoRow(label: 'Folder', value: p.dirname(fp)),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Size',
              value: sizeBytes != null
                  ? formatFileSize(sizeBytes)
                  : (exists ? 'Unknown' : 'File missing'),
            ),
            if (modified != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Modified',
                value:
                    '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
                    '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}',
              ),
            ],
            if (track.youtubeVideoId != null) ...[
              const SizedBox(height: 8),
              _InfoRow(label: 'Video id', value: track.youtubeVideoId!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showSavedYoutubeLinkInfoDialog(
  BuildContext context,
  TrackItem track,
) async {
  if (!context.mounted) return;
  final pal = context.palette;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Saved link info'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(track.title, style: Theme.of(ctx).textTheme.titleSmall),
          const SizedBox(height: 8),
          _InfoRow(label: 'Artist', value: track.artist),
          if (track.youtubeVideoId != null) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Video id', value: track.youtubeVideoId!),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'URL',
              value: 'https://www.youtube.com/watch?v=${track.youtubeVideoId}',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Streams from YouTube when played (not stored on device).',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: pal.textMuted,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: pal.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
