import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// A seed row with given start stamp and totals, written the way the recorder
/// writes them: insert, points, then finishActivity.
///
/// Review I-2/M-1: [uuid], [fixCount], [rejectedCount] and [mockDetected] are
/// per-row parameters, not constants. The uuid must stay a non-monotone
/// literal at every call site — the old `'uuid-$startWallMillis'` shape
/// ascended with the stamp, so an `ORDER BY uuid DESC` implementation could
/// impersonate the documented sort key. The three per-fix counters must vary
/// per row, so a swap of two of them or a hard-coded [mockDetected] fails an
/// assertion instead of passing silently.
Future<int> _seed(
  ActivityRepository repo, {
  required String uuid,
  required int startWallMillis,
  double distanceM = 6400,
  int elapsedNanos = 2_000_000_000_000,
  int fixCount = 1,
  int rejectedCount = 0,
  bool mockDetected = false,
  String sport = 'run',
}) async {
  final id = await repo.insertActivity(
    uuid: uuid,
    sport: sport,
    startWallMillis: startWallMillis,
  );
  await repo.appendPoints(id, [
    StoredPoint(
      lat: 36.75,
      lon: 3.04,
      timeNanos: 0,
      accuracyM: 5,
      type: WaypointType.normal,
    ),
  ]);
  await repo.finishActivity(
    activityId: id,
    elapsedNanos: elapsedNanos,
    distanceM: distanceM,
    fixCount: fixCount,
    rejectedCount: rejectedCount,
    mockDetected: mockDetected,
  );
  return id;
}

/// A repository whose checkpoint removal always fails, so
/// `finishAndClearResume`'s second statement throws inside its transaction
/// (review I-1). `finishActivity` is NOT overridden: the point is that a
/// successful totals write must not survive a failed clear.
class _ClearResumeFailingRepo extends ActivityRepository {
  _ClearResumeFailingRepo(super.db);

  @override
  Future<void> clearResume(int activityId) {
    throw StateError('simulated checkpoint removal failure');
  }
}

