import 'favorite_songs_store.dart';
import 'music_library_path_key.dart';
import 'recently_added_store.dart';
import 'recently_played_store.dart';
import 'user_playlists_store.dart';

/// Updates persisted path lists after a file rename so UI/history do not keep
/// stale absolute paths (duplicate RecentlyPlayed rows, dead play targets).
Future<void> migrateLibraryPathReferences(
  String oldPath,
  String newPath,
) async {
  final oldKey = canonicalMusicLibraryPathKey(oldPath);
  final newKey = canonicalMusicLibraryPathKey(newPath);
  if (oldKey.isEmpty || newKey.isEmpty || oldKey == newKey) return;

  await Future.wait<void>([
    RecentlyPlayedStore.replacePath(oldPath, newPath),
    FavoriteSongsStore.replacePath(oldPath, newPath),
    RecentlyAddedStore.replacePathKey(oldPath, newPath),
    UserPlaylistsStore.replacePathInAllPlaylists(oldPath, newPath),
  ]);
}
