// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_metadata_cache_row.dart';

// **************************************************************************
// _IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, invalid_use_of_protected_member, lines_longer_than_80_chars, constant_identifier_names, avoid_js_rounded_ints, no_leading_underscores_for_local_identifiers, require_trailing_commas, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_in_if_null_operators, library_private_types_in_public_api, prefer_const_constructors
// ignore_for_file: type=lint

extension GetSongMetadataCacheRowCollection on Isar {
  IsarCollection<int, SongMetadataCacheRow> get songMetadataCacheRows =>
      this.collection();
}

const SongMetadataCacheRowSchema = IsarGeneratedSchema(
  schema: IsarSchema(
    name: 'SongMetadataCacheRow',
    idName: 'id',
    embedded: false,
    properties: [
      IsarPropertySchema(
        name: 'path',
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
        name: 'album',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'genres',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'artColorValues',
        type: IsarType.longList,
      ),
      IsarPropertySchema(
        name: 'fileSizeBytes',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'updatedAtMs',
        type: IsarType.long,
      ),
    ],
    indexes: [
      IsarIndexSchema(
        name: 'path',
        properties: [
          "path",
        ],
        unique: true,
        hash: false,
      ),
    ],
  ),
  converter: IsarObjectConverter<int, SongMetadataCacheRow>(
    serialize: serializeSongMetadataCacheRow,
    deserialize: deserializeSongMetadataCacheRow,
    deserializeProperty: deserializeSongMetadataCacheRowProp,
  ),
  embeddedSchemas: [],
);

@isarProtected
int serializeSongMetadataCacheRow(
    IsarWriter writer, SongMetadataCacheRow object) {
  IsarCore.writeString(writer, 1, object.path);
  IsarCore.writeString(writer, 2, object.title);
  IsarCore.writeString(writer, 3, object.artist);
  IsarCore.writeString(writer, 4, object.album);
  IsarCore.writeString(writer, 5, object.genres);
  {
    final list = object.artColorValues;
    final listWriter = IsarCore.beginList(writer, 6, list.length);
    for (var i = 0; i < list.length; i++) {
      IsarCore.writeLong(listWriter, i, list[i]);
    }
    IsarCore.endList(writer, listWriter);
  }
  IsarCore.writeLong(writer, 7, object.fileSizeBytes);
  IsarCore.writeLong(writer, 8, object.updatedAtMs);
  return object.id;
}

@isarProtected
SongMetadataCacheRow deserializeSongMetadataCacheRow(IsarReader reader) {
  final object = SongMetadataCacheRow();
  object.id = IsarCore.readId(reader);
  object.path = IsarCore.readString(reader, 1) ?? '';
  object.title = IsarCore.readString(reader, 2) ?? '';
  object.artist = IsarCore.readString(reader, 3) ?? '';
  object.album = IsarCore.readString(reader, 4) ?? '';
  object.genres = IsarCore.readString(reader, 5) ?? '';
  {
    final length = IsarCore.readList(reader, 6, IsarCore.readerPtrPtr);
    {
      final reader = IsarCore.readerPtr;
      if (reader.isNull) {
        object.artColorValues = const <int>[];
      } else {
        final list =
            List<int>.filled(length, -9223372036854775808, growable: true);
        for (var i = 0; i < length; i++) {
          list[i] = IsarCore.readLong(reader, i);
        }
        IsarCore.freeReader(reader);
        object.artColorValues = list;
      }
    }
  }
  object.fileSizeBytes = IsarCore.readLong(reader, 7);
  object.updatedAtMs = IsarCore.readLong(reader, 8);
  return object;
}

@isarProtected
dynamic deserializeSongMetadataCacheRowProp(IsarReader reader, int property) {
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
      return IsarCore.readString(reader, 4) ?? '';
    case 5:
      return IsarCore.readString(reader, 5) ?? '';
    case 6:
      {
        final length = IsarCore.readList(reader, 6, IsarCore.readerPtrPtr);
        {
          final reader = IsarCore.readerPtr;
          if (reader.isNull) {
            return const <int>[];
          } else {
            final list =
                List<int>.filled(length, -9223372036854775808, growable: true);
            for (var i = 0; i < length; i++) {
              list[i] = IsarCore.readLong(reader, i);
            }
            IsarCore.freeReader(reader);
            return list;
          }
        }
      }
    case 7:
      return IsarCore.readLong(reader, 7);
    case 8:
      return IsarCore.readLong(reader, 8);
    default:
      throw ArgumentError('Unknown property: $property');
  }
}

sealed class _SongMetadataCacheRowUpdate {
  bool call({
    required int id,
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genres,
    int? fileSizeBytes,
    int? updatedAtMs,
  });
}

