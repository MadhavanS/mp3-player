import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../services/album_art_cache.dart';

/// Caches YouTube thumbnails and primes the existing album-art disk pipeline.
class YoutubeThumbnailCache {
  YoutubeThumbnailCache._();

  static final instance = YoutubeThumbnailCache._();

  Future<Uint8List?> getThumbnailBytes(
    String videoId,
    String? thumbnailUrl,
  ) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;

    final cacheFile = await _thumbnailFile(id);
    if (await cacheFile.exists()) {
      return cacheFile.readAsBytes();
    }

    if (thumbnailUrl == null || thumbnailUrl.trim().isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(thumbnailUrl));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(response.bodyBytes, flush: false);
      return response.bodyBytes;
    } catch (e, st) {
      debugPrint('[YoutubeThumbnailCache] download failed: $e\n$st');
      return null;
    }
  }

  /// After download, prime album-art cache for the local audio file path.
  /// Returns the on-disk thumbnail cache path when available.
  Future<String?> primeForLocalFile({
    required String videoId,
    required String localPath,
    String? thumbnailUrl,
  }) async {
    final bytes = await getThumbnailBytes(videoId, thumbnailUrl);
    if (bytes == null || bytes.isEmpty) return null;
    await primeAlbumArtDiskCache(localPath, bytes);
    final cacheFile = await _thumbnailFile(videoId.trim());
    return cacheFile.path;
  }

  Future<String?> cachePathForVideoId(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    final cacheFile = await _thumbnailFile(id);
    if (!await cacheFile.exists()) return null;
    return cacheFile.path;
  }

  Future<File> _thumbnailFile(String videoId) async {
    final dir = await getApplicationCacheDirectory();
    return File(p.join(dir.path, 'yt_thumbs', '$videoId.jpg'));
  }

  Future<void> clearAll() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final thumbs = Directory(p.join(dir.path, 'yt_thumbs'));
      if (await thumbs.exists()) {
        await thumbs.delete(recursive: true);
      }
    } catch (e, st) {
      debugPrint('[YoutubeThumbnailCache.clearAll] $e\n$st');
    }
  }
}
