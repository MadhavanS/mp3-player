// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'youtube_track_record.dart';

// **************************************************************************
// _IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, invalid_use_of_protected_member, lines_longer_than_80_chars, constant_identifier_names, avoid_js_rounded_ints, no_leading_underscores_for_local_identifiers, require_trailing_commas, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_in_if_null_operators, library_private_types_in_public_api, prefer_const_constructors
// ignore_for_file: type=lint

extension GetYoutubeTrackRecordCollection on Isar {
  IsarCollection<int, YoutubeTrackRecord> get youtubeTrackRecords =>
      this.collection();
}

const YoutubeTrackRecordSchema = IsarGeneratedSchema(
  schema: IsarSchema(
    name: 'YoutubeTrackRecord',
    idName: 'id',
    embedded: false,
    properties: [
      IsarPropertySchema(
        name: 'videoId',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'title',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'artist',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'thumbnailUrl',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'localPath',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'downloadedAtMs',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'fileSizeBytes',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'durationMs',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'isDownloaded',
        type: IsarType.bool,
      ),
    ],
    indexes: [
      IsarIndexSchema(
        name: 'videoId',
        properties: [
          "videoId",
        ],
        unique: true,
        hash: false,
      ),
    ],
  ),
  converter: IsarObjectConverter<int, YoutubeTrackRecord>(
    serialize: serializeYoutubeTrackRecord,
    deserialize: deserializeYoutubeTrackRecord,
    deserializeProperty: deserializeYoutubeTrackRecordProp,
  ),
  embeddedSchemas: [],
);

@isarProtected
int serializeYoutubeTrackRecord(IsarWriter writer, YoutubeTrackRecord object) {
  IsarCore.writeString(writer, 1, object.videoId);
  IsarCore.writeString(writer, 2, object.title);
  IsarCore.writeString(writer, 3, object.artist);
  {
    final value = object.thumbnailUrl;
    if (value == null) {
      IsarCore.writeNull(writer, 4);
    } else {
      IsarCore.writeString(writer, 4, value);
    }
  }
  {
    final value = object.localPath;
    if (value == null) {
      IsarCore.writeNull(writer, 5);
    } else {
      IsarCore.writeString(writer, 5, value);
    }
  }
  IsarCore.writeLong(writer, 6, object.downloadedAtMs);
  IsarCore.writeLong(writer, 7, object.fileSizeBytes);
  IsarCore.writeLong(writer, 8, object.durationMs ?? -9223372036854775808);
  IsarCore.writeBool(writer, 9, object.isDownloaded);
  return object.id;
}

@isarProtected
YoutubeTrackRecord deserializeYoutubeTrackRecord(IsarReader reader) {
  final object = YoutubeTrackRecord();
  object.id = IsarCore.readId(reader);
  object.videoId = IsarCore.readString(reader, 1) ?? '';
  object.title = IsarCore.readString(reader, 2) ?? '';
  object.artist = IsarCore.readString(reader, 3) ?? '';
  object.thumbnailUrl = IsarCore.readString(reader, 4);
  object.localPath = IsarCore.readString(reader, 5);
  object.downloadedAtMs = IsarCore.readLong(reader, 6);
  object.fileSizeBytes = IsarCore.readLong(reader, 7);
  {
    final value = IsarCore.readLong(reader, 8);
    if (value == -9223372036854775808) {
      object.durationMs = null;
    } else {
      object.durationMs = value;
    }
  }
  return object;
}

@isarProtected
dynamic deserializeYoutubeTrackRecordProp(IsarReader reader, int property) {
  switch (property) {
    case 0:
      return IsarCore.readId(reader);
    case 1:
      return IsarCore.readString(reader, 1) ?? '';
    case 2:
      return IsarCore.readString(reader, 2) ?? '';
    case 3:
      return IsarCore.readString(reader, 3) ?? '';
    case 4:
      return IsarCore.readString(reader, 4);
    case 5:
      return IsarCore.readString(reader, 5);
    case 6:
      return IsarCore.readLong(reader, 6);
    case 7:
      return IsarCore.readLong(reader, 7);
    case 8:
      {
        final value = IsarCore.readLong(reader, 8);
        if (value == -9223372036854775808) {
          return null;
        } else {
          return value;
        }
      }
    case 9:
      return IsarCore.readBool(reader, 9);
    default:
      throw ArgumentError('Unknown property: $property');
  }
}

sealed class _YoutubeTrackRecordUpdate {
  bool call({
    required int id,
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? localPath,
    int? downloadedAtMs,
    int? fileSizeBytes,
    int? durationMs,
    bool? isDownloaded,
  });
}

class _YoutubeTrackRecordUpdateImpl implements _YoutubeTrackRecordUpdate {
  const _YoutubeTrackRecordUpdateImpl(this.collection);

  final IsarCollection<int, YoutubeTrackRecord> collection;

