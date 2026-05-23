/// Android [permission_handler] allows only one in-flight permission dialog.
/// Queue all [Permission.request] calls (audio, storage, notification, etc.).
Future<void> _permissionRequestTail = Future.value();

Future<T> runWithExclusivePermissionRequest<T>(
  Future<T> Function() action,
) {
  final result = _permissionRequestTail.then((_) => action());
  _permissionRequestTail = result.then((_) {}, onError: (_) {});
  return result;
}