void main() {
  late AppDatabase db;
  late ActivityRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
  });
  tearDown(() => db.close());

  test('a fresh install lists nothing', () async {
    expect(await repo.listActivities(), isEmpty);
  });

  test('lists newest start first, with the row totals', () async {
    // M-1: the uuid letters deliberately do NOT ascend with the stamp, in
    // either direction. Here stamps 1.70/1.80/1.75e12 carry uuid b/a/c, so
    // `ORDER BY uuid DESC` yields stamps 1.75/1.70/1.80 and
    // `ORDER BY uuid ASC` yields 1.80/1.70/1.75 — neither is the expected
    // 1.80/1.75/1.70. The ordering promise can only be kept by the real key.
    await _seed(
      repo,
      uuid: 'uuid-b',
      startWallMillis: 1_700_000_000_000,
      distanceM: 1000,
      elapsedNanos: 4_000_000_000_000,
      fixCount: 10,
      rejectedCount: 1,
    );
    await _seed(
      repo,
      uuid: 'uuid-a',
      startWallMillis: 1_800_000_000_000,
      distanceM: 6400,
      elapsedNanos: 8_000_000_000_000,
      fixCount: 25,
      rejectedCount: 0,
      mockDetected: true,
    );
    await _seed(
      repo,
      uuid: 'uuid-c',
      startWallMillis: 1_750_000_000_000,
      distanceM: 300,
      elapsedNanos: 1_500_000_000_000,
      fixCount: 7,
      rejectedCount: 2,
      sport: 'walk',
    );

    final items = await repo.listActivities();
    expect(items.map((i) => i.startWallMillis), [
      1_800_000_000_000,
      1_750_000_000_000,
      1_700_000_000_000,
    ]);
    expect(items.map((i) => i.sport), ['run', 'walk', 'run']);
    expect(items.map((i) => i.distanceM), [6400, 300, 1000]);
    expect(items.map((i) => i.elapsedNanos), [
      8_000_000_000_000,
      1_500_000_000_000,
      4_000_000_000_000,
    ]);
    // Review I-2: no per-fix expectation belongs here. `ActivityListItem` has
    // no `fixCount`/`rejectedCount`/`mockDetected` at all, so the list cannot
    // print an unfinalized row's zeros; the columns are covered where they are
    // final (`test/state/recording_persistence_test.dart`, the detail screen).
    // Every field the row renders must be present; nothing else is invented.
    expect(items.map((i) => i.isOpen), [false, false, false]);
  });

  test('a soft-deleted activity is not listed', () async {
    // M-2: the deleted row is seeded FIRST, so it holds the LOWER id. The
    // single-list assertion then also proves an included row survives whose
    // id is greater than the deleted one — a bogus "only id 1" filter can no
    // longer fake this result.
    final gone = await _seed(
      repo,
      uuid: 'uuid-gone',
      startWallMillis: 1_700_000_000_000,
    );
    final keep = await _seed(
      repo,
      uuid: 'uuid-keep',
      startWallMillis: 1_800_000_000_000,
    );
    await (db.update(db.activities)
          ..where((t) => t.id.equals(gone)))
        .write(const ActivitiesCompanion(isDeleted: Value(true)));

    final items = await repo.listActivities();
    expect(keep, greaterThan(gone));
    expect(items.map((i) => i.id), [keep]);
  });

  // I-1: the documented promise — two activities stamped in the same
  // millisecond do not reshuffle between reads — rests entirely on the
  // `id DESC` tie-break. Every other seed uses distinct stamps, so this is
  // the only test that dies when that term is removed (proved by sabotage in
  // the fix-round report).
  test('same-millisecond rows keep a stable id DESC order', () async {
    // The uuids are deliberately OPPOSITE to the required order (a sorts
    // after b but must come second here), so a uuid-based tie-break cannot
    // impersonate the rowid one even inside this test.
    final first = await _seed(
      repo,
      uuid: 'uuid-tie-b',
      startWallMillis: 1_900_000_000_000,
      distanceM: 111,
      elapsedNanos: 1_000_000_000_000,
    );
    final second = await _seed(
      repo,
      uuid: 'uuid-tie-a',
      startWallMillis: 1_900_000_000_000,
      distanceM: 222,
      elapsedNanos: 2_000_000_000_000,
    );

    final items = await repo.listActivities();
    // Rowid DESC: the later insert comes first, deterministically.
    expect(items.map((i) => i.id), [second, first]);
    expect(items.map((i) => i.distanceM), [222, 111]);
    expect(items.map((i) => i.elapsedNanos), [
      2_000_000_000_000,
      1_000_000_000_000,
    ]);
  });

  // ر121: the checkpoint is what makes a row "still open" — a ColorOS kill
  // leaves the activity in the table, and hiding it would read as data loss.
  // ر123 (review I-3): such a row prints the checkpoint's MEASURED totals,
  // because its own `activities` values are still the schema defaults
  // 0 m / 0 ns — numbers nobody measured, forbidden by «لا نطبع رقمًا لم يُقس».
  test('the activity a resume checkpoint still names is marked open', () async {
    final closed = await _seed(
      repo,
      uuid: 'uuid-closed',
      startWallMillis: 1_700_000_000_000,
    );
    final live = await repo.insertActivity(
      uuid: 'uuid-live',
      sport: 'bike',
      startWallMillis: 1_800_000_000_000,
    );
    await repo.saveResume(
      activityId: live,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    final items = await repo.listActivities();
    expect(items.map((i) => (i.id, i.isOpen)), [(live, true), (closed, false)]);

    final open = items.firstWhere((ActivityListItem i) => i.id == live);
    // The «قيد التسجيل» row shows 120 m · 1:00 — the checkpoint's measured
    // cumulative distance and R81 cross-session elapsed — not the
    // unfinalized row's 0 م · 0:00.
    expect(open.distanceM, 120);
    expect(open.elapsedNanos, 60_000_000_000);
    // Review I-2: no per-fix assertion belongs here. `ActivityListItem` carries
    // no `fixCount`/`rejectedCount`/`mockDetected`, so an open row cannot even
    // hold the unfinalized zeros the `track_state` table has no column for.

    // And closing it removes the marker — the same checkpoint row the recorder
    // clears at stop. With no checkpoint naming it the row falls back to its
    // own stored values (zeros here, because this activity was never
    // finished) and no longer presents itself as open.
    await repo.clearResume(live);
    final after = await repo.listActivities();
    final afterLive = after.firstWhere((ActivityListItem i) => i.id == live);
    expect(afterLive.isOpen, isFalse);
    expect(afterLive.distanceM, 0);
    expect(afterLive.elapsedNanos, 0);
  });

  // Review I-1: `stop()` wrote the row totals and cleared the checkpoint as two
  // separate awaits, so a kill between them left a checkpoint naming a FINISHED
  // row. That state had no coverage at all — and the absence was the bug: the
  // list masked the row's real totals with the older checkpoint, labelled it
  // «قيد التسجيل», and the screen set `onTap: null`, so the user could not open
  // their own recording. `finishActivity` now stamps `activities.updated_at`,
  // which makes "finished" a stored fact instead of an inference from a missing
  // checkpoint row.
  test('a finished activity whose checkpoint survived lists closed', () async {
    final id = await repo.insertActivity(
      uuid: 'uuid-orphan-checkpoint',
      sport: 'run',
      startWallMillis: 1_700_000_000_000,
    );
    // The checkpoint of the session that was still in progress: 120 m at the
    // cadence of the last write, i.e. OLDER and SMALLER than the stop totals.
    await repo.saveResume(
      activityId: id,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );
    // …then the row WAS finished, and the process died before `clearResume`.
    await repo.finishActivity(
      activityId: id,
      elapsedNanos: 900_000_000_000,
      distanceM: 3400,
      fixCount: 40,
      rejectedCount: 2,
      mockDetected: false,
    );

    final items = await repo.listActivities();
    final row = items.firstWhere((ActivityListItem i) => i.id == id);
    expect(
      row.isOpen,
      isFalse,
      reason:
          'a row finishActivity wrote is finished no matter what checkpoint '
          'survives — ر121 marks a KILLED recording, not a stopped one',
    );
    expect(
      row.distanceM,
      3400,
      reason: 'the finished row prints its OWN totals, not the stale 120 m',
    );
    expect(row.elapsedNanos, 900_000_000_000);

    // And the marker is the stored column, not the checkpoint: prove it by
    // clearing the checkpoint too — the row must stay closed with the same
    // numbers, i.e. nothing about it depended on the checkpoint disappearing.
    await repo.clearResume(id);
    final cleared = (await repo.listActivities()).firstWhere(
      (ActivityListItem i) => i.id == id,
    );
    expect(cleared.isOpen, isFalse);
    expect(cleared.distanceM, 3400);
    expect(cleared.elapsedNanos, 900_000_000_000);
  });

  // Review I-1 part 3: ر123 makes an OPEN row print the checkpoint's measured
  // totals, but the checkpoint is written at a cadence, so it can LAG the row.
  // Both numbers are monotonic accumulators of the same activity, so the greater
  // is always a measured one and never an invention — and taking the max means a
  // stale checkpoint can no longer shrink what the list shows.
  test('an open row prints the greater of row-vs-checkpoint totals', () async {
    final id = await repo.insertActivity(
      uuid: 'uuid-lagging-checkpoint',
      sport: 'run',
      startWallMillis: 1_700_000_000_000,
    );
    // The row itself carries 500 m / 300 s. Written directly, deliberately NOT
    // through finishActivity, which would stamp `updated_at` and close the row:
    // this is the "row ahead of its checkpoint" state while still open.
    final stored =
        await (db.select(
          db.activities,
        )..where((t) => t.id.equals(id))).getSingle();
    await db.update(db.activities).replace(
      stored.copyWith(distanceM: 500, elapsedNanos: 300_000_000_000),
    );
    await repo.saveResume(
      activityId: id,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    final row = (await repo.listActivities()).firstWhere(
      (ActivityListItem i) => i.id == id,
    );
    expect(row.isOpen, isTrue, reason: 'no finishActivity ran, so ر121 applies');
    expect(row.distanceM, 500);
    expect(row.elapsedNanos, 300_000_000_000);
  });

  // Review I-1 part 2: the stop path's pair, as ONE transaction. Both effects
  // must be visible together — the totals AND the checkpoint removal — because
  // the state this replaces (one landed, one not) is the bug. The rollback half
  // is proven separately by sabotaging `clearResume` to throw: see
  // final-fix-report.md, «I-1: the transaction bites».
  test('finishAndClearResume writes the totals and removes the checkpoint', () async {
    final id = await repo.insertActivity(
      uuid: 'uuid-atomic',
      sport: 'run',
      startWallMillis: 1_700_000_000_000,
    );
    await repo.saveResume(
      activityId: id,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    await repo.finishAndClearResume(
      activityId: id,
      elapsedNanos: 900_000_000_000,
      distanceM: 3400,
      fixCount: 40,
      rejectedCount: 2,
      mockDetected: false,
    );

    // Effect 1 — the checkpoint is gone, so nothing can call this row open.
    expect(
      await repo.loadResume(),
      isNull,
      reason: 'clearResume landed inside the same transaction',
    );
    // Effect 2 — the row holds the real totals, and the closed marker with them.
    final row =
        await (db.select(
          db.activities,
        )..where((t) => t.id.equals(id))).getSingle();
    expect(row.distanceM, 3400);
    expect(row.elapsedNanos, 900_000_000_000);
    expect(row.fixCount, 40);
    expect(row.rejectedCount, 2);
    expect(
      row.updatedAt,
      isNotNull,
      reason: 'finishActivity stamps the finished marker (review I-1)',
    );

    // And the list agrees: closed, with its own totals.
    final item = (await repo.listActivities()).firstWhere(
      (ActivityListItem i) => i.id == id,
    );
    expect(item.isOpen, isFalse);
    expect(item.distanceM, 3400);
    expect(item.elapsedNanos, 900_000_000_000);
  });

  // Review I-1: the other half of atomicity, and the permanent proof that the
  // transaction is load-bearing. When the checkpoint removal fails, the totals
  // write must be UNDONE — otherwise the app lands in exactly the state this
  // round set out to destroy: a finished-looking row still named by a
  // checkpoint. Drop the `transaction()` and this test reports
  // `Expected: <0>  Actual: <3400.0>` (observed; see the fix-round report).
  test('a finishAndClearResume that cannot clear the checkpoint writes nothing', () async {
    final repo = _ClearResumeFailingRepo(db);
    final id = await repo.insertActivity(
      uuid: 'uuid-rollback',
      sport: 'run',
      startWallMillis: 1_700_000_000_000,
    );
    await repo.saveResume(
      activityId: id,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    await expectLater(
      repo.finishAndClearResume(
        activityId: id,
        elapsedNanos: 900_000_000_000,
        distanceM: 3400,
        fixCount: 40,
        rejectedCount: 2,
        mockDetected: false,
      ),
      throwsStateError,
    );

    final row =
        await (db.select(
          db.activities,
        )..where((t) => t.id.equals(id))).getSingle();
    expect(
      row.distanceM,
      0,
      reason: 'the totals write rolled back with the failed clear',
    );
    expect(row.elapsedNanos, 0);
    expect(
      row.updatedAt,
      isNull,
      reason: 'and so did the finished marker — nothing claims this row is closed',
    );
    // The safe outcome the controller's `try` documents: the checkpoint is
    // still there, so the next start resumes instead of stranding the session.
    expect(
      await repo.loadResume(),
      isNotNull,
      reason: 'the activity stays recoverable after the failed stop',
    );
  });
}
