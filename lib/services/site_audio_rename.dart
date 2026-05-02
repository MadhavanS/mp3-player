// Port of Java SiteTextConst + SiteAudioRenamer (songsPKRenamer) filename cleanup.
// Suggests a clean basename (no .mp3) and tag values matching Java TagEdit.setTag split.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of [computeSiteRename]; user may confirm before rename + tag write.
class SiteRenameSuggestion {
  SiteRenameSuggestion({
    required this.newBasenameWithoutExt,
    required this.suggestedAlbum,
    required this.suggestedTitle,
    required this.originalBasenameWithoutExt,
  });

  final String newBasenameWithoutExt;
  final String suggestedAlbum;
  final String suggestedTitle;
  final String originalBasenameWithoutExt;

  bool get filenameChanged =>
      newBasenameWithoutExt != originalBasenameWithoutExt;

  bool get hasSuggestion =>
      newBasenameWithoutExt.isNotEmpty &&
      (filenameChanged ||
          suggestedAlbum.isNotEmpty ||
          suggestedTitle.isNotEmpty);
}

abstract final class SiteTextConst {
  static const starmusiqFun = 'StarMusiQ.Fun';
  static const starmusiqOne = 'StarMusiQ.One';
  static const starmusiq5 = '5StarMusiQ.Com';
  static const starmusiqtop = 'StarMusiQ.Top';
  static const sunmusiq = 'SunMusiQ.Com';
  static const tamilwire = 'TamilWire.com';
  static const vmusiq = 'VmusiQ.Com';
  static const masstamilanIO = 'MassTamilan.io';
  static const masstamilanCom = 'MassTamilan.com';
  static const masstamilanFM = 'MassTamilan.fm';
  static const masstamilanDev = 'MassTamilan.dev';
  static const masstamila = 'MassTamila';
  static const masstamilanSo = 'MassTamilan.so';
  static const starmusiq = 'StarMusiQ.Com';
  static const downloadSouthMp3 = 'DownloadSouthMP3.SE';
  static const tnWaps = 'TNwaps.com';
  static const songsPK = '[Songs.PK]';
  static const songsPKLink = '[Songspk.LINK]';
  static const tamilDaDa = 'TamilDaDa.info';
  static const sebastian = 'Sebastian[Ub3r]';
  static const hindiMp3India = 'Hindimp3india.Com';
  static const downloadMing = 'DownloadMing.SE';
  static const downloadMingLA = 'DownloadMing.LA';
  static const downloadMingCom = 'www.downloadming.com';
  static const newtamilhits = 'NewTamilHits.Com';
  static const maango = '[Maango.me]';
  static const maangoInfo = '[Maango.info]';
  static const maangoWS = '[Maango.ws]';
  static const maaMp3 = '[www.MaaMp3.com]';
  static const iSongsInfo = '[iSongs.info]';
  static const songsNut = '[Songsnut.com]';
  static const sensongsMp3 = 'SenSongsMp3.Co';
  static const sensongsCom = 'www.sensongs.com';
  static const singamdaCom = 'Singamda.Com';
  static const tnWapNet = 'Tnwap.Net';
  static const tgx = '[TGx]';
  static const uyirvani = 'www.uyirvani.com';
}

String _stripExtension(String? str) {
  if (str == null || str.isEmpty) return '';
  final pos = str.lastIndexOf('.');
  if (pos == -1) return str;
  return str.substring(0, pos);
}

RegExp _pattern(String pat) => RegExp(pat);

bool _patternFind(String str, String pat) => _pattern(pat).hasMatch(str);

String _capitalize(String line) {
  if (line.isEmpty) return line;
  final c = line.codeUnitAt(0);
  if (c >= 65 && c <= 90) return line;
  return String.fromCharCode(c >= 97 && c <= 122 ? c - 32 : c) +
      line.substring(1);
}

String _capitalizeWords(String s) {
  if (s.trim().isEmpty) return s;
  return s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(_capitalize)
      .join(' ');
}

