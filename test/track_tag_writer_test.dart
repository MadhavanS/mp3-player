import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/services/track_tag_writer_io.dart';

void main() {
  test('writes ID3 tags including composer on bare MP3', () async {
    final dir = await Directory.systemTemp.createTemp('tag_writer_test_');
    final file = File('${dir.path}/track.mp3');
    try {
      await file.writeAsBytes(List<int>.filled(128, 0));

      await writeEmbeddedAudioTags(
        filePath: file.path,
        title: 'KannaiVittu',
        artist: 'Hariharan, Tippu',
        album: 'Irumugan',
        genre: '',
        composer: 'Harris Javaraj',
        artEdit: AlbumArtEditKind.remove,
      );

      late final Mp3Metadata mp3;
      final raf = await file.open();
      try {
        mp3 = MP3Parser(fetchImage: false).parse(raf);
      } catch (_) {
        rethrow;
      } finally {
        try {
          await raf.close();
        } catch (_) {}
      }

      expect(mp3.songName, 'KannaiVittu');
      expect(mp3.leadPerformer, 'Hariharan, Tippu');
      expect(mp3.album, 'Irumugan');
      expect(mp3.composer, 'Harris Javaraj');
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('writes embedded cover without File closed on MP3 read', () async {
    final dir = await Directory.systemTemp.createTemp('tag_writer_art_test_');
    final file = File('${dir.path}/track.mp3');
    try {
      await file.writeAsBytes(List<int>.filled(128, 0));
      final cover = List<int>.filled(64, 0xFF);

      await writeEmbeddedAudioTags(
        filePath: file.path,
        title: 'Cover Test',
        artist: 'Artist',
        album: 'Album',
        genre: '',
        artEdit: AlbumArtEditKind.replace,
        newCoverBytes: Uint8List.fromList(cover),
        newCoverMimeType: 'image/jpeg',
      );

      final raf = await file.open();
      final mp3 = MP3Parser(fetchImage: true).parse(raf);
      expect(mp3.pictures, isNotEmpty);
      expect(mp3.pictures.first.bytes.length, cover.length);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
