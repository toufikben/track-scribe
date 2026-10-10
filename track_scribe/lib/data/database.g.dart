// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, Activity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sportMeta = const VerificationMeta('sport');
  @override
  late final GeneratedColumn<String> sport = GeneratedColumn<String>(
    'sport',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startWallMillisMeta = const VerificationMeta(
    'startWallMillis',
  );
  @override
  late final GeneratedColumn<int> startWallMillis = GeneratedColumn<int>(
    'start_wall_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elapsedNanosMeta = const VerificationMeta(
    'elapsedNanos',
  );
  @override
  late final GeneratedColumn<int> elapsedNanos = GeneratedColumn<int>(
    'elapsed_nanos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _climbMMeta = const VerificationMeta('climbM');
  @override
  late final GeneratedColumn<double> climbM = GeneratedColumn<double>(
    'climb_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fixCountMeta = const VerificationMeta(
    'fixCount',
  );
  @override
  late final GeneratedColumn<int> fixCount = GeneratedColumn<int>(
    'fix_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rejectedCountMeta = const VerificationMeta(
    'rejectedCount',
  );
  @override
  late final GeneratedColumn<int> rejectedCount = GeneratedColumn<int>(
    'rejected_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mockDetectedMeta = const VerificationMeta(
    'mockDetected',
  );
  @override
  late final GeneratedColumn<bool> mockDetected = GeneratedColumn<bool>(
    'mock_detected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mock_detected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverUuidMeta = const VerificationMeta(
    'serverUuid',
  );
  @override
  late final GeneratedColumn<String> serverUuid = GeneratedColumn<String>(
    'server_uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    sport,
    startWallMillis,
    elapsedNanos,
    distanceM,
    climbM,
    fixCount,
    rejectedCount,
    mockDetected,
    serverUuid,
    updatedAt,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Activity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('sport')) {
      context.handle(
        _sportMeta,
        sport.isAcceptableOrUnknown(data['sport']!, _sportMeta),
      );
    } else if (isInserting) {
      context.missing(_sportMeta);
    }
    if (data.containsKey('start_wall_millis')) {
      context.handle(
        _startWallMillisMeta,
        startWallMillis.isAcceptableOrUnknown(
          data['start_wall_millis']!,
          _startWallMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startWallMillisMeta);
    }
    if (data.containsKey('elapsed_nanos')) {
      context.handle(
        _elapsedNanosMeta,
        elapsedNanos.isAcceptableOrUnknown(
          data['elapsed_nanos']!,
          _elapsedNanosMeta,
        ),
      );
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    }
    if (data.containsKey('climb_m')) {
      context.handle(
        _climbMMeta,
        climbM.isAcceptableOrUnknown(data['climb_m']!, _climbMMeta),
      );
    }
    if (data.containsKey('fix_count')) {
      context.handle(
        _fixCountMeta,
        fixCount.isAcceptableOrUnknown(data['fix_count']!, _fixCountMeta),
      );
    }
    if (data.containsKey('rejected_count')) {
      context.handle(
        _rejectedCountMeta,
        rejectedCount.isAcceptableOrUnknown(
          data['rejected_count']!,
          _rejectedCountMeta,
        ),
      );
    }
    if (data.containsKey('mock_detected')) {
      context.handle(
        _mockDetectedMeta,
        mockDetected.isAcceptableOrUnknown(
          data['mock_detected']!,
          _mockDetectedMeta,
        ),
      );
    }
    if (data.containsKey('server_uuid')) {
      context.handle(
        _serverUuidMeta,
        serverUuid.isAcceptableOrUnknown(data['server_uuid']!, _serverUuidMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Activity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Activity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      sport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sport'],
      )!,
      startWallMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_wall_millis'],
      )!,
      elapsedNanos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_nanos'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
      climbM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}climb_m'],
      )!,
      fixCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fix_count'],
      )!,
      rejectedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_count'],
      )!,
      mockDetected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mock_detected'],
      )!,
      serverUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_uuid'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }
}

