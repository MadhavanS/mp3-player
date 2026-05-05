import 'dart:io';

Future<String?> deleteMusicFileOrError(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    await f.delete();
    return null;
  } on FileSystemException catch (e) {
    return e.message.isNotEmpty ? e.message : 'Could not delete file.';
  } catch (e) {
    return e.toString();
  }
}
