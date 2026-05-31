import 'package:flutter/material.dart';

import '../download/youtube_download_job.dart';
import '../download/youtube_download_manager.dart';

class YoutubeDownloadSheetTile extends StatelessWidget {
  const YoutubeDownloadSheetTile({super.key, required this.job});

  final YoutubeDownloadJob job;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            title: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.progressLabel),
                const SizedBox(height: 4),
                if (job.state == YoutubeDownloadState.downloading)
                  LinearProgressIndicator(value: job.progress, minHeight: 3)
                else if (job.state == YoutubeDownloadState.fetchingManifest ||
                    job.state == YoutubeDownloadState.processing)
                  const LinearProgressIndicator(minHeight: 3),
              ],
            ),
            trailing: _trailingAction(context),
          ),
        );
      },
    );
  }

  Widget _trailingAction(BuildContext context) {
    switch (job.state) {
      case YoutubeDownloadState.complete:
        return Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
        );
      case YoutubeDownloadState.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () =>
              YoutubeDownloadManager.instance.retry(job.videoId),
        );
      case YoutubeDownloadState.cancelled:
        return const SizedBox.shrink();
      default:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: () =>
              YoutubeDownloadManager.instance.cancel(job.videoId),
        );
    }
  }
}

class YoutubeActiveDownloadsBar extends StatelessWidget {
  const YoutubeActiveDownloadsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: YoutubeDownloadManager.instance,
      builder: (context, _) {
        final jobs = YoutubeDownloadManager.instance.activeJobs;
        if (jobs.isEmpty) return const SizedBox.shrink();

        return Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final job in jobs) YoutubeDownloadSheetTile(job: job),
              ],
            ),
          ),
        );
      },
    );
  }
}