class Activity extends DataClass implements Insertable<Activity> {
  final int id;
  final String uuid;
  final String sport;
  final int startWallMillis;
  final int elapsedNanos;
  final double distanceM;
  final double climbM;
  final int fixCount;
  final int rejectedCount;
  final bool mockDetected;
  final String? serverUuid;
  final int? updatedAt;
  final bool isDeleted;
  const Activity({
    required this.id,
    required this.uuid,
    required this.sport,
    required this.startWallMillis,
    required this.elapsedNanos,
    required this.distanceM,
    required this.climbM,
    required this.fixCount,
    required this.rejectedCount,
    required this.mockDetected,
    this.serverUuid,
    this.updatedAt,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['sport'] = Variable<String>(sport);
    map['start_wall_millis'] = Variable<int>(startWallMillis);
    map['elapsed_nanos'] = Variable<int>(elapsedNanos);
    map['distance_m'] = Variable<double>(distanceM);
    map['climb_m'] = Variable<double>(climbM);
    map['fix_count'] = Variable<int>(fixCount);
    map['rejected_count'] = Variable<int>(rejectedCount);
    map['mock_detected'] = Variable<bool>(mockDetected);
    if (!nullToAbsent || serverUuid != null) {
      map['server_uuid'] = Variable<String>(serverUuid);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  ActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivitiesCompanion(
      id: Value(id),
      uuid: Value(uuid),
      sport: Value(sport),
      startWallMillis: Value(startWallMillis),
      elapsedNanos: Value(elapsedNanos),
      distanceM: Value(distanceM),
      climbM: Value(climbM),
      fixCount: Value(fixCount),
      rejectedCount: Value(rejectedCount),
      mockDetected: Value(mockDetected),
      serverUuid: serverUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUuid),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      isDeleted: Value(isDeleted),
    );
  }

  factory Activity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Activity(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      sport: serializer.fromJson<String>(json['sport']),
      startWallMillis: serializer.fromJson<int>(json['startWallMillis']),
      elapsedNanos: serializer.fromJson<int>(json['elapsedNanos']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
      climbM: serializer.fromJson<double>(json['climbM']),
      fixCount: serializer.fromJson<int>(json['fixCount']),
      rejectedCount: serializer.fromJson<int>(json['rejectedCount']),
      mockDetected: serializer.fromJson<bool>(json['mockDetected']),
      serverUuid: serializer.fromJson<String?>(json['serverUuid']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'sport': serializer.toJson<String>(sport),
      'startWallMillis': serializer.toJson<int>(startWallMillis),
      'elapsedNanos': serializer.toJson<int>(elapsedNanos),
      'distanceM': serializer.toJson<double>(distanceM),
      'climbM': serializer.toJson<double>(climbM),
      'fixCount': serializer.toJson<int>(fixCount),
      'rejectedCount': serializer.toJson<int>(rejectedCount),
      'mockDetected': serializer.toJson<bool>(mockDetected),
      'serverUuid': serializer.toJson<String?>(serverUuid),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Activity copyWith({
    int? id,
    String? uuid,
    String? sport,
    int? startWallMillis,
    int? elapsedNanos,
    double? distanceM,
    double? climbM,
    int? fixCount,
    int? rejectedCount,
    bool? mockDetected,
    Value<String?> serverUuid = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
    bool? isDeleted,
  }) => Activity(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    sport: sport ?? this.sport,
    startWallMillis: startWallMillis ?? this.startWallMillis,
    elapsedNanos: elapsedNanos ?? this.elapsedNanos,
    distanceM: distanceM ?? this.distanceM,
    climbM: climbM ?? this.climbM,
    fixCount: fixCount ?? this.fixCount,
    rejectedCount: rejectedCount ?? this.rejectedCount,
    mockDetected: mockDetected ?? this.mockDetected,
    serverUuid: serverUuid.present ? serverUuid.value : this.serverUuid,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Activity copyWithCompanion(ActivitiesCompanion data) {
    return Activity(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      sport: data.sport.present ? data.sport.value : this.sport,
      startWallMillis: data.startWallMillis.present
          ? data.startWallMillis.value
          : this.startWallMillis,
      elapsedNanos: data.elapsedNanos.present
          ? data.elapsedNanos.value
          : this.elapsedNanos,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      climbM: data.climbM.present ? data.climbM.value : this.climbM,
      fixCount: data.fixCount.present ? data.fixCount.value : this.fixCount,
      rejectedCount: data.rejectedCount.present
          ? data.rejectedCount.value
          : this.rejectedCount,
      mockDetected: data.mockDetected.present
          ? data.mockDetected.value
          : this.mockDetected,
      serverUuid: data.serverUuid.present
          ? data.serverUuid.value
          : this.serverUuid,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Activity(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('sport: $sport, ')
          ..write('startWallMillis: $startWallMillis, ')
          ..write('elapsedNanos: $elapsedNanos, ')
          ..write('distanceM: $distanceM, ')
          ..write('climbM: $climbM, ')
          ..write('fixCount: $fixCount, ')
          ..write('rejectedCount: $rejectedCount, ')
          ..write('mockDetected: $mockDetected, ')
          ..write('serverUuid: $serverUuid, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    sport,
    startWallMillis,
    elapsedNanos,
    distanceM,
    climbM,
    fixCount,
    rejectedCount,
    mockDetected,
    serverUuid,
    updatedAt,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Activity &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.sport == this.sport &&
          other.startWallMillis == this.startWallMillis &&
          other.elapsedNanos == this.elapsedNanos &&
          other.distanceM == this.distanceM &&
          other.climbM == this.climbM &&
          other.fixCount == this.fixCount &&
          other.rejectedCount == this.rejectedCount &&
          other.mockDetected == this.mockDetected &&
          other.serverUuid == this.serverUuid &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted);
}

class ActivitiesCompanion extends UpdateCompanion<Activity> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> sport;
  final Value<int> startWallMillis;
  final Value<int> elapsedNanos;
  final Value<double> distanceM;
  final Value<double> climbM;
  final Value<int> fixCount;
  final Value<int> rejectedCount;
  final Value<bool> mockDetected;
  final Value<String?> serverUuid;
  final Value<int?> updatedAt;
  final Value<bool> isDeleted;
  const ActivitiesCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.sport = const Value.absent(),
    this.startWallMillis = const Value.absent(),
    this.elapsedNanos = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.climbM = const Value.absent(),
    this.fixCount = const Value.absent(),
    this.rejectedCount = const Value.absent(),
    this.mockDetected = const Value.absent(),
    this.serverUuid = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String sport,
    required int startWallMillis,
    this.elapsedNanos = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.climbM = const Value.absent(),
    this.fixCount = const Value.absent(),
    this.rejectedCount = const Value.absent(),
    this.mockDetected = const Value.absent(),
    this.serverUuid = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
  }) : uuid = Value(uuid),
       sport = Value(sport),
       startWallMillis = Value(startWallMillis);
  static Insertable<Activity> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? sport,
    Expression<int>? startWallMillis,
    Expression<int>? elapsedNanos,
    Expression<double>? distanceM,
    Expression<double>? climbM,
    Expression<int>? fixCount,
    Expression<int>? rejectedCount,
    Expression<bool>? mockDetected,
    Expression<String>? serverUuid,
    Expression<int>? updatedAt,
    Expression<bool>? isDeleted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (sport != null) 'sport': sport,
      if (startWallMillis != null) 'start_wall_millis': startWallMillis,
      if (elapsedNanos != null) 'elapsed_nanos': elapsedNanos,
      if (distanceM != null) 'distance_m': distanceM,
      if (climbM != null) 'climb_m': climbM,
      if (fixCount != null) 'fix_count': fixCount,
      if (rejectedCount != null) 'rejected_count': rejectedCount,
      if (mockDetected != null) 'mock_detected': mockDetected,
      if (serverUuid != null) 'server_uuid': serverUuid,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
    });
  }

  ActivitiesCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? sport,
    Value<int>? startWallMillis,
    Value<int>? elapsedNanos,
    Value<double>? distanceM,
    Value<double>? climbM,
    Value<int>? fixCount,
    Value<int>? rejectedCount,
    Value<bool>? mockDetected,
    Value<String?>? serverUuid,
    Value<int?>? updatedAt,
    Value<bool>? isDeleted,
  }) {
    return ActivitiesCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      sport: sport ?? this.sport,
      startWallMillis: startWallMillis ?? this.startWallMillis,
      elapsedNanos: elapsedNanos ?? this.elapsedNanos,
      distanceM: distanceM ?? this.distanceM,
      climbM: climbM ?? this.climbM,
      fixCount: fixCount ?? this.fixCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      mockDetected: mockDetected ?? this.mockDetected,
      serverUuid: serverUuid ?? this.serverUuid,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (sport.present) {
      map['sport'] = Variable<String>(sport.value);
    }
    if (startWallMillis.present) {
      map['start_wall_millis'] = Variable<int>(startWallMillis.value);
    }
    if (elapsedNanos.present) {
      map['elapsed_nanos'] = Variable<int>(elapsedNanos.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (climbM.present) {
      map['climb_m'] = Variable<double>(climbM.value);
    }
    if (fixCount.present) {
      map['fix_count'] = Variable<int>(fixCount.value);
    }
    if (rejectedCount.present) {
      map['rejected_count'] = Variable<int>(rejectedCount.value);
    }
    if (mockDetected.present) {
      map['mock_detected'] = Variable<bool>(mockDetected.value);
    }
    if (serverUuid.present) {
      map['server_uuid'] = Variable<String>(serverUuid.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('sport: $sport, ')
          ..write('startWallMillis: $startWallMillis, ')
          ..write('elapsedNanos: $elapsedNanos, ')
          ..write('distanceM: $distanceM, ')
          ..write('climbM: $climbM, ')
          ..write('fixCount: $fixCount, ')
          ..write('rejectedCount: $rejectedCount, ')
          ..write('mockDetected: $mockDetected, ')
          ..write('serverUuid: $serverUuid, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }
}

class $TrackPointsTable extends TrackPoints
    with TableInfo<$TrackPointsTable, TrackPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<int> activityId = GeneratedColumn<int>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id)',
    ),
  );
  static const VerificationMeta _timeNanosMeta = const VerificationMeta(
    'timeNanos',
  );
  @override
  late final GeneratedColumn<int> timeNanos = GeneratedColumn<int>(
    'time_nanos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altGnssMeta = const VerificationMeta(
    'altGnss',
  );
  @override
  late final GeneratedColumn<double> altGnss = GeneratedColumn<double>(
    'alt_gnss',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bearingDegMeta = const VerificationMeta(
    'bearingDeg',
  );
  @override
  late final GeneratedColumn<double> bearingDeg = GeneratedColumn<double>(
    'bearing_deg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waypointTypeMeta = const VerificationMeta(
    'waypointType',
  );
  @override
  late final GeneratedColumn<String> waypointType = GeneratedColumn<String>(
    'waypoint_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    activityId,
    timeNanos,
    lat,
    lon,
    altGnss,
    accuracyM,
    speedMps,
    bearingDeg,
    waypointType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('time_nanos')) {
      context.handle(
        _timeNanosMeta,
        timeNanos.isAcceptableOrUnknown(data['time_nanos']!, _timeNanosMeta),
      );
    } else if (isInserting) {
      context.missing(_timeNanosMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('alt_gnss')) {
      context.handle(
        _altGnssMeta,
        altGnss.isAcceptableOrUnknown(data['alt_gnss']!, _altGnssMeta),
      );
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMMeta);
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    if (data.containsKey('bearing_deg')) {
      context.handle(
        _bearingDegMeta,
        bearingDeg.isAcceptableOrUnknown(data['bearing_deg']!, _bearingDegMeta),
      );
    }
    if (data.containsKey('waypoint_type')) {
      context.handle(
        _waypointTypeMeta,
        waypointType.isAcceptableOrUnknown(
          data['waypoint_type']!,
          _waypointTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_waypointTypeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activity_id'],
      )!,
      timeNanos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_nanos'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      altGnss: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}alt_gnss'],
      ),
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      )!,
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
      bearingDeg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bearing_deg'],
      ),
      waypointType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_type'],
      )!,
    );
  }

  @override
  $TrackPointsTable createAlias(String alias) {
    return $TrackPointsTable(attachedDatabase, alias);
  }
}

