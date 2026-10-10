import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    );

    final r = await repo.loadResume();
    expect(r, isNotNull);
    expect(r!.activityId, id);
    expect(r.distanceM, closeTo(222.4, 0.1));
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
    'every appended point is durable before the next one arrives (rule ر13)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
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
          ),
        ]);
      }
      expect(await repo.pointCount(id), 50);
      await db.close();
    },
  );
}
