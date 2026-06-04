import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/services/site_audio_rename.dart';

void main() {
  test('resolveTagsForWrite fills title and album from Album - Title basename', () {
    final resolved = resolveTagsForWrite(
      filePath: '/music/Aalavandhan - Kadavul Paathi.mp3',
      editorTitle: '',
      editorArtist: '',
      editorAlbum: '',
      editorGenre: '',
      editorComposer: '',
      initialTitle: '',
      initialArtist: '',
      initialAlbum: '',
      initialGenre: '',
      initialComposer: '',
      embeddedTitle: '',
      embeddedArtist: '',
      embeddedAlbum: '',
      embeddedGenre: '',
      embeddedComposer: '',
    );
    expect(resolved.album, 'Aalavandhan');
    expect(resolved.title, 'Kadavul Paathi');
  });

  test('resolveTagsForWrite keeps embedded tags when editor left blank', () {
    final resolved = resolveTagsForWrite(
      filePath: '/music/Aalavandhan - Kadavul Paathi.mp3',
      editorTitle: 'Aalavandhan - Kadavul Paathi',
      editorArtist: '',
      editorAlbum: '',
      editorGenre: '',
      editorComposer: '',
      initialTitle: 'Aalavandhan - Kadavul Paathi',
      initialArtist: '',
      initialAlbum: '',
      initialGenre: '',
      initialComposer: '',
      embeddedTitle: 'Kadavul Paathi',
      embeddedArtist: 'Kamal Hassan',
      embeddedAlbum: 'Aalavandhan',
      embeddedGenre: 'Soundtrack',
      embeddedComposer: 'Ilaiyaraaja',
    );
    expect(resolved.title, 'Aalavandhan - Kadavul Paathi');
    expect(resolved.artist, 'Kamal Hassan');
    expect(resolved.album, 'Aalavandhan');
  });

  test('resolveTagsForWrite honors explicit clear in editor', () {
    final resolved = resolveTagsForWrite(
      filePath: '/music/song.mp3',
      editorTitle: '',
      editorArtist: '',
      editorAlbum: '',
      editorGenre: '',
      editorComposer: '',
      initialTitle: 'Had Title',
      initialArtist: 'Had Artist',
      initialAlbum: 'Had Album',
      initialGenre: 'Had Genre',
      initialComposer: 'Had Composer',
      embeddedTitle: 'Still On Disk',
      embeddedArtist: 'Still On Disk',
      embeddedAlbum: 'Still On Disk',
      embeddedGenre: 'Still On Disk',
      embeddedComposer: 'Still On Disk',
    );
    expect(resolved.title, '');
    expect(resolved.artist, '');
    expect(resolved.album, '');
    expect(resolved.genre, '');
    expect(resolved.composer, '');
  });

  test('computeSiteRename compacts generic Album - Title basenames', () {
    final suggestion = computeSiteRename(
      filePath: '/music/Aalavandhan - Kadavul Paathi.mp3',
      albumFromTags: null,
      artistFromTags: '',
      titleFromTags: '',
      genreFromTags: '',
    );
    expect(suggestion.filenameChanged, isTrue);
    expect(suggestion.newBasenameWithoutExt, 'Aalavandhan - KadavulPaathi');
    expect(suggestion.suggestedAlbum, 'Aalavandhan');
    expect(suggestion.suggestedTitle, 'Kadavul Paathi');
  });
}