/// Mirrors Java TagEdit.setTag: album = segment before first '-', title = rest (or full if single).
void splitBasenameLikeJavaSetTag(String base, void Function(String album, String title) out) {
  final b = base.trim();
  final dash = b.indexOf('-');
  if (dash == -1) {
    final one = b;
    out(one, one);
    return;
  }
  out(b.substring(0, dash).trim(), b.substring(dash + 1).trim());
}

String _albumNameFromTags(String? raw) {
  if (raw == null) return '';
  var albumName = raw.trim();
  if (albumName.toLowerCase() == 'title') return '';

  final parts = albumName.split('-');
  final buf = StringBuffer();
  for (final s0 in parts) {
    var s = s0;
    final t = s.toLowerCase().trim();
    if (t.contains(SiteTextConst.vmusiq.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamilanIO.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamilanFM.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamilanDev.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamilanCom.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamilanSo.toLowerCase())) {
      continue;
    } else if (t == SiteTextConst.starmusiq.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.downloadSouthMp3.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.hindiMp3India.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.songsPK.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.tamilwire.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.uyirvani.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.newtamilhits.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.maango.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.maangoInfo.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.maangoWS.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.maaMp3.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.songsNut.toLowerCase()) {
      continue;
    } else if (t == SiteTextConst.sensongsMp3.toLowerCase()) {
      continue;
    } else if (t.contains(SiteTextConst.sensongsCom.toLowerCase()) ||
        t.contains(SiteTextConst.singamdaCom.toLowerCase())) {
      final lower = s.toLowerCase();
      final start = lower.indexOf(':');
      final end = lower.lastIndexOf(':');
      if (start > 0 && end >= start) {
        s = s.replaceRange(start > 0 ? start - 1 : start, end + 1, '');
      }
      s = s.replaceAll('®', '');
      buf.write(s);
    } else if (t.contains(SiteTextConst.tamilDaDa.toLowerCase())) {
      continue;
    } else if (t.contains(SiteTextConst.masstamila.toLowerCase())) {
      continue;
    } else {
      buf.write(s0);
    }
  }
  return buf.toString();
}

String _songsPkSite(String str) {
  var parts = str.split('-');
  var temp = StringBuffer();
  for (final s in parts) {
    if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]'), ''));
      temp.write('-');
    } else {
      temp.write(s);
    }
  }
  var tempStr = temp.toString();
  if (!tempStr.contains('-')) {
    if (_patternFind(str.replaceAll(' ', ''), r'^\[[\w.[\w]+][0-9]+')) {
      tempStr = str
          .replaceAll(' ', '')
          .replaceFirst(RegExp(r'^\[[\w.]+\][0-9]+-'), '');
    }
  }
  final words = tempStr.split(' ');
  final fin = StringBuffer();
  for (final s in words) {
    if (s == SiteTextConst.songsPK ||
        s == SiteTextConst.songsPKLink ||
        s == SiteTextConst.iSongsInfo) {
      continue;
    }
    if (_patternFind(s.trim(), r'^[0-9]')) {
      continue;
    }
    fin.write(s);
  }
  return fin.toString();
}

String _tnWaps(String str) {
  var parts = str.split('-');
  var temp = StringBuffer();
  for (final s in parts) {
    if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]'), ''));
    } else {
      temp.write(s);
    }
  }
  final fin = StringBuffer();
  for (final s in temp.toString().split(' ')) {
    if (s.toLowerCase() == SiteTextConst.tnWaps.toLowerCase()) {
      continue;
    }
    fin.write(s);
  }
  return fin.toString();
}

String _songsNut(String str) {
  var parts = str.split('-');
  var temp = StringBuffer();
  for (final s in parts) {
    final tr = s.trim();
    if (_patternFind(tr, r'^[0-9]+\.')) {
      temp.write(tr.replaceFirst(RegExp(r'^[0-9]+\.'), ''));
    } else if (_patternFind(tr.toLowerCase(), r'^[0-9]+kbps')) {
      temp.write(tr.replaceFirst(RegExp(r'^[0-9]+kbps', caseSensitive: false), ''));
    } else {
      temp.write(s);
    }
  }
  final fin = StringBuffer();
  for (final s in temp.toString().split(' ')) {
    if (s.toLowerCase() == SiteTextConst.songsNut.toLowerCase()) {
      continue;
    }
    fin.write(s);
  }
  return fin.toString();
}