class TrackPoint extends DataClass implements Insertable<TrackPoint> {
  final int id;
  final int activityId;
  final int timeNanos;
  final double lat;
  final double lon;
  final double? altGnss;
  final double accuracyM;
  final double? speedMps;
  final double? bearingDeg;
  final String waypointType;
  const TrackPoint({
    required this.id,
    required this.activityId,
    required this.timeNanos,
    required this.lat,
    required this.lon,
    this.altGnss,
    required this.accuracyM,
    this.speedMps,
    this.bearingDeg,
    required this.waypointType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['activity_id'] = Variable<int>(activityId);
    map['time_nanos'] = Variable<int>(timeNanos);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || altGnss != null) {
      map['alt_gnss'] = Variable<double>(altGnss);
    }
    map['accuracy_m'] = Variable<double>(accuracyM);
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    if (!nullToAbsent || bearingDeg != null) {
      map['bearing_deg'] = Variable<double>(bearingDeg);
    }
    map['waypoint_type'] = Variable<String>(waypointType);
    return map;
  }

  TrackPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackPointsCompanion(
      id: Value(id),
      activityId: Value(activityId),
      timeNanos: Value(timeNanos),
      lat: Value(lat),
      lon: Value(lon),
      altGnss: altGnss == null && nullToAbsent
          ? const Value.absent()
          : Value(altGnss),
      accuracyM: Value(accuracyM),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      bearingDeg: bearingDeg == null && nullToAbsent
          ? const Value.absent()
          : Value(bearingDeg),
      waypointType: Value(waypointType),
    );
  }

  factory TrackPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackPoint(
      id: serializer.fromJson<int>(json['id']),
      activityId: serializer.fromJson<int>(json['activityId']),
      timeNanos: serializer.fromJson<int>(json['timeNanos']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      altGnss: serializer.fromJson<double?>(json['altGnss']),
      accuracyM: serializer.fromJson<double>(json['accuracyM']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
      bearingDeg: serializer.fromJson<double?>(json['bearingDeg']),
      waypointType: serializer.fromJson<String>(json['waypointType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'activityId': serializer.toJson<int>(activityId),
      'timeNanos': serializer.toJson<int>(timeNanos),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'altGnss': serializer.toJson<double?>(altGnss),
      'accuracyM': serializer.toJson<double>(accuracyM),
      'speedMps': serializer.toJson<double?>(speedMps),
      'bearingDeg': serializer.toJson<double?>(bearingDeg),
      'waypointType': serializer.toJson<String>(waypointType),
    };
  }

  TrackPoint copyWith({
    int? id,
    int? activityId,
    int? timeNanos,
    double? lat,
    double? lon,
    Value<double?> altGnss = const Value.absent(),
    double? accuracyM,
    Value<double?> speedMps = const Value.absent(),
    Value<double?> bearingDeg = const Value.absent(),
    String? waypointType,
  }) => TrackPoint(
    id: id ?? this.id,
    activityId: activityId ?? this.activityId,
    timeNanos: timeNanos ?? this.timeNanos,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    altGnss: altGnss.present ? altGnss.value : this.altGnss,
    accuracyM: accuracyM ?? this.accuracyM,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
    bearingDeg: bearingDeg.present ? bearingDeg.value : this.bearingDeg,
    waypointType: waypointType ?? this.waypointType,
  );
  TrackPoint copyWithCompanion(TrackPointsCompanion data) {
    return TrackPoint(
      id: data.id.present ? data.id.value : this.id,
      activityId: data.activityId.present
          ? data.activityId.value
          : this.activityId,
      timeNanos: data.timeNanos.present ? data.timeNanos.value : this.timeNanos,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      altGnss: data.altGnss.present ? data.altGnss.value : this.altGnss,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      bearingDeg: data.bearingDeg.present
          ? data.bearingDeg.value
          : this.bearingDeg,
      waypointType: data.waypointType.present
          ? data.waypointType.value
          : this.waypointType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackPoint(')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('timeNanos: $timeNanos, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('altGnss: $altGnss, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('bearingDeg: $bearingDeg, ')
          ..write('waypointType: $waypointType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    activityId,
    timeNanos,
    lat,
    lon,
    altGnss,
    accuracyM,
    speedMps,
    bearingDeg,
    waypointType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackPoint &&
          other.id == this.id &&
          other.activityId == this.activityId &&
          other.timeNanos == this.timeNanos &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.altGnss == this.altGnss &&
          other.accuracyM == this.accuracyM &&
          other.speedMps == this.speedMps &&
          other.bearingDeg == this.bearingDeg &&
          other.waypointType == this.waypointType);
}

class TrackPointsCompanion extends UpdateCompanion<TrackPoint> {
  final Value<int> id;
  final Value<int> activityId;
  final Value<int> timeNanos;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double?> altGnss;
  final Value<double> accuracyM;
  final Value<double?> speedMps;
  final Value<double?> bearingDeg;
  final Value<String> waypointType;
  const TrackPointsCompanion({
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.timeNanos = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.altGnss = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.bearingDeg = const Value.absent(),
    this.waypointType = const Value.absent(),
  });
  TrackPointsCompanion.insert({
    this.id = const Value.absent(),
    required int activityId,
    required int timeNanos,
    required double lat,
    required double lon,
    this.altGnss = const Value.absent(),
    required double accuracyM,
    this.speedMps = const Value.absent(),
    this.bearingDeg = const Value.absent(),
    required String waypointType,
  }) : activityId = Value(activityId),
       timeNanos = Value(timeNanos),
       lat = Value(lat),
       lon = Value(lon),
       accuracyM = Value(accuracyM),
       waypointType = Value(waypointType);
  static Insertable<TrackPoint> custom({
    Expression<int>? id,
    Expression<int>? activityId,
    Expression<int>? timeNanos,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? altGnss,
    Expression<double>? accuracyM,
    Expression<double>? speedMps,
    Expression<double>? bearingDeg,
    Expression<String>? waypointType,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (timeNanos != null) 'time_nanos': timeNanos,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (altGnss != null) 'alt_gnss': altGnss,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (speedMps != null) 'speed_mps': speedMps,
      if (bearingDeg != null) 'bearing_deg': bearingDeg,
      if (waypointType != null) 'waypoint_type': waypointType,
    });
  }

  TrackPointsCompanion copyWith({
    Value<int>? id,
    Value<int>? activityId,
    Value<int>? timeNanos,
    Value<double>? lat,
    Value<double>? lon,
    Value<double?>? altGnss,
    Value<double>? accuracyM,
    Value<double?>? speedMps,
    Value<double?>? bearingDeg,
    Value<String>? waypointType,
  }) {
    return TrackPointsCompanion(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      timeNanos: timeNanos ?? this.timeNanos,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      altGnss: altGnss ?? this.altGnss,
      accuracyM: accuracyM ?? this.accuracyM,
      speedMps: speedMps ?? this.speedMps,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      waypointType: waypointType ?? this.waypointType,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<int>(activityId.value);
    }
    if (timeNanos.present) {
      map['time_nanos'] = Variable<int>(timeNanos.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (altGnss.present) {
      map['alt_gnss'] = Variable<double>(altGnss.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (bearingDeg.present) {
      map['bearing_deg'] = Variable<double>(bearingDeg.value);
    }
    if (waypointType.present) {
      map['waypoint_type'] = Variable<String>(waypointType.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointsCompanion(')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('timeNanos: $timeNanos, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('altGnss: $altGnss, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('bearingDeg: $bearingDeg, ')
          ..write('waypointType: $waypointType')
          ..write(')'))
        .toString();
  }
}

class $TrackStateTable extends TrackState
    with TableInfo<$TrackStateTable, TrackStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<int> activityId = GeneratedColumn<int>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastTimeNanosMeta = const VerificationMeta(
    'lastTimeNanos',
  );
  @override
  late final GeneratedColumn<int> lastTimeNanos = GeneratedColumn<int>(
    'last_time_nanos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastLatMeta = const VerificationMeta(
    'lastLat',
  );
  @override
  late final GeneratedColumn<double> lastLat = GeneratedColumn<double>(
    'last_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastLonMeta = const VerificationMeta(
    'lastLon',
  );
  @override
  late final GeneratedColumn<double> lastLon = GeneratedColumn<double>(
    'last_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccuracyMMeta = const VerificationMeta(
    'lastAccuracyM',
  );
  @override
  late final GeneratedColumn<double> lastAccuracyM = GeneratedColumn<double>(
    'last_accuracy_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastTypeMeta = const VerificationMeta(
    'lastType',
  );
  @override
  late final GeneratedColumn<String> lastType = GeneratedColumn<String>(
    'last_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    activityId,
    lastTimeNanos,
    lastLat,
    lastLon,
    lastAccuracyM,
    lastType,
    distanceM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('last_time_nanos')) {
      context.handle(
        _lastTimeNanosMeta,
        lastTimeNanos.isAcceptableOrUnknown(
          data['last_time_nanos']!,
          _lastTimeNanosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastTimeNanosMeta);
    }
    if (data.containsKey('last_lat')) {
      context.handle(
        _lastLatMeta,
        lastLat.isAcceptableOrUnknown(data['last_lat']!, _lastLatMeta),
      );
    } else if (isInserting) {
      context.missing(_lastLatMeta);
    }
    if (data.containsKey('last_lon')) {
      context.handle(
        _lastLonMeta,
        lastLon.isAcceptableOrUnknown(data['last_lon']!, _lastLonMeta),
      );
    } else if (isInserting) {
      context.missing(_lastLonMeta);
    }
    if (data.containsKey('last_accuracy_m')) {
      context.handle(
        _lastAccuracyMMeta,
        lastAccuracyM.isAcceptableOrUnknown(
          data['last_accuracy_m']!,
          _lastAccuracyMMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccuracyMMeta);
    }
    if (data.containsKey('last_type')) {
      context.handle(
        _lastTypeMeta,
        lastType.isAcceptableOrUnknown(data['last_type']!, _lastTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_lastTypeMeta);
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    } else if (isInserting) {
      context.missing(_distanceMMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  TrackStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activity_id'],
      )!,
      lastTimeNanos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_time_nanos'],
      )!,
      lastLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}last_lat'],
      )!,
      lastLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}last_lon'],
      )!,
      lastAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}last_accuracy_m'],
      )!,
      lastType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_type'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
    );
  }

  @override
  $TrackStateTable createAlias(String alias) {
    return $TrackStateTable(attachedDatabase, alias);
  }
}

class TrackStateData extends DataClass implements Insertable<TrackStateData> {
  final String key;
  final int activityId;
  final int lastTimeNanos;
  final double lastLat;
  final double lastLon;
  final double lastAccuracyM;
  final String lastType;
  final double distanceM;
  const TrackStateData({
    required this.key,
    required this.activityId,
    required this.lastTimeNanos,
    required this.lastLat,
    required this.lastLon,
    required this.lastAccuracyM,
    required this.lastType,
    required this.distanceM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['activity_id'] = Variable<int>(activityId);
    map['last_time_nanos'] = Variable<int>(lastTimeNanos);
    map['last_lat'] = Variable<double>(lastLat);
    map['last_lon'] = Variable<double>(lastLon);
    map['last_accuracy_m'] = Variable<double>(lastAccuracyM);
    map['last_type'] = Variable<String>(lastType);
    map['distance_m'] = Variable<double>(distanceM);
    return map;
  }

  TrackStateCompanion toCompanion(bool nullToAbsent) {
    return TrackStateCompanion(
      key: Value(key),
      activityId: Value(activityId),
      lastTimeNanos: Value(lastTimeNanos),
      lastLat: Value(lastLat),
      lastLon: Value(lastLon),
      lastAccuracyM: Value(lastAccuracyM),
      lastType: Value(lastType),
      distanceM: Value(distanceM),
    );
  }

  factory TrackStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackStateData(
      key: serializer.fromJson<String>(json['key']),
      activityId: serializer.fromJson<int>(json['activityId']),
      lastTimeNanos: serializer.fromJson<int>(json['lastTimeNanos']),
      lastLat: serializer.fromJson<double>(json['lastLat']),
      lastLon: serializer.fromJson<double>(json['lastLon']),
      lastAccuracyM: serializer.fromJson<double>(json['lastAccuracyM']),
      lastType: serializer.fromJson<String>(json['lastType']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'activityId': serializer.toJson<int>(activityId),
      'lastTimeNanos': serializer.toJson<int>(lastTimeNanos),
      'lastLat': serializer.toJson<double>(lastLat),
      'lastLon': serializer.toJson<double>(lastLon),
      'lastAccuracyM': serializer.toJson<double>(lastAccuracyM),
      'lastType': serializer.toJson<String>(lastType),
      'distanceM': serializer.toJson<double>(distanceM),
    };
  }

  TrackStateData copyWith({
    String? key,
    int? activityId,
    int? lastTimeNanos,
    double? lastLat,
    double? lastLon,
    double? lastAccuracyM,
    String? lastType,
    double? distanceM,
  }) => TrackStateData(
    key: key ?? this.key,
    activityId: activityId ?? this.activityId,
    lastTimeNanos: lastTimeNanos ?? this.lastTimeNanos,
    lastLat: lastLat ?? this.lastLat,
    lastLon: lastLon ?? this.lastLon,
    lastAccuracyM: lastAccuracyM ?? this.lastAccuracyM,
    lastType: lastType ?? this.lastType,
    distanceM: distanceM ?? this.distanceM,
  );
  TrackStateData copyWithCompanion(TrackStateCompanion data) {
    return TrackStateData(
      key: data.key.present ? data.key.value : this.key,
      activityId: data.activityId.present
          ? data.activityId.value
          : this.activityId,
      lastTimeNanos: data.lastTimeNanos.present
          ? data.lastTimeNanos.value
          : this.lastTimeNanos,
      lastLat: data.lastLat.present ? data.lastLat.value : this.lastLat,
      lastLon: data.lastLon.present ? data.lastLon.value : this.lastLon,
      lastAccuracyM: data.lastAccuracyM.present
          ? data.lastAccuracyM.value
          : this.lastAccuracyM,
      lastType: data.lastType.present ? data.lastType.value : this.lastType,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackStateData(')
          ..write('key: $key, ')
          ..write('activityId: $activityId, ')
          ..write('lastTimeNanos: $lastTimeNanos, ')
          ..write('lastLat: $lastLat, ')
          ..write('lastLon: $lastLon, ')
          ..write('lastAccuracyM: $lastAccuracyM, ')
          ..write('lastType: $lastType, ')
          ..write('distanceM: $distanceM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    activityId,
    lastTimeNanos,
    lastLat,
    lastLon,
    lastAccuracyM,
    lastType,
    distanceM,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackStateData &&
          other.key == this.key &&
          other.activityId == this.activityId &&
          other.lastTimeNanos == this.lastTimeNanos &&
          other.lastLat == this.lastLat &&
          other.lastLon == this.lastLon &&
          other.lastAccuracyM == this.lastAccuracyM &&
          other.lastType == this.lastType &&
          other.distanceM == this.distanceM);
}

class TrackStateCompanion extends UpdateCompanion<TrackStateData> {
  final Value<String> key;
  final Value<int> activityId;
  final Value<int> lastTimeNanos;
  final Value<double> lastLat;
  final Value<double> lastLon;
  final Value<double> lastAccuracyM;
  final Value<String> lastType;
  final Value<double> distanceM;
  final Value<int> rowid;
  const TrackStateCompanion({
    this.key = const Value.absent(),
    this.activityId = const Value.absent(),
    this.lastTimeNanos = const Value.absent(),
    this.lastLat = const Value.absent(),
    this.lastLon = const Value.absent(),
    this.lastAccuracyM = const Value.absent(),
    this.lastType = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrackStateCompanion.insert({
    required String key,
    required int activityId,
    required int lastTimeNanos,
    required double lastLat,
    required double lastLon,
    required double lastAccuracyM,
    required String lastType,
    required double distanceM,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       activityId = Value(activityId),
       lastTimeNanos = Value(lastTimeNanos),
       lastLat = Value(lastLat),
       lastLon = Value(lastLon),
       lastAccuracyM = Value(lastAccuracyM),
       lastType = Value(lastType),
       distanceM = Value(distanceM);
  static Insertable<TrackStateData> custom({
    Expression<String>? key,
    Expression<int>? activityId,
    Expression<int>? lastTimeNanos,
    Expression<double>? lastLat,
    Expression<double>? lastLon,
    Expression<double>? lastAccuracyM,
    Expression<String>? lastType,
    Expression<double>? distanceM,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (activityId != null) 'activity_id': activityId,
      if (lastTimeNanos != null) 'last_time_nanos': lastTimeNanos,
      if (lastLat != null) 'last_lat': lastLat,
      if (lastLon != null) 'last_lon': lastLon,
      if (lastAccuracyM != null) 'last_accuracy_m': lastAccuracyM,
      if (lastType != null) 'last_type': lastType,
      if (distanceM != null) 'distance_m': distanceM,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrackStateCompanion copyWith({
    Value<String>? key,
    Value<int>? activityId,
    Value<int>? lastTimeNanos,
    Value<double>? lastLat,
    Value<double>? lastLon,
    Value<double>? lastAccuracyM,
    Value<String>? lastType,
    Value<double>? distanceM,
    Value<int>? rowid,
  }) {
    return TrackStateCompanion(
      key: key ?? this.key,
      activityId: activityId ?? this.activityId,
      lastTimeNanos: lastTimeNanos ?? this.lastTimeNanos,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
      lastAccuracyM: lastAccuracyM ?? this.lastAccuracyM,
      lastType: lastType ?? this.lastType,
      distanceM: distanceM ?? this.distanceM,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<int>(activityId.value);
    }
    if (lastTimeNanos.present) {
      map['last_time_nanos'] = Variable<int>(lastTimeNanos.value);
    }
    if (lastLat.present) {
      map['last_lat'] = Variable<double>(lastLat.value);
    }
    if (lastLon.present) {
      map['last_lon'] = Variable<double>(lastLon.value);
    }
    if (lastAccuracyM.present) {
      map['last_accuracy_m'] = Variable<double>(lastAccuracyM.value);
    }
    if (lastType.present) {
      map['last_type'] = Variable<String>(lastType.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackStateCompanion(')
          ..write('key: $key, ')
          ..write('activityId: $activityId, ')
          ..write('lastTimeNanos: $lastTimeNanos, ')
          ..write('lastLat: $lastLat, ')
          ..write('lastLon: $lastLon, ')
          ..write('lastAccuracyM: $lastAccuracyM, ')
          ..write('lastType: $lastType, ')
          ..write('distanceM: $distanceM, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $TrackPointsTable trackPoints = $TrackPointsTable(this);
  late final $TrackStateTable trackState = $TrackStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    activities,
    trackPoints,
    trackState,
  ];
}

typedef $$ActivitiesTableCreateCompanionBuilder = ActivitiesCompanion Function({
  Value<int> id,
  required String uuid,
  required String sport,
  required int startWallMillis,
  Value<int> elapsedNanos,
  Value<double> distanceM,
  Value<double> climbM,
  Value<int> fixCount,
  Value<int> rejectedCount,
  Value<bool> mockDetected,
  Value<String?> serverUuid,
  Value<int?> updatedAt,
  Value<bool> isDeleted,
});
typedef $$ActivitiesTableUpdateCompanionBuilder = ActivitiesCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> sport,
  Value<int> startWallMillis,
  Value<int> elapsedNanos,
  Value<double> distanceM,
  Value<double> climbM,
  Value<int> fixCount,
  Value<int> rejectedCount,
  Value<bool> mockDetected,
  Value<String?> serverUuid,
  Value<int?> updatedAt,
  Value<bool> isDeleted,
});

final class $$ActivitiesTableReferences
    extends BaseReferences<_$AppDatabase, $ActivitiesTable, Activity> {
  $$ActivitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TrackPointsTable, List<TrackPoint>>
  _trackPointsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.trackPoints,
    aliasName: 'activities__id__track_points__activity_id',
  );

  $$TrackPointsTableProcessedTableManager get trackPointsRefs {
    final manager = $$TrackPointsTableTableManager(
      $_db,
      $_db.trackPoints,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_trackPointsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivitiesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startWallMillis => $composableBuilder(
    column: $table.startWallMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedNanos => $composableBuilder(
    column: $table.elapsedNanos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get climbM => $composableBuilder(
    column: $table.climbM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fixCount => $composableBuilder(
    column: $table.fixCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mockDetected => $composableBuilder(
    column: $table.mockDetected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverUuid => $composableBuilder(
    column: $table.serverUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> trackPointsRefs(
    Expression<bool> Function($$TrackPointsTableFilterComposer f) f,
  ) {
    final $$TrackPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableFilterComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startWallMillis => $composableBuilder(
    column: $table.startWallMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedNanos => $composableBuilder(
    column: $table.elapsedNanos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get climbM => $composableBuilder(
    column: $table.climbM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fixCount => $composableBuilder(
    column: $table.fixCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mockDetected => $composableBuilder(
    column: $table.mockDetected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverUuid => $composableBuilder(
    column: $table.serverUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get sport =>
      $composableBuilder(column: $table.sport, builder: (column) => column);

  GeneratedColumn<int> get startWallMillis => $composableBuilder(
    column: $table.startWallMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elapsedNanos => $composableBuilder(
    column: $table.elapsedNanos,
    builder: (column) => column,
  );

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<double> get climbM =>
      $composableBuilder(column: $table.climbM, builder: (column) => column);

  GeneratedColumn<int> get fixCount =>
      $composableBuilder(column: $table.fixCount, builder: (column) => column);

  GeneratedColumn<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get mockDetected => $composableBuilder(
    column: $table.mockDetected,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverUuid => $composableBuilder(
    column: $table.serverUuid,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  Expression<T> trackPointsRefs<T extends Object>(
    Expression<T> Function($$TrackPointsTableAnnotationComposer a) f,
  ) {
    final $$TrackPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivitiesTable,
          Activity,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (Activity, $$ActivitiesTableReferences),
          Activity,
          PrefetchHooks Function({bool trackPointsRefs})
        > {
  $$ActivitiesTableTableManager(_$AppDatabase db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> sport = const Value.absent(),
                Value<int> startWallMillis = const Value.absent(),
                Value<int> elapsedNanos = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<double> climbM = const Value.absent(),
                Value<int> fixCount = const Value.absent(),
                Value<int> rejectedCount = const Value.absent(),
                Value<bool> mockDetected = const Value.absent(),
                Value<String?> serverUuid = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
              }) => ActivitiesCompanion(
                id: id,
                uuid: uuid,
                sport: sport,
                startWallMillis: startWallMillis,
                elapsedNanos: elapsedNanos,
                distanceM: distanceM,
                climbM: climbM,
                fixCount: fixCount,
                rejectedCount: rejectedCount,
                mockDetected: mockDetected,
                serverUuid: serverUuid,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String sport,
                required int startWallMillis,
                Value<int> elapsedNanos = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<double> climbM = const Value.absent(),
                Value<int> fixCount = const Value.absent(),
                Value<int> rejectedCount = const Value.absent(),
                Value<bool> mockDetected = const Value.absent(),
                Value<String?> serverUuid = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
              }) => ActivitiesCompanion.insert(
                id: id,
                uuid: uuid,
                sport: sport,
                startWallMillis: startWallMillis,
                elapsedNanos: elapsedNanos,
                distanceM: distanceM,
                climbM: climbM,
                fixCount: fixCount,
                rejectedCount: rejectedCount,
                mockDetected: mockDetected,
                serverUuid: serverUuid,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActivitiesTable, Activity>(table),
                  $$ActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (trackPointsRefs) db.trackPoints],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (trackPointsRefs)
                    await $_getPrefetchedData<
                      Activity,
                      $ActivitiesTable,
                      TrackPoint
                    >(
                      currentTable: table,
                      referencedTable: $$ActivitiesTableReferences
                          ._trackPointsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ActivitiesTableReferences(
                            db,
                            table,
                            p0,
                          ).trackPointsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.activityId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivitiesTable,
      Activity,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (Activity, $$ActivitiesTableReferences),
      Activity,
      PrefetchHooks Function({bool trackPointsRefs})
    >;
typedef $$TrackPointsTableCreateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      required int activityId,
      required int timeNanos,
      required double lat,
      required double lon,
      Value<double?> altGnss,
      required double accuracyM,
      Value<double?> speedMps,
      Value<double?> bearingDeg,
      required String waypointType,
    });
typedef $$TrackPointsTableUpdateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      Value<int> activityId,
      Value<int> timeNanos,
      Value<double> lat,
      Value<double> lon,
      Value<double?> altGnss,
      Value<double> accuracyM,
      Value<double?> speedMps,
      Value<double?> bearingDeg,
      Value<String> waypointType,
    });

final class $$TrackPointsTableReferences
    extends BaseReferences<_$AppDatabase, $TrackPointsTable, TrackPoint> {
  $$TrackPointsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias('track_points__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<int>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TrackPointsTableFilterComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeNanos => $composableBuilder(
    column: $table.timeNanos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altGnss => $composableBuilder(
    column: $table.altGnss,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bearingDeg => $composableBuilder(
    column: $table.bearingDeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointType => $composableBuilder(
    column: $table.waypointType,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeNanos => $composableBuilder(
    column: $table.timeNanos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altGnss => $composableBuilder(
    column: $table.altGnss,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bearingDeg => $composableBuilder(
    column: $table.bearingDeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointType => $composableBuilder(
    column: $table.waypointType,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeNanos =>
      $composableBuilder(column: $table.timeNanos, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get altGnss =>
      $composableBuilder(column: $table.altGnss, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<double> get bearingDeg => $composableBuilder(
    column: $table.bearingDeg,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointType => $composableBuilder(
    column: $table.waypointType,
    builder: (column) => column,
  );

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrackPointsTable,
          TrackPoint,
          $$TrackPointsTableFilterComposer,
          $$TrackPointsTableOrderingComposer,
          $$TrackPointsTableAnnotationComposer,
          $$TrackPointsTableCreateCompanionBuilder,
          $$TrackPointsTableUpdateCompanionBuilder,
          (TrackPoint, $$TrackPointsTableReferences),
          TrackPoint,
          PrefetchHooks Function({bool activityId})
        > {
  $$TrackPointsTableTableManager(_$AppDatabase db, $TrackPointsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> activityId = const Value.absent(),
                Value<int> timeNanos = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<double?> altGnss = const Value.absent(),
                Value<double> accuracyM = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<double?> bearingDeg = const Value.absent(),
                Value<String> waypointType = const Value.absent(),
              }) => TrackPointsCompanion(
                id: id,
                activityId: activityId,
                timeNanos: timeNanos,
                lat: lat,
                lon: lon,
                altGnss: altGnss,
                accuracyM: accuracyM,
                speedMps: speedMps,
                bearingDeg: bearingDeg,
                waypointType: waypointType,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int activityId,
                required int timeNanos,
                required double lat,
                required double lon,
                Value<double?> altGnss = const Value.absent(),
                required double accuracyM,
                Value<double?> speedMps = const Value.absent(),
                Value<double?> bearingDeg = const Value.absent(),
                required String waypointType,
              }) => TrackPointsCompanion.insert(
                id: id,
                activityId: activityId,
                timeNanos: timeNanos,
                lat: lat,
                lon: lon,
                altGnss: altGnss,
                accuracyM: accuracyM,
                speedMps: speedMps,
                bearingDeg: bearingDeg,
                waypointType: waypointType,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrackPointsTable, TrackPoint>(table),
                  $$TrackPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$TrackPointsTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$TrackPointsTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TrackPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrackPointsTable,
      TrackPoint,
      $$TrackPointsTableFilterComposer,
      $$TrackPointsTableOrderingComposer,
      $$TrackPointsTableAnnotationComposer,
      $$TrackPointsTableCreateCompanionBuilder,
      $$TrackPointsTableUpdateCompanionBuilder,
      (TrackPoint, $$TrackPointsTableReferences),
      TrackPoint,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$TrackStateTableCreateCompanionBuilder = TrackStateCompanion Function({
  required String key,
  required int activityId,
  required int lastTimeNanos,
  required double lastLat,
  required double lastLon,
  required double lastAccuracyM,
  required String lastType,
  required double distanceM,
  Value<int> rowid,
});
typedef $$TrackStateTableUpdateCompanionBuilder = TrackStateCompanion Function({
  Value<String> key,
  Value<int> activityId,
  Value<int> lastTimeNanos,
  Value<double> lastLat,
  Value<double> lastLon,
  Value<double> lastAccuracyM,
  Value<String> lastType,
  Value<double> distanceM,
  Value<int> rowid,
});

class $$TrackStateTableFilterComposer
    extends Composer<_$AppDatabase, $TrackStateTable> {
  $$TrackStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastTimeNanos => $composableBuilder(
    column: $table.lastTimeNanos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lastLat => $composableBuilder(
    column: $table.lastLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lastLon => $composableBuilder(
    column: $table.lastLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lastAccuracyM => $composableBuilder(
    column: $table.lastAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastType => $composableBuilder(
    column: $table.lastType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrackStateTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackStateTable> {
  $$TrackStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastTimeNanos => $composableBuilder(
    column: $table.lastTimeNanos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lastLat => $composableBuilder(
    column: $table.lastLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lastLon => $composableBuilder(
    column: $table.lastLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lastAccuracyM => $composableBuilder(
    column: $table.lastAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastType => $composableBuilder(
    column: $table.lastType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrackStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackStateTable> {
  $$TrackStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastTimeNanos => $composableBuilder(
    column: $table.lastTimeNanos,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lastLat =>
      $composableBuilder(column: $table.lastLat, builder: (column) => column);

  GeneratedColumn<double> get lastLon =>
      $composableBuilder(column: $table.lastLon, builder: (column) => column);

  GeneratedColumn<double> get lastAccuracyM => $composableBuilder(
    column: $table.lastAccuracyM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastType =>
      $composableBuilder(column: $table.lastType, builder: (column) => column);

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);
}

class $$TrackStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrackStateTable,
          TrackStateData,
          $$TrackStateTableFilterComposer,
          $$TrackStateTableOrderingComposer,
          $$TrackStateTableAnnotationComposer,
          $$TrackStateTableCreateCompanionBuilder,
          $$TrackStateTableUpdateCompanionBuilder,
          (
            TrackStateData,
            BaseReferences<_$AppDatabase, $TrackStateTable, TrackStateData>,
          ),
          TrackStateData,
          PrefetchHooks Function()
        > {
  $$TrackStateTableTableManager(_$AppDatabase db, $TrackStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int> activityId = const Value.absent(),
                Value<int> lastTimeNanos = const Value.absent(),
                Value<double> lastLat = const Value.absent(),
                Value<double> lastLon = const Value.absent(),
                Value<double> lastAccuracyM = const Value.absent(),
                Value<String> lastType = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrackStateCompanion(
                key: key,
                activityId: activityId,
                lastTimeNanos: lastTimeNanos,
                lastLat: lastLat,
                lastLon: lastLon,
                lastAccuracyM: lastAccuracyM,
                lastType: lastType,
                distanceM: distanceM,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required int activityId,
                required int lastTimeNanos,
                required double lastLat,
                required double lastLon,
                required double lastAccuracyM,
                required String lastType,
                required double distanceM,
                Value<int> rowid = const Value.absent(),
              }) => TrackStateCompanion.insert(
                key: key,
                activityId: activityId,
                lastTimeNanos: lastTimeNanos,
                lastLat: lastLat,
                lastLon: lastLon,
                lastAccuracyM: lastAccuracyM,
                lastType: lastType,
                distanceM: distanceM,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrackStateTable, TrackStateData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TrackStateTable,
                    TrackStateData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrackStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrackStateTable,
      TrackStateData,
      $$TrackStateTableFilterComposer,
      $$TrackStateTableOrderingComposer,
      $$TrackStateTableAnnotationComposer,
      $$TrackStateTableCreateCompanionBuilder,
      $$TrackStateTableUpdateCompanionBuilder,
      (
        TrackStateData,
        BaseReferences<_$AppDatabase, $TrackStateTable, TrackStateData>,
      ),
      TrackStateData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$TrackPointsTableTableManager get trackPoints =>
      $$TrackPointsTableTableManager(_db, _db.trackPoints);
  $$TrackStateTableTableManager get trackState =>
      $$TrackStateTableTableManager(_db, _db.trackState);
}
