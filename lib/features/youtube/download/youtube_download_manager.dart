import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../catalog/youtube_library_catalog.dart';
import '../models/youtube_track.dart';
import '../storage/youtube_track_record.dart';
import '../storage/youtube_track_store.dart';
import '../thumbnail/youtube_thumbnail_cache.dart';
import 'youtube_download_job.dart';
import 'youtube_download_notifications.dart';
import 'youtube_download_queue_store.dart';
import 'youtube_manifest_resolver.dart';
import 'youtube_stream_format.dart';

/// Serial download queue: search → local file → library (no streaming playback).
class YoutubeDownloadManager extends ChangeNotifier {
  YoutubeDownloadManager._();

  static final instance = YoutubeDownloadManager._();

  final _jobs = <String, YoutubeDownloadJob>{};
  final _queue = Queue<String>();
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isProcessing = false;

  /// Set when a job finishes successfully (for shell snackbars / catalog merge).
  final ValueNotifier<YoutubeDownloadJob?> lastCompletedJob =
      ValueNotifier(null);

  Map<String, YoutubeDownloadJob> get jobs => Map.unmodifiable(_jobs);

  YoutubeDownloadJob? jobForVideoId(String videoId) => _jobs[videoId];

  List<YoutubeDownloadJob> get activeJobs => _jobs.values
      .where(
        (j) =>
            j.state != YoutubeDownloadState.complete &&
            j.state != YoutubeDownloadState.cancelled &&
            j.state != YoutubeDownloadState.failed,
      )
      .toList(growable: false);

  /// Re-enqueues downloads persisted before the last process exit.
  Future<void> resumePendingDownloads() async {
    final pending = await YoutubeDownloadQueueStore.loadPending();
    for (final track in pending) {
      try {
        await enqueue(track, persistQueue: false);
      } catch (_) {
        // Already on disk or actively queued — drop stale queue row later.
      }
    }
  }

  Future<YoutubeDownloadJob> enqueue(
    YoutubeTrack track, {
    bool persistQueue = true,
  }) async {
    final existing = await YoutubeTrackStore.instance.get(track.videoId);
    if (existing?.localPath != null) {
      final file = File(existing!.localPath!);
      if (await file.exists()) {
        await YoutubeDownloadQueueStore.remove(track.videoId);
        throw StateError('Already downloaded: ${track.videoId}');
      }
    }

    final prior = _jobs[track.videoId];
    if (prior != null &&
        prior.state != YoutubeDownloadState.failed &&
        prior.state != YoutubeDownloadState.cancelled) {
      return prior;
    }

    final job = YoutubeDownloadJob(
      videoId: track.videoId,
      title: track.title,
      artist: track.artist,
      thumbnailUrl: track.thumbnailUrl,
      durationMs: track.duration?.inMilliseconds,
    );

    _jobs[track.videoId] = job;
    _queue.add(track.videoId);
    if (persistQueue) {
      await YoutubeDownloadQueueStore.upsert(track);
    }
    notifyListeners();
    unawaited(_processQueue());
    return job;
  }

  Future<void> retry(String videoId) async {
    final record = await YoutubeTrackStore.instance.get(videoId);
    if (record == null) return;
    await enqueue(
      YoutubeTrack(
        videoId: record.videoId,
        title: record.title,
        artist: record.artist,
        thumbnailUrl: record.thumbnailUrl,
        duration: record.durationMs != null && record.durationMs! > 0
            ? Duration(milliseconds: record.durationMs!)
            : null,
      ),
    );
  }

  void cancel(String videoId) {
    final job = _jobs[videoId];
    if (job == null) return;
    if (job.state == YoutubeDownloadState.complete) return;

    job.applyUpdate(state: YoutubeDownloadState.cancelled);
    _queue.removeWhere((id) => id == videoId);
    _jobs.remove(videoId);
    unawaited(YoutubeDownloadQueueStore.remove(videoId));
    unawaited(YoutubeDownloadNotifications.dismiss());
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (_queue.isEmpty) return;

    _isProcessing = true;
    await WakelockPlus.enable();
    try {
      while (_queue.isNotEmpty) {
        final videoId = _queue.removeFirst();
        final job = _jobs[videoId];
        if (job == null || job.state == YoutubeDownloadState.cancelled) {
          continue;
        }
        await _processJob(job);
      }
    } finally {
      _isProcessing = false;
      if (_queue.isEmpty && activeJobs.isEmpty) {
        await WakelockPlus.disable();
        await YoutubeDownloadNotifications.dismiss();
      }
    }
  }