String _tamilDaDa(String str) {
  final fin = StringBuffer();
  for (final s in str.split(' ')) {
    if (s.toLowerCase().contains(SiteTextConst.tamilDaDa.toLowerCase())) {
      break;
    }
    fin.write(s);
  }
  return fin.toString();
}

String _tamilWire(String str) {
  final fin = StringBuffer();
  for (final s in str.split('-')) {
    final t = s.toLowerCase().trim();
    if (t == SiteTextConst.tamilwire.toLowerCase()) {
      continue;
    }
    if (fin.isEmpty) {
      fin.write(s.trim());
    } else {
      fin.write(' - ');
      fin.write(s.trim());
    }
  }
  return fin.toString();
}

String _downloadSouthMp3(String str) {
  var parts = str.split('-');
  var temp = StringBuffer();
  for (final s in parts) {
    if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]'), ''));
    } else {
      if (temp.toString().trim().isEmpty) {
        temp.write(s);
      } else {
        temp.write('-');
        temp.write(s);
      }
    }
  }
  final fin = StringBuffer();
  for (final s in temp.toString().split(' ')) {
    final t = s.toLowerCase();
    if (t == SiteTextConst.songsPKLink.toLowerCase() ||
        t == SiteTextConst.maango.toLowerCase() ||
        t == SiteTextConst.maangoWS.toLowerCase() ||
        t == SiteTextConst.maangoInfo.toLowerCase() ||
        t == SiteTextConst.maaMp3.toLowerCase()) {
      continue;
    }
    if (!(t == SiteTextConst.downloadSouthMp3.toLowerCase() ||
        t == SiteTextConst.downloadMing.toLowerCase() ||
        t == SiteTextConst.downloadMingCom.toLowerCase() ||
        t == SiteTextConst.downloadMingLA.toLowerCase())) {
      fin.write(s);
    }
  }
  return fin.toString();
}

String _senSongs(String str) {
  var temp = StringBuffer();
  for (final s in str.split(' ')) {
    if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]'), ''));
    } else {
      temp.write(_capitalize(s));
    }
  }
  final fin = StringBuffer();
  for (final s in temp.toString().split('-')) {
    final t = s.toLowerCase();
    if (t.contains(SiteTextConst.sensongsMp3.toLowerCase())) {
      continue;
    }
    if (t.contains(SiteTextConst.sensongsCom.toLowerCase())) {
      continue;
    }
    fin.write(s);
  }
  return fin.toString();
}

String _starMusiq(String str) {
  var temp = StringBuffer();
  for (final s in str.split('_')) {
    if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]'), ''));
    } else {
      temp.write(s);
    }
  }
  final fin = StringBuffer();
  for (final s in temp.toString().split('-')) {
    final t = s.toLowerCase();
    if (t.contains(SiteTextConst.vmusiq.toLowerCase())) {
      if (t == SiteTextConst.vmusiq.toLowerCase()) {
        continue;
      }
      fin.write(s.replaceAll(SiteTextConst.vmusiq, ''));
    } else if (t == SiteTextConst.starmusiq.toLowerCase() ||
        t == SiteTextConst.sunmusiq.toLowerCase() ||
        t == SiteTextConst.starmusiqtop.toLowerCase() ||
        t == SiteTextConst.starmusiqFun.toLowerCase() ||
        t == SiteTextConst.starmusiqOne.toLowerCase() ||
        t == SiteTextConst.starmusiq5.toLowerCase() ||
        t == SiteTextConst.tnWapNet.toLowerCase() ||
        t == SiteTextConst.masstamilanIO.toLowerCase() ||
        t == SiteTextConst.masstamilanFM.toLowerCase() ||
        t == SiteTextConst.masstamilanCom.toLowerCase() ||
        t == SiteTextConst.masstamilanDev.toLowerCase() ||
        t == SiteTextConst.masstamilanSo.toLowerCase()) {
      break;
    } else {
      fin.write(s);
    }
  }
  return fin.toString();
}

