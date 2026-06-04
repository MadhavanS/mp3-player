import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

const int _kApeFooterLength = 32;
const int _kApeVersion = 2000;
const int _kApeFooterPresentFlag = 0x40000000;

/// APEv2 tag writer for files detected by [ApeParser] (footer at EOF or before ID3v1).
///
/// `audio_metadata_reader` 1.6.x is read-only for APE; MadPlayer rebuilds the tag
/// block and preserves trailing ID3v1 when present.
class ApeTagWriter {

  /// Rewrites the APEv2 block at the end of [file] from [metadata].
  static Future<void> write(File file, ApeMetadata metadata) async {
    final raw = await file.readAsBytes();
    final layout = locateApeLayout(raw);
    if (layout == null) {
      throw StateError('No APEv2 footer found.');
    }

    final itemBytes = _encodeItems(_itemsFromMetadata(metadata));
    if (itemBytes.isEmpty) {
      throw StateError('APE tag has no items to write.');
    }

    final footer = _encodeFooter(
      itemCount: _countItems(itemBytes),
      tagSize: itemBytes.length + _kApeFooterLength,
      flags: _kApeFooterPresentFlag,
    );

    final out = BytesBuilder(copy: false);
    out.add(raw.sublist(0, layout.tagStart));
    out.add(itemBytes);
    out.add(footer);
    if (layout.id3v1Suffix != null) {
      out.add(layout.id3v1Suffix!);
    }

    final bytes = out.toBytes();
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'apetag_${DateTime.now().microsecondsSinceEpoch}.bin',
      ),
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.copy(file.path);
      final written = await file.readAsBytes();
      if (written.length != bytes.length) {
        throw StateError(
          'APE write verification failed (file size ${written.length} vs ${bytes.length}).',
        );
      }
      if (locateApeLayout(written, requireItems: true) == null) {
        throw StateError('APE write verification failed: footer not readable.');
      }
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }
}

class ApeFileLayout {
  ApeFileLayout({
    required this.tagStart,
    required this.footerOffset,
    this.id3v1Suffix,
  });

  final int tagStart;
  final int footerOffset;
  final Uint8List? id3v1Suffix;
}

int _countItems(Uint8List itemBytes) {
  var count = 0;
  var i = 0;
  while (i + 8 <= itemBytes.length) {
    final valueSize = _getUint32LE(itemBytes, i);
    i += 4;
    i += 4; // flags
    while (i < itemBytes.length && itemBytes[i] != 0) {
      i++;
    }
    i++; // NUL after key
    i += valueSize;
    count++;
  }
  return count;
}

/// Returns tag region layout when [raw] ends with a valid APEv2 footer.
ApeFileLayout? locateApeLayout(Uint8List raw, {bool requireItems = false}) {
  if (raw.length < _kApeFooterLength) return null;

  final length = raw.length;
  Uint8List? id3v1Suffix;

  var footerOffset = length - _kApeFooterLength;
  if (!_isApeFooterAt(raw, footerOffset)) {
    if (length >= 160 && _isId3v1At(raw, length - 128)) {
      id3v1Suffix = Uint8List.sublistView(raw, length - 128);
      footerOffset = length - 160;
      if (!_isApeFooterAt(raw, footerOffset)) return null;
    } else {
      return null;
    }
  }

  final footerSize = _getUint32LE(raw, footerOffset + 12);
  final itemCount = _getUint32LE(raw, footerOffset + 16);
  if (footerSize < _kApeFooterLength || footerSize > length) return null;

  final candidates = <int>{
    footerOffset - (footerSize - _kApeFooterLength),
    footerOffset - footerSize,
  }.where((o) => o >= 0);

  for (final start in candidates) {
    if (_itemsDecode(raw, start, footerOffset, itemCount)) {
      return ApeFileLayout(
        tagStart: start,
        footerOffset: footerOffset,
        id3v1Suffix: id3v1Suffix,
      );
    }
  }

  if (!requireItems) {
    final fallback = footerOffset - (footerSize - _kApeFooterLength);
    if (fallback >= 0) {
      return ApeFileLayout(
        tagStart: fallback,
        footerOffset: footerOffset,
        id3v1Suffix: id3v1Suffix,
      );
    }
  }
  return null;
}

bool _isApeFooterAt(Uint8List raw, int offset) {
  if (offset < 0 || offset + 8 > raw.length) return false;
  return String.fromCharCodes(raw.sublist(offset, offset + 8)) == 'APETAGEX';
}

bool _isId3v1At(Uint8List raw, int offset) {
  if (offset < 0 || offset + 3 > raw.length) return false;
  return String.fromCharCodes(raw.sublist(offset, offset + 3)) == 'TAG';
}

bool _itemsDecode(
  Uint8List raw,
  int start,
  int footerOffset,
  int itemCount,
) {
  var i = start;
  for (var n = 0; n < itemCount; n++) {
    if (i + 8 > footerOffset) return false;
    final valueSize = _getUint32LE(raw, i);
    i += 8;
    while (i < footerOffset && raw[i] != 0) {
      i++;
    }
    if (i >= footerOffset) return false;
    i++;
    if (i + valueSize > footerOffset) return false;
    i += valueSize;
  }
  return i <= footerOffset;
}

