import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/services/ape_tag_writer_io.dart';

void main() {
  test('rewrites APE text items and preserves audio prefix', () async {
    final dir = await Directory.systemTemp.createTemp('ape_tag_test_');
    final file = File('${dir.path}/track.mp3');
    try {
      await file.writeAsBytes(_minimalApeTaggedFile(
        title: 'Before',
        artist: 'Old Artist',
      ));

      final meta = readAllMetadata(file);
      expect(meta, isA<ApeMetadata>());
      final ape = meta as ApeMetadata;
      ape.title = 'After Rename';
      ape.artist = 'New Artist';
      ape.genres = ['Rock'];

      await ApeTagWriter.write(file, ape);

      final reread = readAllMetadata(file) as ApeMetadata;
      expect(reread.title, 'After Rename');
      expect(reread.artist, 'New Artist');
      expect(reread.genres, contains('Rock'));

      final raw = await file.readAsBytes();
      expect(String.fromCharCodes(raw.sublist(0, 4)), 'fLaC');
      expect(
        String.fromCharCodes(raw.sublist(raw.length - 32, raw.length - 24)),
        'APETAGEX',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

/// Fake audio + single APE text item + footer (no ID3v1).
Uint8List _minimalApeTaggedFile({
  required String title,
  String artist = '',
}) {
  final audio = ascii.encode('fLaC') + List<int>.filled(64, 0);
  final items = BytesBuilder(copy: false);
  void text(String key, String value) {
    final keyBytes = <int>[...utf8.encode(key), 0];
    final valueBytes = utf8.encode(value);
    items.add(_le32(valueBytes.length));
    items.add(_le32(0));
    items.add(keyBytes);
    items.add(valueBytes);
  }

  text('Title', title);
  if (artist.isNotEmpty) text('Artist', artist);

  final itemBytes = items.toBytes();
  final footer = BytesBuilder(copy: false);
  footer.add(ascii.encode('APETAGEX'));
  footer.add(_le32(2000));
  footer.add(_le32(itemBytes.length + 32));
  footer.add(_le32(artist.isNotEmpty ? 2 : 1));
  footer.add(_le32(0x40000000));
  footer.add(Uint8List(8));

  final out = BytesBuilder(copy: false);
  out.add(audio);
  out.add(itemBytes);
  out.add(footer.toBytes());
  return out.toBytes();
}

Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);