String _newTamilHits(String str) {
  for (final s in str.split('-')) {
    if (s.contains('NewTamilHits.Com')) {
      return s.replaceAll('NewTamilHits.Com', '').replaceAll('_', '');
    }
  }
  return '';
}

String _tgxFromTags(String artist, String title) {
  if (artist.trim().isEmpty && title.trim().isEmpty) {
    return '';
  }
  return '${_capitalizeWords(artist)} - ${_capitalizeWords(title)}';
}

class _SplitOutcome {
  _SplitOutcome(this.text, {this.usedTgx = false});
  final String text;
  final bool usedTgx;
}

_SplitOutcome _splitString(
  String str, {
  required String id3Artist,
  required String id3Title,
}) {
  if (RegExp(r'^[0-9]+$').hasMatch(str)) {
    //
  }
  final splitted = str.split(' ');
  var temp = StringBuffer();
  for (final s in splitted) {
    if (s == SiteTextConst.sebastian || s == SiteTextConst.hindiMp3India) {
      continue;
    }
    if (s == SiteTextConst.songsPK || s == SiteTextConst.iSongsInfo) {
      return _SplitOutcome(_songsPkSite(str));
    }
    if (s.contains(SiteTextConst.tnWaps)) {
      return _SplitOutcome(_tnWaps(str));
    }
    if (s.contains(SiteTextConst.tamilwire)) {
      return _SplitOutcome(_tamilWire(str));
    }
    if (s.contains(SiteTextConst.downloadSouthMp3) ||
        s.contains(SiteTextConst.downloadMing) ||
        s.contains(SiteTextConst.downloadMingCom) ||
        s.contains(SiteTextConst.maango) ||
        s.contains(SiteTextConst.maaMp3) ||
        s == SiteTextConst.songsPKLink ||
        s.contains(SiteTextConst.downloadMingLA) ||
        s.contains(SiteTextConst.maangoInfo) ||
        s.contains(SiteTextConst.maangoWS)) {
      return _SplitOutcome(_downloadSouthMp3(str));
    }
    if (s.contains(SiteTextConst.vmusiq) ||
        s.contains(SiteTextConst.starmusiq) ||
        s.contains(SiteTextConst.starmusiqtop) ||
        s.contains(SiteTextConst.sunmusiq) ||
        s.contains(SiteTextConst.starmusiqFun) ||
        s.contains(SiteTextConst.masstamilanFM) ||
        s.contains(SiteTextConst.starmusiqOne) ||
        s.contains(SiteTextConst.tnWapNet) ||
        s.contains(SiteTextConst.masstamilanIO) ||
        s.contains(SiteTextConst.masstamilanCom) ||
        s.contains(SiteTextConst.masstamilanDev) ||
        s.contains(SiteTextConst.masstamilanSo)) {
      return _SplitOutcome(_starMusiq(str));
    }
    if (s.contains(SiteTextConst.newtamilhits)) {
      return _SplitOutcome(_newTamilHits(str));
    }
    if (s.contains(SiteTextConst.songsNut)) {
      return _SplitOutcome(_songsNut(str));
    }
    if (s.contains(SiteTextConst.sensongsMp3) ||
        s.contains(SiteTextConst.sensongsCom)) {
      return _SplitOutcome(_senSongs(str));
    }
    if (s.contains(SiteTextConst.tamilDaDa)) {
      return _SplitOutcome(_tamilDaDa(str));
    }
    if (s.contains(SiteTextConst.tgx)) {
      final line = _tgxFromTags(id3Artist, id3Title);
      if (line.isEmpty) {
        temp.write(_capitalize(s));
      } else {
        return _SplitOutcome(line, usedTgx: true);
      }
    } else if (_patternFind(s.trim(), r'^[0-9]')) {
      temp.write(s.replaceAll(RegExp(r'[0-9]*[\.\-]'), ''));
    } else {
      temp.write(_capitalize(s));
    }
  }
  return _SplitOutcome(temp.toString());
}

