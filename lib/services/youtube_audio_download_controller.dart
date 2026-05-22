import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;

import '../models/track_item.dart';
import '../models/youtube_download_job.dart';
import '../widgets/action_pill_toast.dart';
import 'youtube_audio_download_service.dart';

/// Queued YouTube audio downloads with per-job cancel and pause/resume.
class YoutubeAudioDownloadController extends ChangeNotifier {
  YoutubeAudioDownloadController._();

  static final YoutubeAudioDownloadController instance =
      YoutubeAudioDownloadController._();

  final List<YoutubeDownloadJob> _jobs = [];
  bool _pumping = false;

  /// Set for the whole [_runJob] call so cancel can drop UI while work unwinds.
  YoutubeDownloadJob? _inFlightJob;

  List<YoutubeDownloadJob> get jobs => List.unmodifiable(_jobs);

  int get activeCount =>
      _jobs.where((j) => j.isActive).length;

  /// Non-null while [_runJob] is in progress (even if UI already removed the job).
  YoutubeDownloadJob? get _downloadingJob => _inFlightJob;

  /// Legacy: any job actively downloading.
  bool get isRunning => _downloadingJob != null;

  String? get activeVideoId => _downloadingJob?.videoId;

  double? get progress => _downloadingJob?.progress;

  String get status => _downloadingJob?.status ?? '';

  bool isDownloading(String? videoId) {
    final id = videoId?.trim();
    if (id == null || id.isEmpty) return false;
    final j = _jobFor(id);
    return j != null &&
        (j.state == YoutubeDownloadJobState.downloading ||
            j.state == YoutubeDownloadJobState.paused);
  }

  bool isQueued(String? videoId) {
    final id = videoId?.trim();
    if (id == null || id.isEmpty) return false;
    final j = _jobFor(id);
    return j != null && j.state == YoutubeDownloadJobState.queued;
  }

  YoutubeDownloadJob? jobFor(String? videoId) => _jobFor(videoId?.trim() ?? '');

  YoutubeDownloadJob? _jobFor(String id) {
    if (id.isEmpty) return null;
    for (final j in _jobs) {
      if (j.videoId == id) return j;
    }
    return null;
  }

  /// Enqueues [track]. Returns false on web or if already queued/downloading.
  Future<bool> enqueue(TrackItem track) async {
    if (kIsWeb) return false;
    final id = track.youtubeVideoId?.trim();
    if (id == null || id.isEmpty) return false;

    final existing = _jobFor(id);
    if (existing != null && existing.isActive) return false;

    if (existing != null) {
      _jobs.remove(existing);
    }

    _jobs.insert(0, YoutubeDownloadJob(track: track, videoId: id));
    notifyListeners();
    unawaited(_pumpQueue());
    return true;
  }

  /// Starts saving [track] (alias for [enqueue]).
  Future<bool> start(TrackItem track) => enqueue(track);

  void cancel(String videoId) {
    final id = videoId.trim();
    final job = _jobFor(id);
    if (job == null || !job.isActive) return;
    job.cancelled = true;
    job.paused = false;
    job.state = YoutubeDownloadJobState.cancelled;
    job.status = 'Cancelled';
    notifyListeners();
    _scheduleRemove(job);
  }

  void pause(String videoId) {
    final job = _jobFor(videoId.trim());
    if (job == null ||
        job.state != YoutubeDownloadJobState.downloading) {
      return;
    }
    job.paused = true;
    job.state = YoutubeDownloadJobState.paused;
    job.status = 'Paused';
    notifyListeners();
  }

  void resume(String videoId) {
    final job = _jobFor(videoId.trim());
    if (job == null || job.state != YoutubeDownloadJobState.paused) return;
    job.paused = false;
    job.state = YoutubeDownloadJobState.downloading;
    job.status = 'Saving…';
    notifyListeners();
  }

  void clearFinished() {
    _jobs.removeWhere(
      (j) =>
          j.state == YoutubeDownloadJobState.completed ||
          j.state == YoutubeDownloadJobState.failed ||
          j.state == YoutubeDownloadJobState.cancelled,
    );
    notifyListeners();
  }

  void clearStatus() {
    if (isRunning) return;
    clearFinished();
  }

  Future<void> _pumpQueue() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        if (_downloadingJob != null) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        YoutubeDownloadJob? next;
        for (final j in _jobs.reversed) {
          if (j.state == YoutubeDownloadJobState.queued) {
            next = j;
            break;
          }
        }
        if (next == null) break;
        await _runJob(next);
      }
    } finally {
      _pumping = false;
      notifyListeners();
    }
  }

  Future<void> _runJob(YoutubeDownloadJob job) async {
    _inFlightJob = job;
    try {
      if (job.cancelled) {
        return;
      }

      job.state = YoutubeDownloadJobState.downloading;
      job.progress = null;
      job.status = 'Preparing download…';
      notifyListeners();

      final saved = await YoutubeAudioDownloadService.instance.downloadAndSave(
        job.track,
        onProgress: (p) {
          if (job.cancelled) return;
          job.progress = p;
          notifyListeners();
        },
        onStatus: (status) {
          if (job.cancelled) return;
          job.status = job.paused ? 'Paused' : status;
          notifyListeners();
        },
        isCancelled: () => job.cancelled,
        isPaused: () => job.paused,
      );

      if (job.cancelled) {
        return;
      }
      if (saved != null) {
        job.state = YoutubeDownloadJobState.completed;
        job.progress = 1.0;
        job.status = 'Saved to device';
      } else {
        job.state = YoutubeDownloadJobState.failed;
        job.status = 'Download failed';
        _notifyDownloadFailed(job);
      }
      notifyListeners();
      _scheduleRemove(job);
    } finally {
      if (identical(_inFlightJob, job)) {
        _inFlightJob = null;
      }
      unawaited(_pumpQueue());
    }
  }

  void _notifyDownloadFailed(YoutubeDownloadJob job) {
    ActionPillToast.showUsingRootNavigator(
      'Download failed — check your connection and try again',
      icon: Icons.cloud_off_outlined,
    );
  }

  void _scheduleRemove(YoutubeDownloadJob job) {
    if (job.state == YoutubeDownloadJobState.cancelled) {
      _jobs.remove(job);
      notifyListeners();
      unawaited(_pumpQueue());
      return;
    }
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), () {
        _jobs.remove(job);
        notifyListeners();
        unawaited(_pumpQueue());
      }),
    );
  }
}

/// Starts a device save; progress appears in the Downloads tab and Now Playing.
Future<bool> startYoutubeAudioSave(TrackItem track) =>
    YoutubeAudioDownloadController.instance.enqueue(track);
