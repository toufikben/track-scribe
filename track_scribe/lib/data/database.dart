import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Activities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get sport => text()();
  IntColumn get startWallMillis => integer()();
  IntColumn get elapsedNanos => integer().withDefault(const Constant(0))();
  RealColumn get distanceM => real().withDefault(const Constant(0))();
  RealColumn get climbM => real().withDefault(const Constant(0))();
  IntColumn get fixCount => integer().withDefault(const Constant(0))();
  IntColumn get rejectedCount => integer().withDefault(const Constant(0))();
  BoolColumn get mockDetected => boolean().withDefault(const Constant(false))();
  // sync-ready columns, deliberately unused until a backend exists
  TextColumn get serverUuid => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get activityId => integer().references(Activities, #id)();
  IntColumn get timeNanos => integer()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get altGnss => real().nullable()();
  // R76: an UNMEASURED 1σ is NULL, never a number; the `unmeasuredAccuracyM`
  // sentinel is mapped at the repository boundary. schemaVersion stays 1 —
  // no released app exists, so editing the table is not a migration.
  RealColumn get accuracyM => real().nullable()();
  RealColumn get speedMps => real().nullable()();
  RealColumn get bearingDeg => real().nullable()();
  TextColumn get waypointType => text()();
}

class TrackState extends Table {
  TextColumn get key => text()();
  IntColumn get activityId => integer()();
  IntColumn get lastTimeNanos => integer()();
  RealColumn get lastLat => real()();
  RealColumn get lastLon => real()();
  // R76: NULL means the checkpoint's last stored fix had no measured 1σ
  // (same sentinel rule and same no-migration note as TrackPoints.accuracyM).
  RealColumn get lastAccuracyM => real().nullable()();
  TextColumn get lastType => text()();
  RealColumn get distanceM => real()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Activities, TrackPoints, TrackState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.open() : super(_openLocal());
  @override
  int get schemaVersion => 1;

  // Rule ر13 / spec §4: SQLite WAL is the durability mechanism ("drift +
  // SQLite WAL"). It is enabled on every open, so a file-backed database is
  // always in WAL mode and a point is fsynced to the write-ahead log before
  // the next one arrives. schemaVersion stays 1 (no schema change here).
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL');
    },
  );
}

LazyDatabase _openLocal() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase(File(p.join(dir.path, 'track_scribe.sqlite')));
});
