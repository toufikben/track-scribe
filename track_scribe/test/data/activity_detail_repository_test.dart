import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/gps_quality.dart';

void main() {
  late AppDatabase db;
  late ActivityRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
  });

  tearDown(() => db.close());

  test('loadActivityWithPoints returns totals and points in write order', () async {
    final id = await repo.insertActivity(
      uuid: 'act-test', sport: 'run', startWallMillis: 1234,
    );
    final pts = [
      StoredPoint(lat: 36.75, lon: 3.04, timeNanos: 10, accuracyM: 5, type: WaypointType.normal),
      StoredPoint(lat: 36.751, lon: 3.041, timeNanos: 20, accuracyM: unmeasuredAccuracyM, type: WaypointType.idle),
    ];
    await repo.appendPoints(id, pts);
    await repo.finishActivity(
      activityId: id,
      elapsedNanos: 100,
      distanceM: 42.5,
      fixCount: 2,
      rejectedCount: 0,
      mockDetected: false,
    );

    // Named type, not `final s =`: this is the interface Task 6 compiles
    // against, so the test fails to build if the reader's return type drifts.
    final ActivitySummary? s = await repo.loadActivityWithPoints(id);
    expect(s, isNotNull);
    expect(s!.sport, 'run');
    expect(s.distanceM, 42.5);
    expect(s.elapsedNanos, 100);
    expect(s.points.length, 2);
    expect(s.points.first.type, WaypointType.normal);
    expect(s.points.last.accuracyM, unmeasuredAccuracyM); // R76 round-trip
    expect(s.points.last.type, WaypointType.idle);
  });

  test('returns null for an unknown id', () async {
    expect(await repo.loadActivityWithPoints(999), isNull);
  });
}
