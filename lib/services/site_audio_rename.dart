// Port of tag-editor rules engine semantics for in-app cleanup suggestions.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of [computeSiteRename]; user may confirm before rename + tag write.
class SiteRenameSuggestion {
  SiteRenameSuggestion({
    required this.newBasenameWithoutExt,
    required this.suggestedArtist,
    required this.suggestedAlbum,
    required this.suggestedTitle,
    required this.suggestedGenre,
    required this.originalBasenameWithoutExt,
  });

  final String newBasenameWithoutExt;
  final String suggestedArtist;
  final String suggestedAlbum;
  final String suggestedTitle;
  final String suggestedGenre;
  final String originalBasenameWithoutExt;

  bool get filenameChanged =>
      newBasenameWithoutExt != originalBasenameWithoutExt;

  bool get hasSuggestion =>
      newBasenameWithoutExt.isNotEmpty &&
      (filenameChanged ||
          suggestedArtist.isNotEmpty ||
          suggestedAlbum.isNotEmpty ||
          suggestedTitle.isNotEmpty ||
          suggestedGenre.isNotEmpty);
}

abstract final class SiteTextConst {
  static const title = 'title';
  static const artist = 'artist';
  static const album = 'album';
  static const genre = 'genre';
}

String _stripExtension(String? str) {
  if (str == null || str.isEmpty) return '';
  final pos = str.lastIndexOf('.');
  if (pos == -1) return str;
  return str.substring(0, pos);
}

class _Rule {
  const _Rule({
    required this.name,
    required this.enabled,
    required this.filenameRegex,
    required this.setTags,
    required this.renameTo,
    required this.stripSubstrings,
    required this.stripFields,
    required this.whenTagsContain,
    required this.stripIgnoreCase,
    required this.collapseWhitespace,
    required this.stripTrailingDash,
    this.clearFields = const <String>[],
  });

  final String name;
  final bool enabled;
  final String filenameRegex;
  final Map<String, String> setTags;
  final String renameTo;
  final List<String> stripSubstrings;
  final List<String> stripFields;
  final List<String> whenTagsContain;
  final bool stripIgnoreCase;
  final bool collapseWhitespace;
  final bool stripTrailingDash;
  final List<String> clearFields;
}

const _allFieldKeys = <String>[
  SiteTextConst.title,
  SiteTextConst.artist,
  SiteTextConst.album,
  SiteTextConst.genre,
];