String _getMp3Status(
  String newFileName,
  String albumRaw,
  String originalBaseNoExt,
  String originalFileNameWithExt, {
  required bool skipAlbumRefine,
}) {
  if (skipAlbumRefine) return newFileName.trim();

  var newName = newFileName.trim();
  final albumName = _albumNameFromTags(albumRaw.isEmpty ? null : albumRaw);
  final albumCompact = albumName.replaceAll(' ', '');

  if ('$newName.mp3'.replaceAll(' ', '') ==
          originalFileNameWithExt.replaceAll(' ', '') &&
      albumCompact.isNotEmpty &&
      newName.contains(albumCompact)) {
    return originalBaseNoExt.trim();
  }

  if (newName.contains(albumCompact.replaceAll(RegExp(r'\(\d+\)?'), '').replaceAll(RegExp(r'\(\w+\)?'), ''))) {
    newName = newName.replaceAll(RegExp(r'\(\d+\)?'), '').replaceAll(RegExp(r'\(\w+\)?'), '');
  } else if (albumName.isNotEmpty) {
    if (!newName.contains(albumCompact.replaceAll(RegExp(r'\(\d+\)'), '')) &&
        !newName.contains(albumName.replaceAll(' ', ''))) {
      var alb = albumName;
      if (alb.contains('| Songsnut.')) {
        alb = alb.replaceAll('| Songsnut.', '');
      } else if (alb.contains('- TamilDaDa.Info')) {
        alb = alb.replaceAll('- TamilDaDa.Info', '');
      }
      newName = '${alb.trim().replaceAll(' ', '')} - $newName';
    } else if (newName.trim() == albumName || newName == albumName.replaceAll(' ', '')) {
      newName = '${albumName.trim().replaceAll(' ', '')} - ${newName.trim()}';
    } else if (newName.trim().startsWith(albumName) &&
        newName.trim().length != albumName.trim().length) {
      if (newName.trim().length == albumName.trim().length) {
        if (!newName.contains('$albumName-')) {
          newName = newName.replaceAll(albumName, '$albumName -');
        }
      } else {
        newName = '${albumName.trim().replaceAll(' ', '')} - ${newName.trim()}';
      }
    } else if (newName.trim().startsWith(albumName.replaceAll(' ', '')) &&
        newName.trim() == albumName &&
        newName == albumName.replaceAll(' ', '')) {
      newName = newName.replaceAll(albumName.replaceAll(' ', ''), '$albumName - ');
    }
  }
  return newName.trim();
}

/// Computes a clean filename + album/title split (Java SiteAudioRenamer + TagEdit.setTag).
SiteRenameSuggestion computeSiteRename({
  required String filePath,
  required String? albumFromTags,
  required String artistFromTags,
  required String titleFromTags,
}) {
  final filename = p.basename(filePath);
  final originalBase = _stripExtension(filename);
  final split = _splitString(originalBase, id3Artist: artistFromTags, id3Title: titleFromTags);
  var fName = split.text;
  fName = _getMp3Status(
    fName,
    albumFromTags ?? '',
    originalBase,
    filename,
    skipAlbumRefine: split.usedTgx,
  );

  var album = '';
  var title = '';
  splitBasenameLikeJavaSetTag(fName, (a, t) {
    album = a;
    title = t;
  });

  return SiteRenameSuggestion(
    newBasenameWithoutExt: fName,
    suggestedAlbum: album,
    suggestedTitle: title,
    originalBasenameWithoutExt: originalBase,
  );
}

/// Renames [oldPath] to sibling `$newBasenameWithoutExt.mp3`. Returns new path.
Future<String> renameMp3File(String oldPath, String newBasenameWithoutExt) async {
  final old = File(oldPath);
  if (!await old.exists()) {
    throw StateError('File not found.');
  }
  final dir = old.parent.path;
  final targetName = newBasenameWithoutExt.trim().isEmpty
      ? p.basenameWithoutExtension(oldPath)
      : newBasenameWithoutExt.trim();
  final newPath = p.join(dir, '$targetName.mp3');
  final normOld = p.normalize(oldPath);
  final normNew = p.normalize(newPath);
  if (normOld == normNew) {
    return normOld;
  }
  if (await File(newPath).exists()) {
    throw StateError('Target already exists: $targetName.mp3');
  }
  await old.rename(newPath);
  return normNew;
}

