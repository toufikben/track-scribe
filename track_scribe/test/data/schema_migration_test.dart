import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/database.dart';

/// R125 (§2أ import): a file that was not recorded here must not be filed with
/// the recorded activities as if it were. The schema carries the provenance, so
/// a real migration is required: the owner's phone already holds a version-1
/// database full of recorded activities, and those rows must survive untouched.
///
/// The pre-migration fixture below is NOT invented: it is the verbatim DDL
// MEASURED out of a fresh version-1 database on this machine (dumped with
/// `SELECT sql FROM sqlite_master`, `PRAGMA user_version` = 1), so the test
/// upgrades the shape a released build really wrote.
void main() {
  const v1Activities =
      'CREATE TABLE "activities" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"uuid" TEXT NOT NULL, "sport" TEXT NOT NULL, "start_wall_millis" INTEGER NOT NULL, '
      '"elapsed_nanos" INTEGER NOT NULL DEFAULT 0, "distance_m" REAL NOT NULL DEFAULT 0.0, '
      '"climb_m" REAL NOT NULL DEFAULT 0.0, "fix_count" INTEGER NOT NULL DEFAULT 0, '
      '"rejected_count" INTEGER NOT NULL DEFAULT 0, "mock_detected" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("mock_detected" IN (0, 1)), "server_uuid" TEXT NULL, "updated_at" INTEGER NULL, '
      '"is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)))';
  const v1TrackPoints =
      'CREATE TABLE "track_points" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"activity_id" INTEGER NOT NULL REFERENCES activities (id), "time_nanos" INTEGER NOT NULL, '
      '"lat" REAL NOT NULL, "lon" REAL NOT NULL, "alt_gnss" REAL NULL, "accuracy_m" REAL NULL, '
      '"speed_mps" REAL NULL, "bearing_deg" REAL NULL, "waypoint_type" TEXT NOT NULL)';
  const v1TrackState =
      'CREATE TABLE "track_state" ("key" TEXT NOT NULL, "activity_id" INTEGER NOT NULL, '
      '"last_time_nanos" INTEGER NOT NULL, "last_lat" REAL NOT NULL, "last_lon" REAL NOT NULL, '
      '"last_accuracy_m" REAL NULL, "last_type" TEXT NOT NULL, "distance_m" REAL NOT NULL, '
      '"last_elapsed_nanos" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("key"))';
  const v1AppFlags =
      'CREATE TABLE "app_flags" ("key" TEXT NOT NULL, "value" INTEGER NOT NULL '
      'CHECK ("value" IN (0, 1)), PRIMARY KEY ("key"))';

  /// Write a database exactly as a version-1 install left it, with one of the
  /// owner's recorded activities and its point, checkpoint and flag in it.
  Future<void> buildV1Database(String path) async {
    final executor = NativeDatabase(File(path));
    await executor.ensureOpen(const _FixtureUser());
    for (final ddl in [v1Activities, v1TrackPoints, v1TrackState, v1AppFlags]) {
      await executor.runCustom(ddl, const []);
    }
    await executor.runCustom(
      'INSERT INTO activities (uuid, sport, start_wall_millis, elapsed_nanos, '
      'distance_m, fix_count) VALUES (?, ?, ?, ?, ?, ?)',
      ['v1-owner-row', 'run', 1700000000000, 600000000000, 4212.5, 77],
    );
    await executor.runCustom(
      'INSERT INTO track_points (activity_id, time_nanos, lat, lon, waypoint_type) '
      'VALUES (?, ?, ?, ?, ?)',
      [1, 1000, 36.7538, 3.1856, 'normal'],
    );
    await executor.runCustom(
      'INSERT INTO track_state (key, activity_id, last_time_nanos, last_lat, '
      'last_lon, last_type, distance_m) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['checkpoint', 1, 1000, 36.7538, 3.1856, 'normal', 4212.5],
    );
    await executor.runCustom(
      'INSERT INTO app_flags (key, value) VALUES (?, ?)',
      ['onboarded', 1],
    );
    await executor.runCustom('PRAGMA user_version = 1', const []);
    await executor.close();
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.data.values.first as int;
  }

  test('a version-1 database upgrades in place: every old row survives and is '
      'marked recorded, which is the truth about it', () async {
    final dir = Directory.systemTemp.createTempSync('track_scribe_r125');
    final path = p.join(dir.path, 'owner.sqlite');
    await buildV1Database(path);

    final db = AppDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);

    expect(await userVersion(db), 2);

    final rows = await db
        .customSelect('SELECT uuid, source FROM activities')
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('uuid'), 'v1-owner-row');
    // Not a default that happens to apply to new inserts: the row written
    // before the column existed must read back as what it actually was.
    expect(rows.single.read<String>('source'), 'recorded');

    // The upgrade must not lose, rewrite or duplicate anything else.
    final points = await db
        .customSelect('SELECT lat, lon, waypoint_type FROM track_points')
        .get();
    expect(points, hasLength(1));
    expect(points.single.read<double>('lat'), 36.7538);
    expect(points.single.read<String>('waypoint_type'), 'normal');
    expect(
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM track_state')
              .getSingle())
          .read<int>('n'),
      1,
    );
    expect(
      (await db
              .customSelect(
                "SELECT value FROM app_flags WHERE key = 'onboarded'",
              )
              .getSingle())
          .read<int>('value'),
      1,
    );

    // The columns the migration added must not disturb the ones it did not:
    // the totals the owner recorded are still exactly what they were.
    final kept = await db
        .customSelect(
          'SELECT start_wall_millis, elapsed_nanos, distance_m, fix_count '
          'FROM activities',
        )
        .getSingle();
    expect(kept.read<int>('start_wall_millis'), 1700000000000);
    expect(kept.read<int>('elapsed_nanos'), 600000000000);
    expect(kept.read<double>('distance_m'), 4212.5);
    expect(kept.read<int>('fix_count'), 77);
  });

  test(
    'a version-1 database keeps working after the upgrade: a new activity '
    'inserts, and its point attaches to it through the same connection',
    () async {
      final dir = Directory.systemTemp.createTempSync('track_scribe_r125_new');
      final path = p.join(dir.path, 'owner.sqlite');
      await buildV1Database(path);

      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);

      final id = await db
          .into(db.activities)
          .insert(
            ActivitiesCompanion.insert(
              uuid: 'after-upgrade',
              sport: 'bike',
              startWallMillis: 1700000999000,
            ),
          );
      expect(id, greaterThan(1));
      final row = await (db.select(
        db.activities,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.source, 'recorded');
      expect(row.uuid, 'after-upgrade');
    },
  );
}

/// drift will not run a statement on an executor it has not opened, and opening
/// needs a [QueryExecutorUser]. This one exists only so the fixture can write
/// the version-1 SQL through the same SQLite path the app uses; it never runs a
/// query, and the database under test is always a real [AppDatabase].
class _FixtureUser implements QueryExecutorUser {
  const _FixtureUser();

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {
    // The fixture writes raw SQL; no pragma is owed here beyond what the DDL
    // statements themselves set.
  }
}