int _getUint32LE(Uint8List data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

Uint8List _intToUint32LE(int value) {
  return Uint8List.fromList([
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ]);
}

class _ApeItem {
  _ApeItem.text(this.key, this.text) : binary = null;
  _ApeItem.binary(this.key, this.binary) : text = null;

  final String key;
  final String? text;
  final Uint8List? binary;
}

List<_ApeItem> _itemsFromMetadata(ApeMetadata metadata) {
  final items = <_ApeItem>[];
  final writtenKeys = <String>{};

  void text(String key, String? value) {
    if (value == null || value.trim().isEmpty) return;
    final k = key.trim();
    if (k.isEmpty || !writtenKeys.add(k.toUpperCase())) return;
    items.add(_ApeItem.text(k, value.trim()));
  }

  text('Title', metadata.title);
  text('Artist', metadata.artist);
  text('Album', metadata.album);
  text('Album Artist', metadata.albumArtist);
  text('Composer', metadata.composer);
  text('Comment', metadata.comment);
  text('Copyright', metadata.copyright);
  text('Encoded By', metadata.encodedBy);
  text('Lyrics', metadata.lyric);

  if (metadata.date != null) {
    text('Year', '${metadata.date!.year}');
  }

  if (metadata.trackNumber != null) {
    final n = metadata.trackNumber!;
    final t = metadata.trackTotal;
    text('Track', t != null ? '$n/$t' : '$n');
  } else if (metadata.trackTotal != null) {
    text('Tracktotal', '${metadata.trackTotal}');
  }

  if (metadata.discNumber != null) {
    final n = metadata.discNumber!;
    final t = metadata.discTotal;
    text('Disc', t != null ? '$n/$t' : '$n');
  } else if (metadata.discTotal != null) {
    text('Disctotal', '${metadata.discTotal}');
  }

  for (final g in metadata.genres) {
    final genre = g.trim();
    if (genre.isNotEmpty) {
      items.add(_ApeItem.text('Genre', genre));
    }
  }

  for (final p in metadata.performer) {
    final v = p.trim();
    if (v.isNotEmpty) items.add(_ApeItem.text('Performer', v));
  }

  for (final lang in metadata.language) {
    final v = lang.trim();
    if (v.isNotEmpty) items.add(_ApeItem.text('Language', v));
  }

  for (final entry in metadata.unknowns.entries) {
    final k = entry.key.trim();
    final v = entry.value.trim();
    if (k.isEmpty || v.isEmpty) continue;
    if (!writtenKeys.add(k.toUpperCase())) continue;
    items.add(_ApeItem.text(k, v));
  }

  for (final pic in metadata.pictures) {
    if (pic.bytes.isEmpty) continue;
    final key = pic.pictureType == PictureType.coverBack
        ? 'Cover Art (Back)'
        : 'Cover Art (Front)';
    final desc = pic.pictureType == PictureType.coverBack
        ? 'Back Cover.jpg'
        : 'Front Cover.jpg';
    final payload = BytesBuilder(copy: false);
    payload.add(utf8.encode(desc));
    payload.addByte(0);
    payload.add(pic.bytes);
    items.add(_ApeItem.binary(key, payload.toBytes()));
  }

  return items;
}

Uint8List _encodeItems(List<_ApeItem> items) {
  final b = BytesBuilder(copy: false);
  for (final item in items) {
    if (item.text != null) {
      _appendTextItem(b, item.key, item.text!);
    } else if (item.binary != null) {
      _appendBinaryItem(b, item.key, item.binary!);
    }
  }
  return b.toBytes();
}

void _appendTextItem(BytesBuilder b, String key, String value) {
  final keyBytes = [...utf8.encode(key), 0];
  final valueBytes = utf8.encode(value);
  b.add(_intToUint32LE(valueBytes.length));
  b.add(_intToUint32LE(0)); // text, not read-only
  b.add(keyBytes);
  b.add(valueBytes);
}

void _appendBinaryItem(BytesBuilder b, String key, Uint8List value) {
  final keyBytes = [...utf8.encode(key), 0];
  b.add(_intToUint32LE(value.length));
  b.add(_intToUint32LE(2)); // binary (type bits = 01)
  b.add(keyBytes);
  b.add(value);
}

Uint8List _encodeFooter({
  required int itemCount,
  required int tagSize,
  required int flags,
}) {
  final footer = BytesBuilder(copy: false);
  footer.add(ascii.encode('APETAGEX'));
  footer.add(_intToUint32LE(_kApeVersion));
  footer.add(_intToUint32LE(tagSize));
  footer.add(_intToUint32LE(itemCount));
  footer.add(_intToUint32LE(flags));
  footer.add(Uint8List(8)); // reserved
  return footer.toBytes();
}

/// True when [file] ends with a readable APEv2 footer (optionally before ID3v1).
Future<bool> fileHasApeFooter(File file) async {
  if (!await file.exists()) return false;
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    return ApeParser.canUserParser(raf);
  } catch (_) {
    return false;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}