  @override
  bool call({
    required int id,
    Object? videoId = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? thumbnailUrl = ignore,
    Object? localPath = ignore,
    Object? downloadedAtMs = ignore,
    Object? fileSizeBytes = ignore,
    Object? durationMs = ignore,
    Object? isDownloaded = ignore,
  }) {
    return collection.updateProperties([
          id
        ], {
          if (videoId != ignore) 1: videoId as String?,
          if (title != ignore) 2: title as String?,
          if (artist != ignore) 3: artist as String?,
          if (thumbnailUrl != ignore) 4: thumbnailUrl as String?,
          if (localPath != ignore) 5: localPath as String?,
          if (downloadedAtMs != ignore) 6: downloadedAtMs as int?,
          if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
          if (durationMs != ignore) 8: durationMs as int?,
          if (isDownloaded != ignore) 9: isDownloaded as bool?,
        }) >
        0;
  }
}

sealed class _YoutubeTrackRecordUpdateAll {
  int call({
    required List<int> id,
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? localPath,
    int? downloadedAtMs,
    int? fileSizeBytes,
    int? durationMs,
    bool? isDownloaded,
  });
}

class _YoutubeTrackRecordUpdateAllImpl implements _YoutubeTrackRecordUpdateAll {
  const _YoutubeTrackRecordUpdateAllImpl(this.collection);

  final IsarCollection<int, YoutubeTrackRecord> collection;

  @override
  int call({
    required List<int> id,
    Object? videoId = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? thumbnailUrl = ignore,
    Object? localPath = ignore,
    Object? downloadedAtMs = ignore,
    Object? fileSizeBytes = ignore,
    Object? durationMs = ignore,
    Object? isDownloaded = ignore,
  }) {
    return collection.updateProperties(id, {
      if (videoId != ignore) 1: videoId as String?,
      if (title != ignore) 2: title as String?,
      if (artist != ignore) 3: artist as String?,
      if (thumbnailUrl != ignore) 4: thumbnailUrl as String?,
      if (localPath != ignore) 5: localPath as String?,
      if (downloadedAtMs != ignore) 6: downloadedAtMs as int?,
      if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
      if (durationMs != ignore) 8: durationMs as int?,
      if (isDownloaded != ignore) 9: isDownloaded as bool?,
    });
  }
}

extension YoutubeTrackRecordUpdate on IsarCollection<int, YoutubeTrackRecord> {
  _YoutubeTrackRecordUpdate get update => _YoutubeTrackRecordUpdateImpl(this);

  _YoutubeTrackRecordUpdateAll get updateAll =>
      _YoutubeTrackRecordUpdateAllImpl(this);
}

sealed class _YoutubeTrackRecordQueryUpdate {
  int call({
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? localPath,
    int? downloadedAtMs,
    int? fileSizeBytes,
    int? durationMs,
    bool? isDownloaded,
  });
}

class _YoutubeTrackRecordQueryUpdateImpl
    implements _YoutubeTrackRecordQueryUpdate {
  const _YoutubeTrackRecordQueryUpdateImpl(this.query, {this.limit});

  final IsarQuery<YoutubeTrackRecord> query;
  final int? limit;

  @override
  int call({
    Object? videoId = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? thumbnailUrl = ignore,
    Object? localPath = ignore,
    Object? downloadedAtMs = ignore,
    Object? fileSizeBytes = ignore,
    Object? durationMs = ignore,
    Object? isDownloaded = ignore,
  }) {
    return query.updateProperties(limit: limit, {
      if (videoId != ignore) 1: videoId as String?,
      if (title != ignore) 2: title as String?,
      if (artist != ignore) 3: artist as String?,
      if (thumbnailUrl != ignore) 4: thumbnailUrl as String?,
      if (localPath != ignore) 5: localPath as String?,
      if (downloadedAtMs != ignore) 6: downloadedAtMs as int?,
      if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
      if (durationMs != ignore) 8: durationMs as int?,
      if (isDownloaded != ignore) 9: isDownloaded as bool?,
    });
  }
}

extension YoutubeTrackRecordQueryUpdate on IsarQuery<YoutubeTrackRecord> {
  _YoutubeTrackRecordQueryUpdate get updateFirst =>
      _YoutubeTrackRecordQueryUpdateImpl(this, limit: 1);

  _YoutubeTrackRecordQueryUpdate get updateAll =>
      _YoutubeTrackRecordQueryUpdateImpl(this);
}

class _YoutubeTrackRecordQueryBuilderUpdateImpl
    implements _YoutubeTrackRecordQueryUpdate {
  const _YoutubeTrackRecordQueryBuilderUpdateImpl(this.query, {this.limit});

  final QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QOperations> query;
  final int? limit;

  @override
  int call({
    Object? videoId = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? thumbnailUrl = ignore,
    Object? localPath = ignore,
    Object? downloadedAtMs = ignore,
    Object? fileSizeBytes = ignore,
    Object? durationMs = ignore,
    Object? isDownloaded = ignore,
  }) {
    final q = query.build();
    try {
      return q.updateProperties(limit: limit, {
        if (videoId != ignore) 1: videoId as String?,
        if (title != ignore) 2: title as String?,
        if (artist != ignore) 3: artist as String?,
        if (thumbnailUrl != ignore) 4: thumbnailUrl as String?,
        if (localPath != ignore) 5: localPath as String?,
        if (downloadedAtMs != ignore) 6: downloadedAtMs as int?,
        if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
        if (durationMs != ignore) 8: durationMs as int?,
        if (isDownloaded != ignore) 9: isDownloaded as bool?,
      });
    } finally {
      q.close();
    }
  }
}

