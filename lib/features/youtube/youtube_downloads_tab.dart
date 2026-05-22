import 'package:flutter/material.dart';

import '../../models/youtube_download_job.dart';
import '../../services/youtube_audio_download_controller.dart';
import '../../theme/app_theme.dart';
import 'youtube_search_thumbnail.dart';

/// Lists queued/active YouTube audio downloads with cancel and pause/resume.
class YoutubeDownloadsTab extends StatelessWidget {
  const YoutubeDownloadsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final dl = YoutubeAudioDownloadController.instance;

    return ListenableBuilder(
      listenable: dl,
      builder: (context, _) {
        final jobs = dl.jobs;
        if (jobs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No downloads yet.\nUse Save audio on a track to queue a download.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          itemCount: jobs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _DownloadJobTile(job: job);
          },
        );
      },
    );
  }
}

class _DownloadJobTile extends StatelessWidget {
  const _DownloadJobTile({required this.job});

  final YoutubeDownloadJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final dl = YoutubeAudioDownloadController.instance;
    final progress = job.progress?.clamp(0.0, 1.0);

    IconData stateIcon;
    Color? stateColor;
    switch (job.state) {
      case YoutubeDownloadJobState.queued:
        stateIcon = Icons.schedule_rounded;
        stateColor = pal.textMuted;
      case YoutubeDownloadJobState.downloading:
        stateIcon = Icons.downloading_rounded;
        stateColor = context.controlAccent;
      case YoutubeDownloadJobState.paused:
        stateIcon = Icons.pause_circle_outline_rounded;
        stateColor = pal.textMuted;
      case YoutubeDownloadJobState.completed:
        stateIcon = Icons.check_circle_outline_rounded;
        stateColor = Colors.green.shade700;
      case YoutubeDownloadJobState.failed:
        stateIcon = Icons.error_outline_rounded;
        stateColor = Colors.red.shade700;
      case YoutubeDownloadJobState.cancelled:
        stateIcon = Icons.cancel_outlined;
        stateColor = pal.textMuted;
    }

    return Material(
      color: pal.onScaffold.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: YoutubeSearchThumbnail(
                    url: job.track.thumbnailUrl,
                    size: 48,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.track.title.trim().isNotEmpty
                            ? job.track.title
                            : 'Untitled video',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(stateIcon, size: 16, color: stateColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              job.status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: pal.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (job.isActive) ...[
                  if (job.state == YoutubeDownloadJobState.downloading)
                    IconButton(
                      tooltip: 'Pause',
                      icon: const Icon(Icons.pause_rounded),
                      onPressed: () => dl.pause(job.videoId),
                    ),
                  if (job.state == YoutubeDownloadJobState.paused)
                    IconButton(
                      tooltip: 'Resume',
                      icon: Icon(
                        Icons.play_arrow_rounded,
                        color: context.controlAccent,
                      ),
                      onPressed: () => dl.resume(job.videoId),
                    ),
                  IconButton(
                    tooltip: 'Cancel download',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => dl.cancel(job.videoId),
                  ),
                ],
              ],
            ),
            if (job.state == YoutubeDownloadJobState.downloading ||
                job.state == YoutubeDownloadJobState.paused) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
