import 'package:isar/isar.dart';

part 'song_metadata_cache_row.g.dart';

@collection
class SongMetadataCacheRow {
  SongMetadataCacheRow();

  int id = 0;

  @Index(unique: true)
  late String path;

  String title = '';
  String artist = '';
  String album = '';
  String genres = '';
  List<int> artColorValues = const <int>[];
  List<int>? albumArtBytes;
  int updatedAtMs = 0;
}
