import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android [permission_handler] allows only one in-flight platform request.
Future<void>? _permissionOpChain = Future.value();

bool _isConcurrentPermissionRequest(PlatformException e) =>
    e.code == 'PermissionHandler.PermissionManager' &&
    (e.message?.toLowerCase().contains('already running') ?? false);

/// Runs [op] after any prior permission work finishes (startup, resume, settings).
Future<T> runExclusivePermissionOperation<T>(Future<T> Function() op) async {
  final prior = _permissionOpChain!;
  final done = Completer<void>();
  _permissionOpChain = done.future;
  try {
    await prior.catchError((_) {});
    return await op();
  } finally {
    if (!done.isCompleted) done.complete();
  }
}

/// Single permission request with retry when another request was already active.
Future<PermissionStatus> requestPermissionSafely(Permission permission) {
  return runExclusivePermissionOperation(() async {
    try {
      return await permission.request();
    } on PlatformException catch (e) {
      if (!_isConcurrentPermissionRequest(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return permission.status;
    }
  });
}

/// Requests [permissions] in one platform call when possible.
Future<Map<Permission, PermissionStatus>> requestPermissionsSafely(
  List<Permission> permissions,
) {
  return runExclusivePermissionOperation(() async {
    try {
      return await permissions.request();
    } on PlatformException catch (e) {
      if (!_isConcurrentPermissionRequest(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final out = <Permission, PermissionStatus>{};
      for (final p in permissions) {
        out[p] = await p.status;
      }
      return out;
    }
  });
}
