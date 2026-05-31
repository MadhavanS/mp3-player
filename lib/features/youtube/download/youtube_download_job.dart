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
  });

  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;

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

  String get progressLabel {
    switch (_state) {
      case YoutubeDownloadState.queued:
        return 'Queued';
      case YoutubeDownloadState.fetchingManifest:
        return 'Preparing…';
      case YoutubeDownloadState.downloading:
        final dl = (_downloadedBytes / 1048576).toStringAsFixed(1);
        final tot = (_totalBytes / 1048576).toStringAsFixed(1);
        return '$dl / $tot MB';
      case YoutubeDownloadState.processing:
        return 'Finalizing…';
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
    if (changed) notifyListeners();
  }
}
