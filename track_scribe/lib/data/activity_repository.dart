import 'package:drift/drift.dart';

import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/gps_quality.dart';

/// A resume checkpoint decoded back into engine types (rule ر12: the
/// checkpoint carries the exact distance, elapsed total and last stored point
/// of the previous session so a killed recording resumes where it stopped).
class ResumeRow {
  const ResumeRow({
    required this.activityId,
    required this.lastStored,
    required this.distanceM,
    required this.elapsedNanos,
  });
  final int activityId;
  final StoredPoint lastStored;
  final double distanceM;

  /// R81: the activity's elapsed INCLUDING this session's carried predecessors.
  /// It is a sum of measured monotonic durations, never a wall-clock
  /// difference (ر1) — the counterpart of [distanceM] so a resumed activity's
  /// totals describe the same recording.
  final int elapsedNanos;
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
  /// R76 boundary mapping: an unmeasured 1σ (`unmeasuredAccuracyM`) is
  /// written as SQL NULL — a sentinel is a missing measurement, never a
  /// number in the database. The checkpoint maps the same pair in both
  /// directions ([saveResume] writes NULL, [loadResume] reads it back as the
  /// sentinel), so `StoredPoint.accuracyM` stays non-nullable everywhere
  /// else and ر7 keeps refusing an unmeasured fix after a resume.
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
            accuracyM: Value(
              p.accuracyM == unmeasuredAccuracyM ? null : p.accuracyM,
            ),
            speedMps: Value(p.speedMps),
            bearingDeg: Value(p.bearingDeg),
            waypointType: p.type.name,
          ),
        );
      }
    });
  }

  /// Writes the ر12 checkpoint. The stored `lastTimeNanos` is session-relative
  /// monotonic time, meaningless in a new process, so the *clock reading* never
  /// resumes and the wall clock is never a duration source (ر1/R21). R81
  /// narrows R79's "الوقت restarts from zero": that sentence now describes the
  /// ON-SCREEN counter during a resumed session, which really does restart,
  /// while the PERSISTED total — [elapsedNanos] here, and the
  /// `Activities.elapsedNanos` written from it at stop — ACCUMULATES every
  /// session's measured duration, exactly as `distanceM` has always done, so
  /// the two halves of the row describe the same recording.
  /// R76: an unmeasured accuracy in [lastStored] is written as NULL and
  /// reads back through [loadResume] as the sentinel again.
  Future<void> saveResume({
    required int activityId,
    required StoredPoint lastStored,
    required double distanceM,
    required int elapsedNanos,
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
            lastAccuracyM: Value(
              lastStored.accuracyM == unmeasuredAccuracyM
                  ? null
                  : lastStored.accuracyM,
            ),
            lastType: lastStored.type.name,
            distanceM: distanceM,
            lastElapsedNanos: Value(elapsedNanos),
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
        // R76 read side: NULL means the sentinel, never a fake number.
        accuracyM: row.lastAccuracyM ?? unmeasuredAccuracyM,
        type: WaypointType.values.byName(row.lastType),
      ),
      distanceM: row.distanceM,
      elapsedNanos: row.lastElapsedNanos,
    );
  }

  /// Ends an activity cleanly — the counterpart of the ر12 checkpoint: the
  /// row's `elapsedNanos`, `distanceM`, `fixCount`, `rejectedCount` and
  /// `mockDetected` default to zero/false, so a stopped recording must
  /// write its real totals here before the resume row is cleared, or a
  /// later list/export would report an empty activity.
  /// R81: [elapsedNanos] and [distanceM] must be the SAME activity's totals —
  /// each already carrying what an earlier session wrote into the checkpoint.
  /// One session's time against all sessions' distance produces a row that
  /// validates fine and poisons every average pace read from it.
  Future<void> finishActivity({
    required int activityId,
    required int elapsedNanos,
    required double distanceM,
    required int fixCount,
    required int rejectedCount,
    required bool mockDetected,
  }) async {
    final row =
        await (_db.select(_db.activities)
              ..where((t) => t.id.equals(activityId)))
            .getSingle();
    await _db.update(_db.activities).replace(
      row.copyWith(
        elapsedNanos: elapsedNanos,
        distanceM: distanceM,
        fixCount: fixCount,
        rejectedCount: rejectedCount,
        mockDetected: mockDetected,
      ),
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
