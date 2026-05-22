import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track_item.dart';
import 'saved_youtube_audio_store.dart';
import 'youtube_download_settings_store.dart';
import 'youtube_client.dart';
import 'youtube_manifest_resolver.dart';

/// Downloads YouTube audio to app storage via [ytClient].
class YoutubeAudioDownloadService {
  YoutubeAudioDownloadService._();

  static final YoutubeAudioDownloadService instance =
      YoutubeAudioDownloadService._();

  Future<Directory> downloadsDirectory() =>
      YoutubeDownloadSettingsStore.resolveDownloadsDirectory();

  /// Returns the saved [TrackItem] with [TrackItem.filePath], or null on failure.
  Future<TrackItem?> downloadAndSave(
    TrackItem source, {
    void Function(double? progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
    bool Function()? isPaused,
  }) async {
    if (kIsWeb) return null;

    final videoId = source.youtubeVideoId?.trim();
    if (videoId == null || videoId.isEmpty) return null;

    await SavedYoutubeAudioStore.ensureLoaded();
    final existingPath = SavedYoutubeAudioStore.filePathForVideoId(videoId);
    if (existingPath != null && await File(existingPath).exists()) {
      onProgress?.call(1.0);
      onStatus?.call('Already saved');
      for (final t in await SavedYoutubeAudioStore.load()) {
        if (t.youtubeVideoId == videoId) return t;
      }
    }

    try {
      if (isCancelled?.call() == true) throw _DownloadCancelled();
      onProgress?.call(null);
      onStatus?.call('Preparing download…');

      final manifest = await resolveYoutubeAudioManifest(
        videoId,
        isCancelled: isCancelled,
        onStatus: onStatus,
      );
      if (isCancelled?.call() == true) throw _DownloadCancelled();
      if (manifest == null) return null;

      final audioOnly = manifest.audioOnly;
      if (audioOnly.isEmpty) return null;

      final streamInfo = audioOnly.withHighestBitrate();
      final ext = _extensionForContainer(streamInfo.container);
      final dir = await downloadsDirectory();
      final outPath = p.join(dir.path, '$videoId.$ext');
      final outFile = File(outPath);

      if (await outFile.exists()) {
        await outFile.delete();
      }

      onStatus?.call('Saving… 0%');
      final byteStream = ytClient.videos.streamsClient.get(streamInfo);

      final total = streamInfo.size.totalBytes;
      IOSink? sink;
      var received = 0;
      try {
        sink = outFile.openWrite();
        await for (final chunk in byteStream) {
          if (isCancelled?.call() == true) {
            throw _DownloadCancelled();
          }
          while (isPaused?.call() == true) {
            if (isCancelled?.call() == true) {
              throw _DownloadCancelled();
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final p = (received / total).clamp(0.0, 0.99);
            onProgress?.call(p);
            onStatus?.call('Saving… ${(p * 100).round()}%');
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
      } on _DownloadCancelled {
        try {
          await sink?.close();
        } catch (_) {}
        if (await outFile.exists()) {
          try {
            await outFile.delete();
          } catch (_) {}
        }
        return null;
      } catch (e, st) {
        debugPrint('YouTube download stream error: $e\n$st');
        try {
          await sink?.close();
        } catch (_) {}
        if (await outFile.exists()) {
          try {
            await outFile.delete();
          } catch (_) {}
        }
        return null;
      }

      onProgress?.call(1.0);
      onStatus?.call('Saved to device');

      final saved = TrackItem(
        title: source.title,
        artist: source.artist,
        metaLine: source.metaLine,
        genres: '',
        artColors: source.artColors,
        filePath: outPath,
        youtubeVideoId: videoId,
        youtubeChannelId: source.youtubeChannelId,
        thumbnailUrl: source.thumbnailUrl,
      );
      await SavedYoutubeAudioStore.add(saved);
      return saved;
    } on _DownloadCancelled {
      return null;
    } catch (e, st) {
      if (isManifestResolveCancelled(e)) {
        return null;
      }
      debugPrint('YouTube download error: $e\n$st');
      return null;
    }
  }

  static String _extensionForContainer(StreamContainer container) {
    final name = container.name.toLowerCase();
    if (name.contains('webm')) return 'webm';
    if (name.contains('mp4') || name.contains('m4a')) return 'm4a';
    if (name.contains('opus')) return 'webm';
    return name.isNotEmpty ? name : 'webm';
  }
}

class _DownloadCancelled implements Exception {}
