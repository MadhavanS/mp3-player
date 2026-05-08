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

  /// Embedded cover art is not cached here — storing it as List<int> mapped Isar to
  /// longList (one long per byte) and crashed on large images; art loads during enrichment.
  int fileSizeBytes = 0;
  int updatedAtMs = 0;
}
