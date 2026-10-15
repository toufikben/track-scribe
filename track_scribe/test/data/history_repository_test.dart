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
    // I-2: the three per-fix fields are asserted as lists, with values chosen
    // so a fixCount/rejectedCount swap (→ [0, 2, 1] vs [25, 7, 10]) or a
    // hard-coded `mockDetected: false` cannot pass.
    expect(items.map((i) => i.fixCount), [25, 7, 10]);
    expect(items.map((i) => i.rejectedCount), [0, 2, 1]);
    expect(items.map((i) => i.mockDetected), [true, false, false]);
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
    // The checkpoint table has no per-fix columns (database.dart:44-68), so
    // these stay the unfinalized row's defaults — exactly why the history
    // screen must not render them for an open row.
    expect(open.fixCount, 0);
    expect(open.rejectedCount, 0);
    expect(open.mockDetected, isFalse);

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
}
