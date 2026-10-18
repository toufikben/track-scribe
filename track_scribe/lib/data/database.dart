import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'activity_source.dart';

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
  // R125 (§2أ import): where the row came from. An imported file is not a
  // recording, and the history list orders by `startWallMillis` — a 2023 ride
  // imported today would otherwise sit among the owner's own activities with
  // nothing saying it was not measured here. `recorded` is the default because
  // the recorder is the only writer that exists so far; a new writer names
  // itself instead of inheriting the label silently.
  // Unlike the earlier table edits, this column IS a migration: a version-1
  // database is already on the owner's phone, so schemaVersion goes to 2 and
  // `AppDatabase.migration` adds the column in place (see its onUpgrade).
  TextColumn get source => text().withDefault(const Constant(kSourceRecorded))();
}

class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get activityId => integer().references(Activities, #id)();
  IntColumn get timeNanos => integer()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get altGnss => real().nullable()();
  // R76: an UNMEASURED 1σ is NULL, never a number; the `unmeasuredAccuracyM`
  // sentinel is mapped at the repository boundary. That edit was legal without
  // a migration (no installed database had the old shape yet); the R125 column
  // in [Activities] is the first change that does need one.
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
  // R81 (I-2): the elapsed this checkpoint's session had measured, INCLUDING
  // whatever an earlier session carried. Distance was already cumulative here,
  // while `Activities.elapsedNanos` came from one session only, so a resumed
  // activity stored all sessions' distance against one session's time — a
  // valid-looking row whose every average-pace number is wrong. Adding measured
  // monotonic DURATIONS is not a ر1 violation (ر1 bans deriving a duration from
  // the wall clock, which still never happens). Nullable is not needed: a
  // zero-checkpoint is exact.
  // These earlier edits (this column, and TrackPoints.accuracyM becoming
  // nullable) needed no migration because no installed database had the old
  // shape; R125's `source` column is the first change that does.
  IntColumn get lastElapsedNanos => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {key};
}

// R86: a single key/value row per persisted on/off flag — today only
// `onboarded`. Adding this table needed no migration: it went in while no
// installed database existed to upgrade.
class AppFlags extends Table {
  TextColumn get key => text()();
  BoolColumn get value => boolean()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Activities, TrackPoints, TrackState, AppFlags])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.open() : super(_openLocal());
  @override
  int get schemaVersion => 2;

  // Rule ر13 / spec §4: SQLite WAL is the durability mechanism ("drift +
  // SQLite WAL"). It is enabled on every open, so a file-backed database is
  // always in WAL mode and a point is fsynced to the write-ahead log before
  // the next one arrives.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // R125: the version-1 database on the owner's phone holds activities that
      // were all recorded here — the recorder was the only writer — so every
      // existing row is stamped `recorded` by the column default and stays
      // exactly as it was. Nothing else changes: no row is rewritten, no table
      // is rebuilt, and the points keep their rowid order (R78).
      if (from < 2) {
        await m.addColumn(activities, activities.source);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL');
    },
  );
}

LazyDatabase _openLocal() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase(File(p.join(dir.path, 'track_scribe.sqlite')));
});
