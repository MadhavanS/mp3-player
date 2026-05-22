import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_api_clients.dart';
import 'youtube_client.dart';

/// Per client-set attempt (playback + download).
const Duration kYoutubeManifestPerSetTimeout = Duration(seconds: 18);

/// Tries [youtubeManifestClients] plus fallbacks until audio streams are found.
Future<StreamManifest?> resolveYoutubeAudioManifest(
  String videoId, {
  Duration perSetTimeout = kYoutubeManifestPerSetTimeout,
  bool Function()? isCancelled,
  void Function(String message)? onStatus,
}) async {
  final id = videoId.trim();
  if (id.isEmpty) return null;

  final clientSets = <List<YoutubeApiClient>>[
    youtubeManifestClients,
    ...youtubeManifestClientFallbacks,
  ];

  Object? lastError;
  for (var i = 0; i < clientSets.length; i++) {
    if (isCancelled?.call() == true) return null;
    onStatus?.call('Connecting (${i + 1}/${clientSets.length})…');

    try {
      final manifest = await _awaitWithCancellation(
        ytClient.videos.streams
            .getManifest(id, ytClients: clientSets[i])
            .timeout(perSetTimeout),
        isCancelled,
      );
      if (manifest.audioOnly.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            'YouTube manifest ok for $id (client set ${i + 1}/'
            '${clientSets.length})',
          );
        }
        return manifest;
      }
    } on TimeoutException catch (e) {
      lastError = e;
      if (kDebugMode) {
        debugPrint(
          'YouTube manifest slow for $id (client set ${i + 1}/'
          '${clientSets.length})',
        );
      }
    } catch (e, st) {
      lastError = e;
      if (kDebugMode) {
        debugPrint(
          'YouTube manifest error for $id (set ${i + 1}): $e\n$st',
        );
      }
    }
  }

  if (kDebugMode && lastError != null) {
    debugPrint(
      'YouTube manifest failed for $id after ${clientSets.length} client sets: '
      '$lastError',
    );
  }
  return null;
}

Future<T> _awaitWithCancellation<T>(
  Future<T> operation,
  bool Function()? isCancelled,
) async {
  if (isCancelled?.call() == true) {
    throw _ManifestResolveCancelled();
  }
  return Future.any([
    operation,
    _pollUntilCancelled<T>(isCancelled),
  ]);
}

Future<T> _pollUntilCancelled<T>(bool Function()? isCancelled) async {
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (isCancelled?.call() == true) {
      throw _ManifestResolveCancelled();
    }
  }
}

/// Used by [YoutubeAudioDownloadService] — same as download cancel.
class _ManifestResolveCancelled implements Exception {}

bool isManifestResolveCancelled(Object? error) =>
    error is _ManifestResolveCancelled;