extension YoutubeTrackRecordQueryBuilderUpdate
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QOperations> {
  _YoutubeTrackRecordQueryUpdate get updateFirst =>
      _YoutubeTrackRecordQueryBuilderUpdateImpl(this, limit: 1);

  _YoutubeTrackRecordQueryUpdate get updateAll =>
      _YoutubeTrackRecordQueryBuilderUpdateImpl(this);
}

extension YoutubeTrackRecordQueryFilter
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QFilterCondition> {
  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      idBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 0,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 1,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 1,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      videoIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 2,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 2,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 3,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 3,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      artistIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const IsNullCondition(property: 4));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlIsNotNull() {
    return QueryBuilder.apply(not(), (query) {
      return query.addFilterCondition(const IsNullCondition(property: 4));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlGreaterThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlGreaterThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlLessThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlLessThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlBetween(
    String? lower,
    String? upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 4,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 4,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      thumbnailUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const IsNullCondition(property: 5));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathIsNotNull() {
    return QueryBuilder.apply(not(), (query) {
      return query.addFilterCondition(const IsNullCondition(property: 5));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathGreaterThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathGreaterThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathLessThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathLessThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathBetween(
    String? lower,
    String? upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 5,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 5,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      localPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      downloadedAtMsBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 6,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      fileSizeBytesBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 7,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const IsNullCondition(property: 8));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsIsNotNull() {
    return QueryBuilder.apply(not(), (query) {
      return query.addFilterCondition(const IsNullCondition(property: 8));
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsGreaterThan(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsGreaterThanOrEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsLessThan(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsLessThanOrEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      durationMsBetween(
    int? lower,
    int? upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 8,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterFilterCondition>
      isDownloadedEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 9,
          value: value,
        ),
      );
    });
  }
}

extension YoutubeTrackRecordQueryObject
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QFilterCondition> {}

extension YoutubeTrackRecordQuerySortBy
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QSortBy> {
  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByVideoId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByVideoIdDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByTitleDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByArtistDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByThumbnailUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByThumbnailUrlDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByLocalPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByLocalPathDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByDownloadedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByDownloadedAtMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByFileSizeBytesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByIsDownloaded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      sortByIsDownloadedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9, sort: Sort.desc);
    });
  }
}

extension YoutubeTrackRecordQuerySortThenBy
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QSortThenBy> {
  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByVideoId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByVideoIdDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByTitleDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByArtistDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByThumbnailUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByThumbnailUrlDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByLocalPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByLocalPathDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByDownloadedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByDownloadedAtMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByFileSizeBytesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByIsDownloaded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterSortBy>
      thenByIsDownloadedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9, sort: Sort.desc);
    });
  }
}

extension YoutubeTrackRecordQueryWhereDistinct
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QDistinct> {
  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByVideoId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByThumbnailUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByLocalPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByDownloadedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QAfterDistinct>
      distinctByIsDownloaded() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(9);
    });
  }
}

extension YoutubeTrackRecordQueryProperty1
    on QueryBuilder<YoutubeTrackRecord, YoutubeTrackRecord, QProperty> {
  QueryBuilder<YoutubeTrackRecord, int, QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<YoutubeTrackRecord, String, QAfterProperty> videoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<YoutubeTrackRecord, String, QAfterProperty> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<YoutubeTrackRecord, String, QAfterProperty> artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<YoutubeTrackRecord, String?, QAfterProperty>
      thumbnailUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<YoutubeTrackRecord, String?, QAfterProperty>
      localPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<YoutubeTrackRecord, int, QAfterProperty>
      downloadedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, int, QAfterProperty>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, int?, QAfterProperty> durationMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, bool, QAfterProperty>
      isDownloadedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }
}

extension YoutubeTrackRecordQueryProperty2<R>
    on QueryBuilder<YoutubeTrackRecord, R, QAfterProperty> {
  QueryBuilder<YoutubeTrackRecord, (R, int), QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, String), QAfterProperty>
      videoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, String), QAfterProperty>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, String), QAfterProperty>
      artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, String?), QAfterProperty>
      thumbnailUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, String?), QAfterProperty>
      localPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, int), QAfterProperty>
      downloadedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, int), QAfterProperty>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, int?), QAfterProperty>
      durationMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R, bool), QAfterProperty>
      isDownloadedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }
}

extension YoutubeTrackRecordQueryProperty3<R1, R2>
    on QueryBuilder<YoutubeTrackRecord, (R1, R2), QAfterProperty> {
  QueryBuilder<YoutubeTrackRecord, (R1, R2, int), QOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, String), QOperations>
      videoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, String), QOperations>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, String), QOperations>
      artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, String?), QOperations>
      thumbnailUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, String?), QOperations>
      localPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, int), QOperations>
      downloadedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, int), QOperations>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, int?), QOperations>
      durationMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<YoutubeTrackRecord, (R1, R2, bool), QOperations>
      isDownloadedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }
}
