import 'package:drift/drift.dart';

import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// A resume checkpoint decoded back into engine types (rule ر12: the
/// checkpoint carries the exact distance and last stored point of the
/// previous session so a killed recording resumes where it stopped).
class ResumeRow {
  const ResumeRow({
    required this.activityId,
    required this.lastStored,
    required this.distanceM,
  });
  final int activityId;
  final StoredPoint lastStored;
  final double distanceM;
}

class ActivityRepository {
  ActivityRepository(this._db);
  final AppDatabase _db;

  Future<int> insertActivity({
    required String uuid,
    required String sport,
    required int startWallMillis,
  }) {
    return _db
        .into(_db.activities)
        .insert(
          ActivitiesCompanion.insert(
            uuid: uuid,
            sport: sport,
            startWallMillis: startWallMillis,
          ),
        );
  }

  /// Rule ر13: one `batch()` = one immediate transaction. The returned
  /// future only completes after that transaction has committed, so every
  /// appended point is durable before the caller proceeds to the next one.
  /// Note: `accuracyM` is a non-null REAL column, so a heartbeat-forced store
  /// of an unmeasured-accuracy fix persists the `unmeasuredAccuracyM` sentinel;
  /// what to do with it on read/export is Task 9b's decision.
  Future<void> appendPoints(int activityId, List<StoredPoint> points) {
    return _db.batch((batch) {
      for (final p in points) {
        batch.insert(
          _db.trackPoints,
          TrackPointsCompanion.insert(
            activityId: activityId,
            timeNanos: p.timeNanos,
            lat: p.lat,
            lon: p.lon,
            altGnss: Value(p.altitudeM),
            accuracyM: p.accuracyM,
            speedMps: Value(p.speedMps),
            bearingDeg: Value(p.bearingDeg),
            waypointType: p.type.name,
          ),
        );
      }
    });
  }

  Future<void> saveResume({
    required int activityId,
    required StoredPoint lastStored,
    required double distanceM,
  }) {
    // upsert on the primary key `key` (rule ر12: exactly one 'resume' row)
    return _db
        .into(_db.trackState)
        .insertOnConflictUpdate(
          TrackStateCompanion.insert(
            key: 'resume',
            activityId: activityId,
            lastTimeNanos: lastStored.timeNanos,
            lastLat: lastStored.lat,
            lastLon: lastStored.lon,
            lastAccuracyM: lastStored.accuracyM,
            lastType: lastStored.type.name,
            distanceM: distanceM,
          ),
        );
  }

  Future<ResumeRow?> loadResume() async {
    final row =
        await (_db.select(_db.trackState)
              ..where((t) => t.key.equals('resume'))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return ResumeRow(
      activityId: row.activityId,
      lastStored: StoredPoint(
        lat: row.lastLat,
        lon: row.lastLon,
        timeNanos: row.lastTimeNanos,
        accuracyM: row.lastAccuracyM,
        type: WaypointType.values.byName(row.lastType),
      ),
      distanceM: row.distanceM,
    );
  }

  Future<void> clearResume(int activityId) {
    return (_db.delete(_db.trackState)..where(
          (t) => t.key.equals('resume') & t.activityId.equals(activityId),
        ))
        .go();
  }

  Future<int> pointCount(int activityId) async {
    final count = _db.trackPoints.id.count();
    final q = _db.selectOnly(_db.trackPoints)
      ..addColumns([count])
      ..where(_db.trackPoints.activityId.equals(activityId));
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }
}