class _SongMetadataCacheRowUpdateImpl implements _SongMetadataCacheRowUpdate {
  const _SongMetadataCacheRowUpdateImpl(this.collection);

  final IsarCollection<int, SongMetadataCacheRow> collection;

  @override
  bool call({
    required int id,
    Object? path = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? album = ignore,
    Object? genres = ignore,
    Object? fileSizeBytes = ignore,
    Object? updatedAtMs = ignore,
  }) {
    return collection.updateProperties([
          id
        ], {
          if (path != ignore) 1: path as String?,
          if (title != ignore) 2: title as String?,
          if (artist != ignore) 3: artist as String?,
          if (album != ignore) 4: album as String?,
          if (genres != ignore) 5: genres as String?,
          if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
          if (updatedAtMs != ignore) 8: updatedAtMs as int?,
        }) >
        0;
  }
}

sealed class _SongMetadataCacheRowUpdateAll {
  int call({
    required List<int> id,
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genres,
    int? fileSizeBytes,
    int? updatedAtMs,
  });
}

class _SongMetadataCacheRowUpdateAllImpl
    implements _SongMetadataCacheRowUpdateAll {
  const _SongMetadataCacheRowUpdateAllImpl(this.collection);

  final IsarCollection<int, SongMetadataCacheRow> collection;

  @override
  int call({
    required List<int> id,
    Object? path = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? album = ignore,
    Object? genres = ignore,
    Object? fileSizeBytes = ignore,
    Object? updatedAtMs = ignore,
  }) {
    return collection.updateProperties(id, {
      if (path != ignore) 1: path as String?,
      if (title != ignore) 2: title as String?,
      if (artist != ignore) 3: artist as String?,
      if (album != ignore) 4: album as String?,
      if (genres != ignore) 5: genres as String?,
      if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
      if (updatedAtMs != ignore) 8: updatedAtMs as int?,
    });
  }
}

extension SongMetadataCacheRowUpdate
    on IsarCollection<int, SongMetadataCacheRow> {
  _SongMetadataCacheRowUpdate get update =>
      _SongMetadataCacheRowUpdateImpl(this);

  _SongMetadataCacheRowUpdateAll get updateAll =>
      _SongMetadataCacheRowUpdateAllImpl(this);
}

sealed class _SongMetadataCacheRowQueryUpdate {
  int call({
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genres,
    int? fileSizeBytes,
    int? updatedAtMs,
  });
}

class _SongMetadataCacheRowQueryUpdateImpl
    implements _SongMetadataCacheRowQueryUpdate {
  const _SongMetadataCacheRowQueryUpdateImpl(this.query, {this.limit});

  final IsarQuery<SongMetadataCacheRow> query;
  final int? limit;

  @override
  int call({
    Object? path = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? album = ignore,
    Object? genres = ignore,
    Object? fileSizeBytes = ignore,
    Object? updatedAtMs = ignore,
  }) {
    return query.updateProperties(limit: limit, {
      if (path != ignore) 1: path as String?,
      if (title != ignore) 2: title as String?,
      if (artist != ignore) 3: artist as String?,
      if (album != ignore) 4: album as String?,
      if (genres != ignore) 5: genres as String?,
      if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
      if (updatedAtMs != ignore) 8: updatedAtMs as int?,
    });
  }
}

extension SongMetadataCacheRowQueryUpdate on IsarQuery<SongMetadataCacheRow> {
  _SongMetadataCacheRowQueryUpdate get updateFirst =>
      _SongMetadataCacheRowQueryUpdateImpl(this, limit: 1);

  _SongMetadataCacheRowQueryUpdate get updateAll =>
      _SongMetadataCacheRowQueryUpdateImpl(this);
}

class _SongMetadataCacheRowQueryBuilderUpdateImpl
    implements _SongMetadataCacheRowQueryUpdate {
  const _SongMetadataCacheRowQueryBuilderUpdateImpl(this.query, {this.limit});

  final QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QOperations>
      query;
  final int? limit;

  @override
  int call({
    Object? path = ignore,
    Object? title = ignore,
    Object? artist = ignore,
    Object? album = ignore,
    Object? genres = ignore,
    Object? fileSizeBytes = ignore,
    Object? updatedAtMs = ignore,
  }) {
    final q = query.build();
    try {
      return q.updateProperties(limit: limit, {
        if (path != ignore) 1: path as String?,
        if (title != ignore) 2: title as String?,
        if (artist != ignore) 3: artist as String?,
        if (album != ignore) 4: album as String?,
        if (genres != ignore) 5: genres as String?,
        if (fileSizeBytes != ignore) 7: fileSizeBytes as int?,
        if (updatedAtMs != ignore) 8: updatedAtMs as int?,
      });
    } finally {
      q.close();
    }
  }
}

