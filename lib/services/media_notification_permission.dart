import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Android 13+ requires runtime consent before media-style notifications show.
Future<void> ensureMediaNotificationPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final status = await Permission.notification.status;
  if (status.isGranted || status.isLimited) return;
  await Permission.notification.request();
}
