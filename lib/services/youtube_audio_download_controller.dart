import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track_item.dart';
import 'youtube_audio_download_service.dart';

/// In-app YouTube audio download progress (shown on Now Playing, not a modal).
class YoutubeAudioDownloadController extends ChangeNotifier {
  YoutubeAudioDownloadController._();

  static final YoutubeAudioDownloadController instance =
      YoutubeAudioDownloadController._();

  String? _videoId;
  double? _progress;
  bool _running = false;
  String _status = '';

  String? get activeVideoId => _videoId;
  double? get progress => _progress;
  bool get isRunning => _running;
  String get status => _status;

  bool isDownloading(String? videoId) {
    final id = videoId?.trim();
    if (id == null || id.isEmpty) return false;
    return _running && _videoId == id;
  }

  /// Starts saving [track] to device storage. Returns false if another save is active.
  Future<bool> start(TrackItem track) async {
    if (kIsWeb) return false;
    final id = track.youtubeVideoId?.trim();
    if (id == null || id.isEmpty) return false;
    if (_running) return false;

    _videoId = id;
    _running = true;
    _progress = null;
    _status = 'Preparing download…';
    notifyListeners();

    final saved = await YoutubeAudioDownloadService.instance.downloadAndSave(
      track,
      onProgress: (p) {
        _progress = p;
        _status = p == null
            ? 'Preparing download…'
            : 'Saving… ${(p * 100).round()}%';
        notifyListeners();
      },
    );

    _running = false;
    _progress = saved != null ? 1.0 : _progress;
    _status = saved != null ? 'Saved to device' : 'Download failed';
    notifyListeners();

    await Future<void>.delayed(const Duration(seconds: 2));
    if (_videoId == id && !_running) {
      _videoId = null;
      _progress = null;
      _status = '';
      notifyListeners();
    }
    return saved != null;
  }

  void clearStatus() {
    if (_running) return;
    _videoId = null;
    _progress = null;
    _status = '';
    notifyListeners();
  }
}

/// Starts a device save without blocking dialogs.
Future<bool> startYoutubeAudioSave(TrackItem track) =>
    YoutubeAudioDownloadController.instance.start(track);