  Future<void> _processJob(YoutubeDownloadJob job) async {
    try {
      job.applyUpdate(state: YoutubeDownloadState.fetchingManifest);
      await YoutubeDownloadNotifications.showActive(job);

      final enriched = await _fetchVideoMetadata(job);
      job.applyUpdate(
        title: enriched.title,
        artist: enriched.artist,
        thumbnailUrl: enriched.thumbnailUrl,
        durationMs: enriched.duration?.inMilliseconds ?? job.durationMs,
      );

      final streamInfo =
          await YoutubeManifestResolver.instance.resolveAudio(job.videoId);
      if (streamInfo == null) {
        job.applyUpdate(
          state: YoutubeDownloadState.failed,
          error: 'Could not fetch stream info',
        );
        await YoutubeDownloadNotifications.showFailed(job.title, job.error);
        notifyListeners();
        return;
      }

      job.applyUpdate(
        state: YoutubeDownloadState.downloading,
        containerLabel: containerLabelForStream(streamInfo.container),
      );
      await YoutubeDownloadNotifications.showActive(job);

      final tempFile = await _downloadToTemp(job, streamInfo);
      if (tempFile == null) return;

      job.applyUpdate(state: YoutubeDownloadState.processing);
      await YoutubeDownloadNotifications.showActive(job);

      final finalPath = await _finalizeDownload(job, tempFile, streamInfo);
      final fileLen = await File(finalPath).length();

      final thumbPath = await YoutubeThumbnailCache.instance.primeForLocalFile(
        videoId: job.videoId,
        localPath: finalPath,
        thumbnailUrl: job.thumbnailUrl,
      );
      final artCachePath =
          thumbPath ??
          await YoutubeThumbnailCache.instance.cachePathForVideoId(job.videoId);
      final thumbBytes = artCachePath != null
          ? await File(artCachePath).readAsBytes()
          : await YoutubeThumbnailCache.instance.getThumbnailBytes(
              job.videoId,
              job.thumbnailUrl,
            );

      await _writeTags(
        finalPath,
        job,
        durationMs: job.durationMs,
        pictureBytes: thumbBytes,
      );

      final record = YoutubeTrackRecord()
        ..videoId = job.videoId
        ..title = job.title
        ..artist = job.artist
        ..thumbnailUrl = job.thumbnailUrl
        ..localPath = finalPath
        ..downloadedAtMs = DateTime.now().millisecondsSinceEpoch
        ..fileSizeBytes = fileLen
        ..durationMs = job.durationMs
        ..albumArtCachePath = artCachePath;

      await YoutubeTrackStore.instance.save(record);
      await YoutubeDownloadQueueStore.remove(job.videoId);

      job.applyUpdate(
        state: YoutubeDownloadState.complete,
        localPath: finalPath,
      );
      lastCompletedJob.value = job;
      await YoutubeDownloadNotifications.showComplete(job.title);
      notifyListeners();

      unawaited(YoutubeLibraryCatalog.instance.reload());
    } catch (e) {
      debugPrint('[YoutubeDownloadManager] failed ${job.videoId}: $e');
      job.applyUpdate(
        state: YoutubeDownloadState.failed,
        error: e.toString(),
      );
      await YoutubeDownloadNotifications.showFailed(job.title, job.error);
      notifyListeners();
    }
  }

  Future<YoutubeTrack> _fetchVideoMetadata(YoutubeDownloadJob job) async {
    try {
      final video = await _yt.videos.get(job.videoId);
      return YoutubeTrack(
        videoId: job.videoId,
        title: video.title.trim().isNotEmpty ? video.title : job.title,
        artist: video.author.trim().isNotEmpty ? video.author : job.artist,
        thumbnailUrl: video.thumbnails.mediumResUrl.trim().isNotEmpty
            ? video.thumbnails.mediumResUrl
            : job.thumbnailUrl,
        duration: video.duration ?? job.duration,
      );
    } catch (_) {
      return YoutubeTrack(
        videoId: job.videoId,
        title: job.title,
        artist: job.artist,
        thumbnailUrl: job.thumbnailUrl,
        duration: job.duration,
      );
    }
  }

  Future<File?> _downloadToTemp(
    YoutubeDownloadJob job,
    AudioOnlyStreamInfo streamInfo,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'yt_dl_${job.videoId}.part'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final sink = tempFile.openWrite();
    var downloaded = 0;
    final total = streamInfo.size.totalBytes;
    job.applyUpdate(downloaded: 0, total: total);

    try {
      final stream = _yt.videos.streamsClient.get(streamInfo);
      await for (final chunk in stream) {
        if (job.state == YoutubeDownloadState.cancelled) {
          await sink.close();
          if (await tempFile.exists()) await tempFile.delete();
          return null;
        }

        sink.add(chunk);
        downloaded += chunk.length;

        if (downloaded % (512 * 1024) < chunk.length || downloaded >= total) {
          job.applyUpdate(downloaded: downloaded, total: total);
          await YoutubeDownloadNotifications.showActive(job);
        }
      }

      await sink.flush();
      await sink.close();
      return tempFile;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await tempFile.exists()) await tempFile.delete();
      job.applyUpdate(
        state: YoutubeDownloadState.failed,
        error: e.toString(),
      );
      await YoutubeDownloadNotifications.showFailed(job.title, job.error);
      notifyListeners();
      return null;
    }
  }

  Future<String> _finalizeDownload(
    YoutubeDownloadJob job,
    File tempFile,
    AudioOnlyStreamInfo streamInfo,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ytDir = Directory(p.join(docsDir.path, 'youtube_audio'));
    if (!await ytDir.exists()) {
      await ytDir.create(recursive: true);
    }

    final ext = fileExtensionForStream(streamInfo.container);
    final safeName = job.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    final clipped = safeName.isEmpty
        ? job.videoId
        : safeName.substring(0, math.min(safeName.length, 50));
    final finalPath = p.join(ytDir.path, '${job.videoId}_$clipped.$ext');

    if (await File(finalPath).exists()) {
      await File(finalPath).delete();
    }
    await tempFile.rename(finalPath);
    return finalPath;
  }

  Future<void> _writeTags(
    String path,
    YoutubeDownloadJob job, {
    required int? durationMs,
    Uint8List? pictureBytes,
  }) async {
    try {
      Picture? picture;
      if (pictureBytes != null && pictureBytes.isNotEmpty) {
        picture = Picture(mimeType: 'image/jpeg', data: pictureBytes);
      }
      await MetadataGod.writeMetadata(
        file: path,
        metadata: Metadata(
          title: job.title,
          artist: job.artist,
          album: 'YouTube',
          albumArtist: job.artist,
          durationMs: durationMs != null && durationMs > 0
              ? durationMs.toDouble()
              : null,
          picture: picture,
        ),
      );
    } catch (e) {
      debugPrint('[YoutubeDownloadManager] tag write failed (non-fatal): $e');
    }
  }

  void disposeClient() => _yt.close();
}
