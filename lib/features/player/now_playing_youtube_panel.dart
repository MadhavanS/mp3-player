import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../youtube/download/youtube_download_job.dart';
import '../youtube/download/youtube_download_manager.dart';
import '../youtube/models/youtube_track.dart';
import '../youtube/storage/youtube_track_store.dart';
import '../youtube/youtube_now_playing.dart';

/// Download progress for the current YouTube track on Now Playing.
class YoutubeNowPlayingDownloadRow extends StatefulWidget {
  const YoutubeNowPlayingDownloadRow({
    super.key,
    required this.track,
    this.maxWidth,
  });

  final TrackItem track;
  final double? maxWidth;

  @override
  State<YoutubeNowPlayingDownloadRow> createState() =>
      _YoutubeNowPlayingDownloadRowState();
}

class _YoutubeNowPlayingDownloadRowState
    extends State<YoutubeNowPlayingDownloadRow> {
  String? _videoId;

  @override
  void initState() {
    super.initState();
    YoutubeDownloadManager.instance.addListener(_onDownloads);
    unawaited(_resolveVideoId());
  }

  @override
  void didUpdateWidget(covariant YoutubeNowPlayingDownloadRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.filePath != widget.track.filePath) {
      unawaited(_resolveVideoId());
    }
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.removeListener(_onDownloads);
    super.dispose();
  }

  void _onDownloads() {
    if (mounted) setState(() {});
  }

  Future<void> _resolveVideoId() async {
    final id = await youtubeVideoIdForTrackItem(widget.track);
    if (!mounted) return;
    setState(() => _videoId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _videoId == null) return const SizedBox.shrink();

    final job = YoutubeDownloadManager.instance.jobForVideoId(_videoId!);
    if (job == null) return const SizedBox.shrink();

    final active = job.state != YoutubeDownloadState.complete &&
        job.state != YoutubeDownloadState.failed &&
        job.state != YoutubeDownloadState.cancelled;
    if (!active) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final pal = context.palette;
    final percent = job.state == YoutubeDownloadState.downloading
        ? (job.progress * 100).round()
        : null;

    final label = switch (job.state) {
      YoutubeDownloadState.queued => 'Download queued',
      YoutubeDownloadState.fetchingManifest => 'Preparing download…',
      YoutubeDownloadState.downloading =>
        percent != null ? 'Downloading · $percent%' : 'Downloading…',
      YoutubeDownloadState.processing => 'Finalizing download…',
      _ => job.progressLabel,
    };

    final width = widget.maxWidth ?? double.infinity;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (job.state == YoutubeDownloadState.downloading)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: job.progress > 0 ? job.progress : null,
                  minHeight: 4,
                  backgroundColor: pal.onScaffold.withValues(alpha: 0.12),
                  color: context.controlAccent,
                ),
              )
            else
              const SizedBox(
                height: 4,
                child: LinearProgressIndicator(minHeight: 4),
              ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: download / progress for a YouTube Now Playing track.
Future<void> showYoutubeNowPlayingTrackSheet(
  BuildContext context, {
  required TrackItem track,
}) async {
  if (kIsWeb) return;
  final yt = await youtubeTrackForPlayerItem(track);
  if (!context.mounted || yt == null) return;

  final downloadedIds = await YoutubeTrackStore.instance.downloadedVideoIds();
  if (!context.mounted) return;
  final alreadyDownloaded = downloadedIds.contains(yt.videoId);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    builder: (ctx) => _YoutubeNowPlayingSheetBody(
      track: track,
      youtube: yt,
      alreadyDownloaded: alreadyDownloaded,
    ),
  );
}

class _YoutubeNowPlayingSheetBody extends StatefulWidget {
  const _YoutubeNowPlayingSheetBody({
    required this.track,
    required this.youtube,
    required this.alreadyDownloaded,
  });

  final TrackItem track;
  final YoutubeTrack youtube;
  final bool alreadyDownloaded;

  @override
  State<_YoutubeNowPlayingSheetBody> createState() =>
      _YoutubeNowPlayingSheetBodyState();
}

class _YoutubeNowPlayingSheetBodyState extends State<_YoutubeNowPlayingSheetBody> {
  late bool _downloaded = widget.alreadyDownloaded;

  @override
  void initState() {
    super.initState();
    YoutubeDownloadManager.instance.addListener(_onDownloads);
  }

  @override
  void dispose() {
    YoutubeDownloadManager.instance.removeListener(_onDownloads);
    super.dispose();
  }

  void _onDownloads() {
    if (!mounted) return;
    final job =
        YoutubeDownloadManager.instance.jobForVideoId(widget.youtube.videoId);
    if (job?.state == YoutubeDownloadState.complete) {
      setState(() => _downloaded = true);
    } else {
      setState(() {});
    }
  }

  Future<void> _startDownload() async {
    try {
      await YoutubeDownloadManager.instance.enqueue(widget.youtube);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading "${widget.youtube.title}"')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _downloaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final job = YoutubeDownloadManager.instance.jobForVideoId(widget.youtube.videoId);
    final downloading = job != null &&
        job.state != YoutubeDownloadState.complete &&
        job.state != YoutubeDownloadState.failed &&
        job.state != YoutubeDownloadState.cancelled;

    final percent = job != null && job.state == YoutubeDownloadState.downloading
        ? (job.progress * 100).round()
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.youtube.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              widget.youtube.artist,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: pal.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            if (downloading) ...[
              if (job.state == YoutubeDownloadState.downloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: job.progress > 0 ? job.progress : null,
                    minHeight: 6,
                  ),
                )
              else
                const LinearProgressIndicator(minHeight: 6),
              const SizedBox(height: 10),
              Text(
                percent != null
                    ? 'Downloading · $percent%'
                    : job.progressLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (_downloaded)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Downloaded to library',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download song'),
              ),
            if (!_downloaded && !downloading && job?.state == YoutubeDownloadState.failed) ...[
              const SizedBox(height: 12),
              Text(
                job!.error ?? 'Download failed',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  YoutubeDownloadManager.instance.retry(widget.youtube.videoId);
                },
                child: const Text('Retry download'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
