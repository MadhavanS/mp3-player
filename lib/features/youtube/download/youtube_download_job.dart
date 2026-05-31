import 'package:flutter/foundation.dart';

enum YoutubeDownloadState {
  queued,
  fetchingManifest,
  downloading,
  processing,
  complete,
  failed,
  cancelled,
}

class YoutubeDownloadJob extends ChangeNotifier {
  YoutubeDownloadJob({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.durationMs,
  });

  final String videoId;
  String title;
  String artist;
  String? thumbnailUrl;
  int? durationMs;
  String? containerLabel;

  YoutubeDownloadState _state = YoutubeDownloadState.queued;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _error;
  String? _localPath;

  YoutubeDownloadState get state => _state;
  double get progress => _totalBytes > 0
      ? (_downloadedBytes / _totalBytes).clamp(0.0, 1.0)
      : 0.0;
  String? get localPath => _localPath;
  String? get error => _error;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;

  Duration? get duration =>
      durationMs != null && durationMs! > 0
          ? Duration(milliseconds: durationMs!)
          : null;

  String get progressLabel {
    switch (_state) {
      case YoutubeDownloadState.queued:
        return 'Queued';
      case YoutubeDownloadState.fetchingManifest:
        return 'Preparing…';
      case YoutubeDownloadState.downloading:
        final dl = (_downloadedBytes / 1048576).toStringAsFixed(1);
        final tot = (_totalBytes / 1048576).toStringAsFixed(1);
        final format =
            containerLabel == null ? '' : ' · $containerLabel';
        return '$dl / $tot MB$format';
      case YoutubeDownloadState.processing:
        return containerLabel == null
            ? 'Finalizing…'
            : 'Finalizing $containerLabel…';
      case YoutubeDownloadState.complete:
        return 'Complete';
      case YoutubeDownloadState.failed:
        return 'Failed: ${_error ?? 'unknown'}';
      case YoutubeDownloadState.cancelled:
        return 'Cancelled';
    }
  }

  void applyUpdate({
    YoutubeDownloadState? state,
    int? downloaded,
    int? total,
    String? error,
    String? localPath,
    String? title,
    String? artist,
    String? thumbnailUrl,
    int? durationMs,
    String? containerLabel,
  }) {
    var changed = false;
    if (state != null && state != _state) {
      _state = state;
      changed = true;
    }
    if (downloaded != null && downloaded != _downloadedBytes) {
      _downloadedBytes = downloaded;
      changed = true;
    }
    if (total != null && total != _totalBytes) {
      _totalBytes = total;
      changed = true;
    }
    if (error != null && error != _error) {
      _error = error;
      changed = true;
    }
    if (localPath != null && localPath != _localPath) {
      _localPath = localPath;
      changed = true;
    }
    if (title != null && title != this.title) {
      this.title = title;
      changed = true;
    }
    if (artist != null && artist != this.artist) {
      this.artist = artist;
      changed = true;
    }
    if (thumbnailUrl != null && thumbnailUrl != this.thumbnailUrl) {
      this.thumbnailUrl = thumbnailUrl;
      changed = true;
    }
    if (durationMs != null && durationMs != this.durationMs) {
      this.durationMs = durationMs;
      changed = true;
    }
    if (containerLabel != null && containerLabel != this.containerLabel) {
      this.containerLabel = containerLabel;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
