import 'package:drift/drift.dart';

import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/gps_quality.dart';

/// R86: the one flag onboarding writes and [AppGate] reads — whether this
/// install has ever shown the permission instructions screen. It is a durable
/// row, so a fresh install re-shows onboarding after a kill, not just after an
/// uninstall.
const kOnboardedFlag = 'onboarded';

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

  /// The detail screen's read: one activity's row plus every point in
  /// engine/write order (rowid order — R78 guarantees append order = id order).
  /// NULL accuracy reads back as the R76 sentinel, exactly like [loadResume].
  ///
  /// `ORDER BY id` and NOT `ORDER BY timeNanos`: R79 lets a resumed session's
  /// on-screen clock restart, so `timeNanos` is monotonic time relative to
  /// whichever process wrote the point and is meaningless across a resume,
  /// while the append chain (_enqueueStoredPoints) is what actually defines
  /// engine order. Sorting by time would reorder a track that was recorded
  /// correctly, and a polyline is only honest in the order it was walked.
  ///
  /// The totals carry no `?? 0`: every one of them has a schema default, so
  /// drift types them non-nullable and a null-aware read here would be dead
  /// code the analyzer rejects — the default is enforced in the table, not at
  /// the reader.
  Future<ActivitySummary?> loadActivityWithPoints(int activityId) async {
    final row = await (_db.select(_db.activities)
          ..where((t) => t.id.equals(activityId))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final pts = await (_db.select(_db.trackPoints)
          ..where((t) => t.activityId.equals(activityId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return ActivitySummary(
      id: row.id,
      sport: row.sport,
      startWallMillis: row.startWallMillis,
      distanceM: row.distanceM,
      elapsedNanos: row.elapsedNanos,
      fixCount: row.fixCount,
      rejectedCount: row.rejectedCount,
      mockDetected: row.mockDetected,
      points: [
        for (final p in pts)
          StoredPoint(
            lat: p.lat,
            lon: p.lon,
            timeNanos: p.timeNanos,
            // R76 read side: the sentinel is restored, never a stored number
            // and never a null — `StoredPoint.accuracyM` is non-nullable so
            // every consumer (aggregations, drift, the map) must skip this
            // value instead of averaging an infinity into a real 1σ.
            accuracyM: p.accuracyM ?? unmeasuredAccuracyM,
            type: WaypointType.values.byName(p.waypointType),
            altitudeM: p.altGnss,
            speedMps: p.speedMps,
            bearingDeg: p.bearingDeg,
          ),
      ],
    );
  }

  /// خطة 3: what the history list reads — every non-deleted activity, newest
  /// start first, with its totals and NONE of its points (ر117).
  ///
  /// `ORDER BY start_wall_millis DESC, id DESC`: the wall clock is the only
  /// key that matches what the user saw while recording, and ر1 forbids using
  /// it as a duration source, not as a display key. `id DESC` breaks a tie
  /// between two rows stamped in the same millisecond, so the list cannot
  /// reshuffle itself between two reads.
  ///
  /// Two SELECTs total: the activity rows, then the one-row `resume`
  /// checkpoint to learn which of them is still open (ر121) — and, per ر123,
  /// to SOURCE the two totals of an open row. A never-finished activity still
  /// holds the schema defaults 0 m / 0 ns in its `activities` row, so for
  /// `isOpen` rows the stored row values are NOT the source of truth and the
  /// checkpoint's measured `distanceM`/`lastElapsedNanos` are returned
  /// instead. The checkpoint table carries no per-fix columns
  /// (database.dart:44-68), so `fixCount`/`rejectedCount`/`mockDetected` stay
  /// the unfinalized row's defaults — which is why no view may render them
  /// for an open row. `track_points` is never opened here — that is the whole
  /// point of the return type.
  Future<List<ActivityListItem>> listActivities() async {
    final rows =
        await (_db.select(_db.activities)
              ..where((t) => t.isDeleted.equals(false))
              ..orderBy([
                (t) => OrderingTerm.desc(t.startWallMillis),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .get();
    if (rows.isEmpty) return const [];
    final checkpoints = {
      for (final s in await (_db.select(_db.trackState)
            ..where((t) => t.key.equals('resume')))
          .get())
        s.activityId: s,
    };
    return [
      for (final r in rows)
        ActivityListItem(
          id: r.id,
          sport: r.sport,
          startWallMillis: r.startWallMillis,
          // ر123: an activity named by a resume checkpoint has never been
          // finished, so its `activities` row still holds the schema defaults
          // 0 m / 0 ns — numbers nobody measured. The checkpoint the open-set
          // lookup already loaded carries the MEASURED totals (distanceM is
          // cumulative, lastElapsedNanos is R81's cross-session sum), so the
          // «قيد التسجيل» row prints those instead of an unmeasured zero.
          distanceM: checkpoints[r.id]?.distanceM ?? r.distanceM,
          elapsedNanos: checkpoints[r.id]?.lastElapsedNanos ?? r.elapsedNanos,
          fixCount: r.fixCount,
          rejectedCount: r.rejectedCount,
          mockDetected: r.mockDetected,
          isOpen: checkpoints.containsKey(r.id),
        ),
    ];
  }

  /// R86: read one persisted on/off flag; an unwritten key returns [defaultValue].
  Future<bool> flag(String key, {bool defaultValue = false}) async {
    final row =
        await (_db.select(_db.appFlags)
              ..where((t) => t.key.equals(key))
              ..limit(1))
            .getSingleOrNull();
    return row?.value ?? defaultValue;
  }

  /// R86: upsert one flag on its primary key, so a second write replaces the
  /// first instead of colliding.
  Future<void> setFlag(String key, bool value) {
    return _db
        .into(_db.appFlags)
        .insertOnConflictUpdate(AppFlagsCompanion.insert(key: key, value: value));
  }
}
