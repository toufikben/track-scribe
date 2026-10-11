import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

void main() {
  test('a killed session resumes with the same distance, not a reset one (rule ر12)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ActivityRepository(db);
    final id = await repo.insertActivity(
      uuid: 'u1',
      sport: 'run',
      startWallMillis: 1,
    );
    await repo.appendPoints(id, [
      const StoredPoint(
        lat: 36.7538,
        lon: 3.1856,
        timeNanos: 1000,
        accuracyM: 4,
        type: WaypointType.normal,
      ),
      const StoredPoint(
        lat: 36.7558,
        lon: 3.1856,
        timeNanos: 9000,
        accuracyM: 4,
        type: WaypointType.normal,
      ),
    ]);
    await repo.saveResume(
      activityId: id,
      lastStored: const StoredPoint(
        lat: 36.7558,
        lon: 3.1856,
        timeNanos: 9000,
        accuracyM: 4,
        type: WaypointType.normal,
      ),
      distanceM: 222.4,
      // R81: the checkpoint carries the elapsed TOTAL (nanoseconds of measured
      // monotonic duration across every session that wrote this row).
      elapsedNanos: 61000,
    );

    final r = await repo.loadResume();
    expect(r, isNotNull);
    expect(r!.activityId, id);
    expect(r.distanceM, closeTo(222.4, 0.1));
    // An exact total that no other column of this row holds: the column's
    // `Constant(0)` default, and a value copied from `lastTimeNanos`, would
    // each survive a weaker assertion — only the distinct number pins the
    // write/read round trip of the new column.
    expect(
      r.elapsedNanos,
      61000,
      reason: 'R81: elapsed accumulates across a kill instead of resetting',
    );
    expect(
      r.lastStored.distanceTo(
        const StoredPoint(
          lat: 36.7538,
          lon: 3.1856,
          timeNanos: 1000,
          accuracyM: 4,
          type: WaypointType.normal,
        ),
      ),
      closeTo(222.4, 1.0),
    );
    await db.close();
  });

  test(
    'every appended point survives an app death: reopen over the same file '
    'and read the fields back (rule ر13, WAL)',
    () async {
      // A file-backed database, not NativeDatabase.memory(): memory proves
      // nothing about durability, because a count on the same in-process
      // connection stays 50 even if the write never reached storage. We use
      // a real file so that closing and reopening it is a genuine "app was
      // killed" simulation — the reopened connection can only see what the
      // first one actually flushed to disk.
      final dir = Directory.systemTemp.createTempSync('track_scribe_r13');
      final file = File(p.join(dir.path, 'durability.sqlite'));
      try {
        final db = AppDatabase(NativeDatabase(file));
        final repo = ActivityRepository(db);
        final id = await repo.insertActivity(
          uuid: 'u2',
          sport: 'walk',
          startWallMillis: 1,
        );
        for (var i = 0; i < 50; i++) {
          await repo.appendPoints(id, [
            StoredPoint(
              lat: 36.7538 + i / 10000,
              lon: 3.1856,
              timeNanos: i * 1000000000,
              accuracyM: 5,
              type: WaypointType.normal,
              altitudeM: 120.0 + i,
            ),
          ]);
        }

        // ر13 / spec §4: the durability mechanism is SQLite WAL, and it must
        // be measured on this file-backed database, not assumed. (An
        // in-memory database cannot take WAL — hence this is the file test.)
        final journalMode =
            (await db.customSelect('PRAGMA journal_mode').get()).single
                .data['journal_mode'];
        expect(journalMode, 'wal');

        // App death: the connection is gone entirely, then a fresh one opens
        // the same backing store on next launch.
        await db.close();
        final reopened = AppDatabase(NativeDatabase(file));
        try {
          // the write survived — every point is really on disk
          expect(await ActivityRepository(reopened).pointCount(id), 50);

          // and the just-appended point's fields came back through the new
          // connection (lat/lon/type, plus the GNSS altitude we now persist)
          final last =
              await (reopened.select(reopened.trackPoints)
                    ..where((t) => t.activityId.equals(id))
                    ..where((t) => t.timeNanos.equals(49 * 1000000000)))
                  .getSingle();
          expect(last.lat, closeTo(36.7538 + 49 / 10000, 1e-9));
          expect(last.lon, closeTo(3.1856, 1e-9));
          expect(last.waypointType, WaypointType.normal.name);
          expect(last.altGnss, closeTo(120.0 + 49, 1e-9));
        } finally {
          await reopened.close();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
