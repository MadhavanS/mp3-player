import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'youtube_download_job.dart';

/// Android/iOS download progress and completion notifications.
abstract final class YoutubeDownloadNotifications {
  YoutubeDownloadNotifications._();

  static const _channelId = 'youtube_downloads_v1';
  static const _notificationId = 9042;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static var _initialized = false;

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'YouTube downloads',
              description: 'Progress while YouTube audio is saved offline',
              importance: Importance.low,
            ),
          );
    }

    _initialized = true;
  }

  static Future<void> showActive(YoutubeDownloadJob job) async {
    if (!_initialized) return;

    final indeterminate =
        job.state == YoutubeDownloadState.fetchingManifest ||
        job.state == YoutubeDownloadState.processing ||
        job.state == YoutubeDownloadState.queued;
    final downloading = job.state == YoutubeDownloadState.downloading;
    final hasTotal = downloading && job.totalBytes > 0;

    await _plugin.show(
      _notificationId,
      'Downloading from YouTube',
      job.title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'YouTube downloads',
          channelDescription:
              'Progress while YouTube audio is saved offline',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: downloading || indeterminate,
          showProgress: downloading || indeterminate,
          maxProgress: hasTotal ? 100 : 0,
          progress: hasTotal ? (job.progress * 100).round() : 0,
          indeterminate: indeterminate || (downloading && !hasTotal),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  static Future<void> showComplete(String title) async {
    if (!_initialized) return;
    await dismiss();
    await _plugin.show(
      _notificationId,
      'Download complete',
      title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'YouTube downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showFailed(String title, String? error) async {
    if (!_initialized) return;
    await dismiss();
    await _plugin.show(
      _notificationId,
      'Download failed',
      error == null || error.isEmpty ? title : '$title — $error',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'YouTube downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> dismiss() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
  }
}
