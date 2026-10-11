import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/gps_quality.dart';

/// R76: the `unmeasuredAccuracyM` sentinel must never be stored as a number.
/// The host SQLite build was MEASURED first (see task-9b report): inserting
/// `double.infinity` into the old non-null REAL column committed silently and
/// read back as Infinity — a fake measurement surviving into every future
/// export. The schema now says what is true (`accuracyM`/`lastAccuracyM` are
/// nullable), and the repository maps the sentinel at the boundary in both
/// directions; `StoredPoint.accuracyM` itself stays non-nullable so the
/// engine never sees a null.
void main() {
  test(
    'R76: the unmeasured sentinel is stored as SQL NULL and reads back as '
    'unmeasuredAccuracyM through StoredPoint, while a real accuracy is intact',
    () async {
      // File-backed, close, reopen: the same pattern as the ر13 durability
      // test — a reopened connection can only see what was really written.
      final dir = Directory.systemTemp.createTempSync('track_scribe_r76');
      final file = File(p.join(dir.path, 'sentinel.sqlite'));
      try {
        final db = AppDatabase(NativeDatabase(file));
        final repo = ActivityRepository(db);
        final id = await repo.insertActivity(
          uuid: 'r76-sentinel',
          sport: 'run',
          startWallMillis: 1,
        );
        const unmeasured = StoredPoint(
          lat: 36.7538,
          lon: 3.1856,
          timeNanos: 1000,
          accuracyM: unmeasuredAccuracyM,
          type: WaypointType.normal,
        );
        const normal = StoredPoint(
          lat: 36.7548,
          lon: 3.1856,
          timeNanos: 2000,
          accuracyM: 5.0,
          type: WaypointType.normal,
        );
        await repo.appendPoints(id, [unmeasured, normal]);
        await repo.saveResume(
          activityId: id,
          lastStored: unmeasured,
          distanceM: 111.0,
        );
        await db.close();

        final reopened = AppDatabase(NativeDatabase(file));
        try {
          final rows = await (reopened.select(
            reopened.trackPoints,
          )..where((t) => t.activityId.equals(id))).get();
          final unmeasuredRow = rows.firstWhere((r) => r.timeNanos == 1000);
          final normalRow = rows.firstWhere((r) => r.timeNanos == 2000);

          // write side: the sentinel became NULL, never a number
          expect(unmeasuredRow.accuracyM, isNull);
          // the real measurement is untouched by the mapping
          expect(normalRow.accuracyM, 5.0);

          // read side, through StoredPoint: NULL comes back as the sentinel,
          // so ر7 keeps refusing an unmeasured fix after a resume.
          final r = await ActivityRepository(reopened).loadResume();
          expect(r!.lastStored.accuracyM, unmeasuredAccuracyM);
          expect(r.lastStored.accuracyM.isInfinite, isTrue);
        } finally {
          await reopened.close();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