extension SongMetadataCacheRowQueryBuilderUpdate
    on QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QOperations> {
  _SongMetadataCacheRowQueryUpdate get updateFirst =>
      _SongMetadataCacheRowQueryBuilderUpdateImpl(this, limit: 1);

  _SongMetadataCacheRowQueryUpdate get updateAll =>
      _SongMetadataCacheRowQueryBuilderUpdateImpl(this);
}

extension SongMetadataCacheRowQueryFilter on QueryBuilder<SongMetadataCacheRow,
    SongMetadataCacheRow, QFilterCondition> {
  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> idBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathStartsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathEndsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      pathContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      pathMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> pathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleStartsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleEndsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistStartsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistEndsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artistIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumGreaterThan(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumGreaterThanOrEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumLessThan(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumLessThanOrEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumBetween(
    String lower,
    String upper, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumStartsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumEndsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      albumContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      albumMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> albumIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresGreaterThan(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresGreaterThanOrEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresLessThan(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresLessThanOrEqualTo(
    String value, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresBetween(
    String lower,
    String upper, {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresStartsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresEndsWith(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      genresContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
          QAfterFilterCondition>
      genresMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> genresIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesElementBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesIsEmpty() {
    return not().artColorValuesIsNotEmpty();
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> artColorValuesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterOrEqualCondition(property: 6, value: null),
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesGreaterThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesGreaterThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesLessThan(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesLessThanOrEqualTo(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> fileSizeBytesBetween(
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsEqualTo(
    int value,
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsGreaterThan(
    int value,
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsGreaterThanOrEqualTo(
    int value,
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsLessThan(
    int value,
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsLessThanOrEqualTo(
    int value,
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

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow,
      QAfterFilterCondition> updatedAtMsBetween(
    int lower,
    int upper,
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
}

extension SongMetadataCacheRowQueryObject on QueryBuilder<SongMetadataCacheRow,
    SongMetadataCacheRow, QFilterCondition> {}

extension SongMetadataCacheRowQuerySortBy
    on QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QSortBy> {
  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByPathDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByTitleDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByArtistDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByAlbum({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByAlbumDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByGenres({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByGenresDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByFileSizeBytesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByUpdatedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      sortByUpdatedAtMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }
}

extension SongMetadataCacheRowQuerySortThenBy
    on QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QSortThenBy> {
  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByPathDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByTitleDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByArtistDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByAlbum({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByAlbumDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByGenres({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByGenresDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByFileSizeBytesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByUpdatedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterSortBy>
      thenByUpdatedAtMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }
}

extension SongMetadataCacheRowQueryWhereDistinct
    on QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QDistinct> {
  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByArtist({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByAlbum({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByGenres({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByArtColorValues() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(6);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByFileSizeBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QAfterDistinct>
      distinctByUpdatedAtMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(8);
    });
  }
}

extension SongMetadataCacheRowQueryProperty1
    on QueryBuilder<SongMetadataCacheRow, SongMetadataCacheRow, QProperty> {
  QueryBuilder<SongMetadataCacheRow, int, QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SongMetadataCacheRow, String, QAfterProperty> pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SongMetadataCacheRow, String, QAfterProperty> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SongMetadataCacheRow, String, QAfterProperty> artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<SongMetadataCacheRow, String, QAfterProperty> albumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<SongMetadataCacheRow, String, QAfterProperty> genresProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<SongMetadataCacheRow, List<int>, QAfterProperty>
      artColorValuesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<SongMetadataCacheRow, int, QAfterProperty>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, int, QAfterProperty>
      updatedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }
}

extension SongMetadataCacheRowQueryProperty2<R>
    on QueryBuilder<SongMetadataCacheRow, R, QAfterProperty> {
  QueryBuilder<SongMetadataCacheRow, (R, int), QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, String), QAfterProperty>
      pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, String), QAfterProperty>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, String), QAfterProperty>
      artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, String), QAfterProperty>
      albumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, String), QAfterProperty>
      genresProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, List<int>), QAfterProperty>
      artColorValuesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, int), QAfterProperty>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R, int), QAfterProperty>
      updatedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }
}

extension SongMetadataCacheRowQueryProperty3<R1, R2>
    on QueryBuilder<SongMetadataCacheRow, (R1, R2), QAfterProperty> {
  QueryBuilder<SongMetadataCacheRow, (R1, R2, int), QOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, String), QOperations>
      pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, String), QOperations>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, String), QOperations>
      artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, String), QOperations>
      albumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, String), QOperations>
      genresProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, List<int>), QOperations>
      artColorValuesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, int), QOperations>
      fileSizeBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<SongMetadataCacheRow, (R1, R2, int), QOperations>
      updatedAtMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }
}