const _rules = <_Rule>[
  _Rule(
    name: 'Masstamilan.com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      ' - MassTamilan.org',
      ' - Masstamilan.org',
      ' - MassTamilan.fm',
      ' - Masstamilan.fm',
      ' - MassTamilan.dev',
      ' - Masstamilan.dev',
      ' - MassTamilan.com',
      ' - Masstamilan.com',
      '- MassTamilan.org',
      '- Masstamilan.org',
      '- MassTamilan.fm',
      '- Masstamilan.fm',
      '- MassTamilan.dev',
      '- Masstamilan.dev',
      '- MassTamilan.com',
      '- Masstamilan.com',
      'MassTamilan.org',
      'MassTamilan.fm',
      'MassTamilan.dev',
      'MassTamilan.com',
      'MassTamilan.io',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
      '[Masstamilan.In]',
      '[MassTamilan.In]',
      'Masstamilan.In',
      'MassTamilan.In',
      ' - Masstamilan.In',
      '- Masstamilan.In',
      '[Massan.In]',
      'Massan.In',
      ' - Massan.In',
      '- Massan.In',
      'MassTamilan.so',
      ' - MassTamilan.so',
      '- MassTamilan.so',
      '[MassTamilan.so]',
      'MassTamilan',
      'MassTamilan ',
      ' - MassTamilan',
      '- MassTamilan',
      '[MassTamilan]',
      '(MassTamilan)',
      '::MassTamilan::',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment'],
    whenTagsContain: [
      'masstamilan.com',
      'masstamilan.dev',
      'masstamilan.fm',
      'masstamilan.org',
      'masstamilan.in',
      'massan.in',
      'masstamilan.so',
      'masstamilan.io',
      'masstamilan',
    ],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: '5StarMusiQ.Com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecase} - {title_titlecompact}.mp3',
    stripSubstrings: [
      '5StarMusiQ.Com -',
      '5starmusiq.com -',
      'StarMusiQ.Com -',
      'starmusiq.com -',
      'VmusiQ.Com -',
      'vmusiq.com -',
      ' - 5StarMusiQ.Com',
      ' - 5starmusiq.com',
      ' - StarMusiQ.Com',
      ' - starmusiq.com',
      ' - VmusiQ.Com',
      ' - vmusiq.com',
      '- 5StarMusiQ.Com',
      '- 5starmusiq.com',
      '- StarMusiQ.Com',
      '- starmusiq.com',
      '- VmusiQ.Com',
      '- vmusiq.com',
      '5StarMusiQ.Com',
      'StarMusiQ.Com',
      'VmusiQ.Com',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
      'SunMusiQ.Com -',
      ' - SunMusiQ.Com',
      '- SunMusiQ.Com',
      'SunMusiQ.Com',
      'StarMusiQ.One -',
      ' - StarMusiQ.One',
      '- StarMusiQ.One',
      'StarMusiQ.One',
      'StarMusiQ.Fun',
      '-StarMusiQ.Fun',
      ' - StarMusiQ.Fun',
      '- StarMusiQ.Fun',
      'StarMusiQ.Fun -',
      '[StarMusiQ.Fun]',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment'],
    whenTagsContain: [
      '5starmusiq.com',
      'starmusiq.com',
      'vmusiq.com',
      'sunmusiq.com',
      'starmusiq.one',
      'starmusiq.fun',
    ],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'SenSongsMp3.Co cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      ' ::: www.sensongs.com :::  ® Riya collections ®',
      '::: www.sensongs.com ::: ® Riya collections ®',
      '::: www.sensongs.com :::  ® Riya collections ®',
      ':: www.sensongs.com :: ® Riya collections ®',
      'www.sensongs.com ::: ® Riya collections ®',
      '® Riya collections ®',
      ' :: SenSongsMp3.Co',
      ':: SenSongsMp3.Co',
      ', SenSongsMp3.Co',
      'SenSongsMp3.Co',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
      'www.sensongs.com',
      ':: www.sensongs.com ::',
    ],
    stripFields: _allFieldKeys,
    whenTagsContain: ['sensongsmp3.co', 'www.sensongs.com', 'riya collections'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'iSongs.info cleanup',
    enabled: true,
    filenameRegex: r'^\[\s*iSongs\.info\s*\]\s*(\d+)\s*-\s*(.+)\.mp3$',
    setTags: {SiteTextConst.title: r'$2'},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecase}.mp3',
    stripSubstrings: [
      '[iSongs.info]',
      '[ isongs.info ]',
      'iSongs.info',
      'isongs.info',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment'],
    whenTagsContain: [],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'Singamda.Com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecase}.mp3',
    stripSubstrings: [
      '::Singamda.Com::',
      ':: Singamda.Com ::',
      ' ::Singamda.Com:: ',
      'Singamda.Com',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment', 'disc', 'genre'],
    whenTagsContain: ['singamda.com'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'isaimini.co cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      ' :: isaimini.co',
      ':: isaimini.co',
      '::isaimini.co',
      ' :: isaimini.co ::',
      'isaimini.co',
      'Isaimini.Co',
      'ISAIMINI.CO',
      '[isaimini.co]',
      '(isaimini.co)',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
    ],
    stripFields: [
      SiteTextConst.title,
      SiteTextConst.genre,
      SiteTextConst.album,
      SiteTextConst.artist,
    ],
    whenTagsContain: ['isaimini.co'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'DownloadSouthMP3.Com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {SiteTextConst.title: '{title_noleadtrack}'},
    renameTo:
        '{album_titlecompact_cleanyear} - {title_titlecompact_nolead}.mp3',
    stripSubstrings: [
      'DownloadSouthMP3.Com',
      'downloadsouthmp3.com',
      'DownloadSouthMP3.SE',
      'downloadsouthmp3.se',
      'tamil',
      'soundtrack',
      'unknown',
      'soundtrack - tamil',
    ],
    stripFields: _allFieldKeys,
    whenTagsContain: ['downloadsouthmp3.com', 'downloadsouthmp3.se'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'oruTamilsong.com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      'oruTamilsong.com',
      'orutamilsong.com',
      'OruTamilsong.Com',
      'OruTamilSong.Com',
      '[oruTamilsong.com]',
      '[orutamilsong.com]',
      '[OruTamilsong.Com]',
      '- oruTamilsong.com',
      ' - oruTamilsong.com',
      '- OruTamilsong.Com',
      ' - OruTamilsong.Com',
      'tamil',
      'soundtrack',
      'soundtrack - tamil',
      'unknown',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment', 'genre'],
    whenTagsContain: ['orutamilsong.com'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'TamilPaadalgal cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      'TamilPaadalgal.com™',
      'tamilpaadalgal.com™',
      'TamilPaadalgal.com',
      'tamilpaadalgal.com',
      '[TamilPaadalgal.com™]',
      '[tamilpaadalgal.com™]',
      '- TamilPaadalgal.com™',
      ' - TamilPaadalgal.com™',
      '- TamilPaadalgal.com',
      ' - TamilPaadalgal.com',
      'tamil',
      'soundtrack',
      'soundtrack - tamil',
      'unknown',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment', 'track', 'genre'],
    whenTagsContain: ['tamilpaadalgal.com'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
  _Rule(
    name: 'NewTamilHits.Com cleanup',
    enabled: true,
    filenameRegex: '.*',
    setTags: {},
    renameTo: '{album_titlecompact_cleanyear} - {title_titlecompact}.mp3',
    stripSubstrings: [
      'NewTamilHits.Com',
      'newtamilhits.com',
      'NewTamilHits.com',
      '[NewTamilHits.Com]',
      '[newtamilhits.com]',
      '- NewTamilHits.Com',
      ' - NewTamilHits.Com',
      '- newtamilhits.com',
      ' - newtamilhits.com',
      'tamil',
      'soundtrack',
      'soundtrack - tamil',
      'unknown',
    ],
    stripFields: _allFieldKeys,
    clearFields: ['comment', 'track', 'genre'],
    whenTagsContain: ['newtamilhits.com'],
    stripIgnoreCase: true,
    collapseWhitespace: true,
    stripTrailingDash: true,
  ),
];

String _titleWordsSpaced(String text) {
  final out = <String>[];
  for (final w in text.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    out.add(
      w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : ''),
    );
  }
  return out.join(' ');
}

String _titleTitleCompact(String title) =>
    _titleWordsSpaced(title).replaceAll(' ', '');

String _titleDropLeadingTrackNum(String text) {
  final out = text.replaceFirst(
    RegExp(r'^\s*\d{1,3}(?:\s*/\s*\d{1,3})?\s*[-.:)]?\s*'),
    '',
  );
  return out.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

String _albumRenameBase(String text) {
  final base = text
      .replaceAll('(*)', '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
  return base.replaceFirst(RegExp(r'[-–—]+\s*$'), '').trim();
}

String _albumDropYearBrackets(String text) {
  final out = text.replaceAll(RegExp(r'\(\s*\d{4}\s*\)'), ' ');
  return out
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ')
      .replaceFirst(RegExp(r'\s*[-–—]+\s*$'), '')
      .trim();
}

String _sanitizeFilename(String input) {
  var out = input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceFirst(RegExp(r'[. ]+$'), '');
  if (out.isEmpty) return 'untitled';
  return out;
}

/// Applies the same filename cleanup semantics as the tag-editor rules engine,
/// returning a safe basename without extension.
String sanitizeRenameBasename(String input) {
  final raw = input.trim().replaceFirst(
    RegExp(r'\.mp3$', caseSensitive: false),
    '',
  );
  return _sanitizeFilename(raw);
}

String _expandDollarGroups(String template, RegExpMatch? match) {
  if (match == null) return template;
  return template.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
    final idx = int.tryParse(m.group(1) ?? '') ?? -1;
    if (idx == 0) return match.group(0) ?? '';
    if (idx < 0 || idx > match.groupCount) return '';
    return match.group(idx) ?? '';
  });
}

String _expandBraceFields(String template, Map<String, String> fields) {
  var out = template;
  final keys = fields.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    out = out.replaceAll('{$key}', fields[key] ?? '');
  }
  return out;
}

String _expandTemplate(
  String template,
  RegExpMatch? match,
  Map<String, String> fields,
) {
  final withGroups = _expandDollarGroups(template, match);
  return _expandBraceFields(withGroups, fields);
}

bool _matchesWhenTagsContain(
  Map<String, String> fields,
  List<String> triggers,
) {
  final eff = triggers.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (eff.isEmpty) return true;
  for (final value in fields.values) {
    final lower = value.toLowerCase();
    if (eff.any((t) => lower.contains(t.toLowerCase()))) {
      return true;
    }
  }
  return false;
}

void _applySetTags(_Rule rule, Map<String, String> fields, RegExpMatch? match) {
  for (final e in rule.setTags.entries) {
    if (!_allFieldKeys.contains(e.key)) continue;
    fields[e.key] = _expandTemplate(e.value, match, fields);
  }
}

void _applyClearFields(_Rule rule, Map<String, String> fields) {
  for (final key in rule.clearFields) {
    if (!_allFieldKeys.contains(key)) continue;
    fields[key] = '';
  }
}

void _applyStrip(_Rule rule, Map<String, String> fields) {
  var subs = rule.stripSubstrings.where((s) => s.trim().isNotEmpty).toList();
  if (subs.isEmpty) return;
  subs.sort((a, b) => b.length.compareTo(a.length));
  final keys = rule.stripFields.isEmpty ? _allFieldKeys : rule.stripFields;
  for (final key in keys) {
    if (!_allFieldKeys.contains(key)) continue;
    var val = fields[key] ?? '';
    for (final sub in subs) {
      if (rule.stripIgnoreCase) {
        val = val.replaceAll(
          RegExp(RegExp.escape(sub), caseSensitive: false),
          '',
        );
      } else {
        val = val.replaceAll(sub, '');
      }
    }
    fields[key] = val.trim();
  }
}

void _applyCorePostTransforms(_Rule rule, Map<String, String> fields) {
  final album = fields[SiteTextConst.album] ?? '';
  fields[SiteTextConst.album] = album
      .replaceFirst(RegExp(r'\s*\.mp3\s*$', caseSensitive: false), '')
      .trim();

  for (final key in [SiteTextConst.title, SiteTextConst.album]) {
    final value = fields[key] ?? '';
    fields[key] = value.replaceFirst(RegExp(r'_+\s*$'), '').trim();
  }

  if (rule.collapseWhitespace) {
    for (final key in _allFieldKeys) {
      fields[key] = (fields[key] ?? '')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .join(' ');
    }
  }
  if (rule.stripTrailingDash) {
    for (final key in _allFieldKeys) {
      final value = (fields[key] ?? '').trimRight();
      fields[key] = value.endsWith('-')
          ? value.substring(0, value.length - 1).trimRight()
          : value;
    }
  }
}

String? _resolveRename(
  _Rule rule,
  String originalPath,
  Map<String, String> renameFields,
  RegExpMatch? match,
) {
  final template = rule.renameTo.trim();
  if (template.isEmpty) return null;

  final expanded = _expandTemplate(template, match, renameFields).trim();
  if (expanded.isEmpty) return null;

  var name = _sanitizeFilename(expanded);
  if (name.toLowerCase().endsWith('.mp3')) {
    name =
        '${name.substring(0, name.length - 4).trimRight().replaceFirst(RegExp(r'[. ]+$'), '')}.mp3';
  } else {
    name = '${name.trimRight().replaceFirst(RegExp(r'[. ]+$'), '')}.mp3';
  }
  if (name == '.mp3') name = 'untitled.mp3';

  final parent = p.dirname(originalPath);
  final target = p.normalize(p.join(parent, name));
  if (target == p.normalize(originalPath)) return null;
  return p.basenameWithoutExtension(target);
}

/// Computes a clean filename + album/title split (Java SiteAudioRenamer + TagEdit.setTag).
SiteRenameSuggestion computeSiteRename({
  required String filePath,
  required String? albumFromTags,
  required String artistFromTags,
  required String titleFromTags,
  required String genreFromTags,
}) {
  final filename = p.basename(filePath);
  final originalBase = _stripExtension(filename);
  final sourceFields = <String, String>{
    SiteTextConst.title: titleFromTags.trim(),
    SiteTextConst.artist: artistFromTags.trim(),
    SiteTextConst.album: (albumFromTags ?? '').trim(),
    SiteTextConst.genre: genreFromTags.trim(),
    'filename': filename,
    'stem': originalBase,
    'ext': '.mp3',
    'title_noleadtrack': _titleDropLeadingTrackNum(titleFromTags.trim()),
  };

  var chosenName = originalBase;
  var title = sourceFields[SiteTextConst.title] ?? '';
  var artist = sourceFields[SiteTextConst.artist] ?? '';
  var album = sourceFields[SiteTextConst.album] ?? '';
  var genre = sourceFields[SiteTextConst.genre] ?? '';
  var matchedRule = false;

  for (final rule in _rules) {
    if (!rule.enabled) continue;
    if (!_matchesWhenTagsContain(sourceFields, rule.whenTagsContain)) continue;

    RegExpMatch? match;
    if (rule.filenameRegex.trim().isNotEmpty) {
      final regex = RegExp(rule.filenameRegex);
      match = regex.firstMatch(filename);
      if (match == null) continue;
    }

    final fields = <String, String>{
      SiteTextConst.title: sourceFields[SiteTextConst.title] ?? '',
      SiteTextConst.artist: sourceFields[SiteTextConst.artist] ?? '',
      SiteTextConst.album: sourceFields[SiteTextConst.album] ?? '',
      SiteTextConst.genre: sourceFields[SiteTextConst.genre] ?? '',
      'filename': filename,
      'stem': originalBase,
      'ext': '.mp3',
      'title_noleadtrack': sourceFields['title_noleadtrack'] ?? '',
    };

    _applySetTags(rule, fields, match);
    _applyClearFields(rule, fields);
    _applyStrip(rule, fields);
    _applyCorePostTransforms(rule, fields);

    final renameFields = <String, String>{...fields};
    final t = renameFields[SiteTextConst.title] ?? '';
    final a = renameFields[SiteTextConst.album] ?? '';
    renameFields['title_titlecompact'] = _titleTitleCompact(t);
    renameFields['title_titlecase'] = _titleWordsSpaced(t);
    renameFields['title_titlecompact_nolead'] = _titleTitleCompact(
      _titleDropLeadingTrackNum(t),
    );
    renameFields['album_titlecase'] = _titleWordsSpaced(a);
    renameFields['album_titlecase_clean'] = _titleWordsSpaced(
      _albumRenameBase(a),
    );
    renameFields['album_titlecompact_cleanyear'] = _titleTitleCompact(
      _albumDropYearBrackets(_albumRenameBase(a)),
    );

    final renamed = _resolveRename(rule, filePath, renameFields, match);
    if (renamed != null && renamed.trim().isNotEmpty) {
      chosenName = renamed.trim();
    }
    title = fields[SiteTextConst.title] ?? title;
    artist = fields[SiteTextConst.artist] ?? artist;
    album = fields[SiteTextConst.album] ?? album;
    genre = fields[SiteTextConst.genre] ?? genre;
    matchedRule = true;
    break;
  }

  if (!matchedRule) {
    return SiteRenameSuggestion(
      newBasenameWithoutExt: originalBase,
      suggestedArtist: '',
      suggestedAlbum: '',
      suggestedTitle: '',
      suggestedGenre: '',
      originalBasenameWithoutExt: originalBase,
    );
  }

  if (title.trim().isEmpty) {
    title = chosenName;
  }
  if (album.trim().isEmpty) {
    final dash = chosenName.indexOf('-');
    if (dash > 0) album = chosenName.substring(0, dash).trim();
  }

  return SiteRenameSuggestion(
    newBasenameWithoutExt: chosenName,
    suggestedArtist: artist,
    suggestedAlbum: album,
    suggestedTitle: title,
    suggestedGenre: genre,
    originalBasenameWithoutExt: originalBase,
  );
}

/// Renames [oldPath] to sibling `$newBasenameWithoutExt.mp3`. Returns new path.
Future<String> renameMp3File(
  String oldPath,
  String newBasenameWithoutExt,
) async {
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

/// User-visible text for [StateError] from [renameMp3File] when the target name is taken.
String renameTargetExistsUserMessage(StateError e) {
  final m = e.message;
  const prefix = 'Target already exists:';
  if (m.startsWith(prefix)) {
    final file = m.substring(prefix.length).trim();
    return file.isEmpty
        ? 'That MP3 name is already used in this folder.'
        : '$file is already in this folder — rename or remove the other file first.';
  }
  return m.isEmpty ? 'Could not rename file.' : m;
}
