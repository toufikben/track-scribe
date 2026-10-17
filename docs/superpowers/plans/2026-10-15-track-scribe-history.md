# خطة 3: سجل الأنشطة — قائمة تاريخية داكنة من الجهاز وحده

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app the history it already promises: a screen that lists every recorded activity newest-first with its honest totals, and a row that opens the existing detail screen.

**Architecture:** One new repository read (`listActivities`) that touches only the `activities` row and the `resume` checkpoint — never `track_points`. One `autoDispose` provider per the ر116 residency ruling. One new screen (`HistoryScreen`) reusing the existing `Format` primitives, `Palette`/`TextTheme` tokens and `ActivityDetailScreen`. The entry point is an `AppBar` action on the recording screen, so layout B's 40/60 split is untouched.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, flutter_riverpod 3.4.3, drift 2.35.2. **No new package** — `intl` is deliberately not added (see ر118).

**Spec:** `docs/superpowers/specs/2026-10-09-route-recorder-dark-ui-design.md` §1 line 10 («ويعرض المسار تاريخيًا»), §4 (data), §5 (the approved design layer), §8 (test law). Plan 1 deferred this surface explicitly: `docs/superpowers/plans/2026-10-09-track-scribe-plan1-recorder-dark-ui.md:29` («ر11 … GPX/FIT export, **history screens**, light theme: out of Plan 1; each gets its own plan») and its hand-off list at line 1684.

---

## Global Constraints

(Every task's requirements implicitly include this section. Exact values verbatim.)

- **CI is the only APK builder.** Locally run only `flutter analyze` and `flutter test`; never `flutter build`. Device verification happens on the Realme via adb, and **never accept the device PIN**.
- **Everything stays local.** No network call, no analytics, no account, no new dependency, no external service.
- **Layout B is locked** (spec §5: «التخطيط: B — الخريطة 40% أعلى، لوحة أرقام تحتها، زر عريض وليس دائرة»). Nothing in this plan may change the `flex: 4` / `flex: 6` split, the chip/banner overlay positions, or the stop control.
  - **ر124 SUPERSEDES THE SPLIT IN THIS LINE (owner order 2026-10-16).** The owner then ordered «من الأحسن في واجهة الخريطة أن تكون الخريطة تحتل الجزء الأكبر من الواجهة والآخرين في أسفل الواجهة», and the app now ships Layout **B2**: map `flex: 6` on top, stat panel `flex: 4` below (`6b92226`, ruling recorded in `docs/ROADMAP.md` §ر124, device-measured 804/536 px of 1340 = 60.0 %/40.0 %). Read this constraint as *the split is locked at B2's 6/4* — a worker who reads only this line would call the shipped B2 a violation, so this pointer is the correction. The chip/banner overlay positions and the single wide ≥ 56 dp stop control remain locked exactly as written here.
- **Colour law** (spec §5): bg `#101315`, surface `#171B1E`, text `#F4F7F2`, secondary text `#9DA4A1`, accent `#C6FF3D` **only for the route line and the big number**, `danger` `#B42318` **reserved for stop**. Every new widget uses a `Palette` token or a `TextTheme` slot — no raw hex inside a widget file.
- **Contrast law is tested**, not narrated: any new text style must come from the theme or from `Palette.text` / `Palette.textSecondary`, both already certified in `test/theme/palette_contrast_test.dart`.
- **Touch targets ≥ 48 dp**, one-handed reach respected (spec §5).
- **Arabic-first, RTL** by explicit `Directionality` (R23) — no `flutter_localizations` anywhere.
- **Decimal separator is a token**: every formatted number passes `sep:` from `localeSepProvider`, never a hard-coded `,`.
- **ر1/R21 (wall clock is display-only):** `start_wall_millis` may order and label a row; it must never be subtracted to produce a duration.
- **Honesty law (§8, and ر99–ر102 precedent):** a number that was never measured is not printed. `climb_m` exists in the schema and is always 0 until ر11 (DEM) ships, so **no view in this plan may show climb**.
- **No fidelity claim** about the recorder comes out of this plan; it is a display surface.

## Rulings made for this plan (recorded before execution)

- **ر117 — the list reads totals, never points.** `listActivities()` returns a new `ActivityListItem` carrying the row's columns only. Rationale is the same measurement that closed ر116: a full track of a 30-minute run is hundreds of `StoredPoint` objects, and the 4 GB target device runs the tile raster cache in the same process. A list that loaded every track to print three numbers would re-open exactly the residency hole ر116 closed, one screen earlier. Cost if wrong: none — the detail screen already reads points per row id.
- **ر118 — hand-rolled Arabic date, not `intl`.** R23 already rejected the locale package and set `Directionality` by hand; pulling `intl` in for one date label would add locale data to an app that promises zero external machinery. Cost: the month list is ours to maintain (12 const strings, tested).
- **ر119 — the entry point is an AppBar action, not a bottom navigation bar.** A bottom bar would restructure the screen the owner approved as layout B and steal height from the 40/60 split. The AppBar already exists and is outside that split. Cost: one icon tap to reach history instead of one thumb tap on a bar — reversible later if the owner asks.
- **ر120 — no climb column until ر11 exists.** `climb_m` is a schema default of 0, and a row that prints «0 م صعود» for a real hill is a lie of the same family ر99–ر101 were written against.
- **ر121 — an activity that still has a `resume` checkpoint is listed and marked «قيد التسجيل», never hidden.** A ColorOS kill leaves such a row (that is ر12/R79's whole design). Hiding it would read as data loss to the user; printing it as a finished activity would present totals that `finishActivity` has not yet written. The marker is the honest third answer.
- **ر122 — no delete UI in this plan.** `is_deleted` is read (excluded) but never written; deleting a recording is irreversible and the owner has not asked for it. Cost: a user cannot prune the list yet.
- **ر123 — an open row prints the checkpoint's measured totals, never the unfinalized row's zeros** (Task 1 review, finding I-3). A never-finished activity still holds `distance_m = 0` / `elapsed_nanos = 0` in `activities` (`finishActivity` is what writes the real totals), while the `track_state` row `listActivities()` already loads for the open-set holds `distanceM` (cumulative) and `lastElapsedNanos` (R81's cross-session sum). So `listActivities()` returns those two from the checkpoint for `isOpen` rows: «قيد التسجيل» then shows 120 m · 1:00 — measured, one checkpoint stale at worst — instead of `0 م · 0:00`, an unmeasured zero the honesty law forbids. `fixCount` / `rejectedCount` / `mockDetected` have no checkpoint column, so they stay the unfinalized row's, which is why no view may render them for an open row. Cost if wrong: the row's distance lags the live session by the checkpoint cadence; the label discloses that it is not a finished activity.

## File structure

```
track_scribe/
  lib/data/activity_list_item.dart            # NEW  — the list's value type
  lib/data/activity_repository.dart           # EDIT — + listActivities()
  lib/core/format.dart                        # EDIT — + activityDate()
  lib/ui/history/history_screen.dart          # NEW  — provider + screen + rows
  lib/ui/recording/recording_screen.dart      # EDIT — AppBar action only
  test/data/history_repository_test.dart      # NEW
  test/core/format_test.dart                  # EDIT — date-label cases
  test/ui/history_screen_test.dart            # NEW
  test/ui/recording_screen_test.dart          # EDIT — the action navigates
```

---

### Task 1: The repository read (totals only, newest first)

**Files:**
- Create: `track_scribe/lib/data/activity_list_item.dart`
- Modify: `track_scribe/lib/data/activity_repository.dart` (add one method, after `loadActivityWithPoints`)
- Test: `track_scribe/test/data/history_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` tables `Activities`, `TrackState` (already generated in `database.g.dart`).
- Produces: `ActivityListItem` (fields below) and `Future<List<ActivityListItem>> ActivityRepository.listActivities()` — the only API Tasks 3–4 need.

- [ ] **Step 1: Write the value type**

Create `track_scribe/lib/data/activity_list_item.dart`:

```dart
/// One row of the history list (خطة 3 §1) — the activity's stored TOTALS and
/// nothing else.
///
/// ر117: this type exists to make the list's cost visible in the code. The
/// detail screen's `ActivitySummary` carries every `StoredPoint` of one
/// activity, which is correct there (one activity at a time, released with the
/// screen per ر116) and wrong here: a list read that returned summaries would
/// hold every track the user ever recorded alive at once, on a 4 GB target
/// whose tile raster cache wants the same memory.
class ActivityListItem {
  const ActivityListItem({
    required this.id,
    required this.sport,
    required this.startWallMillis,
    required this.distanceM,
    required this.elapsedNanos,
    required this.fixCount,
    required this.rejectedCount,
    required this.mockDetected,
    required this.isOpen,
  });

  final int id;
  final String sport;

  /// Display metadata only — the same contract as `ActivitySummary`'s field
  /// (ر1/R21): it orders and labels the list, and never becomes a duration.
  final int startWallMillis;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;
  final int rejectedCount;
  final bool mockDetected;

  /// True while a `resume` checkpoint still names this activity, i.e. the
  /// recording was paused or killed rather than stopped (ر12/R79). Its
  /// `distanceM`/`elapsedNanos` are then whatever the LAST stopped write put
  /// there, not the session's total, so the list marks the row «قيد التسجيل»
  /// instead of presenting it as finished (ر121).
  final bool isOpen;
}
```

- [ ] **Step 2: Write the failing tests**

Create `track_scribe/test/data/history_repository_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// A seed row with given start stamp and totals, written the way the recorder
/// writes them: insert, points, then finishActivity.
Future<int> _seed(
  ActivityRepository repo, {
  required int startWallMillis,
  double distanceM = 6400,
  int elapsedNanos = 2_000_000_000_000,
  String sport = 'run',
}) async {
  final id = await repo.insertActivity(
    uuid: 'uuid-$startWallMillis',
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
    fixCount: 1,
    rejectedCount: 0,
    mockDetected: false,
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
    await _seed(repo, startWallMillis: 1_700_000_000_000, distanceM: 1000);
    await _seed(repo, startWallMillis: 1_800_000_000_000, distanceM: 6400);
    await _seed(repo, startWallMillis: 1_750_000_000_000, distanceM: 300, sport: 'walk');

    final items = await repo.listActivities();
    expect(items.map((i) => i.startWallMillis), [
      1_800_000_000_000,
      1_750_000_000_000,
      1_700_000_000_000,
    ]);
    expect(items.map((i) => i.sport), ['run', 'walk', 'run']);
    expect(items.map((i) => i.distanceM), [6400, 300, 1000]);
    expect(items.first.elapsedNanos, 2_000_000_000_000);
    // Every field the row renders must be present; nothing else is invented.
    expect(items.first.isOpen, isFalse);
  });

  test('a soft-deleted activity is not listed', () async {
    final keep = await _seed(repo, startWallMillis: 1_700_000_000_000);
    final gone = await _seed(repo, startWallMillis: 1_800_000_000_000);
    await (db.update(db.activities)
          ..where((t) => t.id.equals(gone)))
        .write(const ActivitiesCompanion(isDeleted: Value(true)));

    final items = await repo.listActivities();
    expect(items.map((i) => i.id), [keep]);
  });

  // ر121: the checkpoint is what makes a row "still open" — a ColorOS kill
  // leaves the activity in the table, and hiding it would read as data loss.
  test('the activity a resume checkpoint still names is marked open', () async {
    final closed = await _seed(repo, startWallMillis: 1_700_000_000_000);
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

    // And closing it removes the marker — the same checkpoint row the recorder
    // clears at stop.
    await repo.clearResume(live);
    final after = await repo.listActivities();
    expect(after.firstWhere((ActivityListItem i) => i.id == live).isOpen, isFalse);
  });
}
```

- [ ] **Step 3: Run them to make sure they fail for the right reason**

Run: `cd track_scribe && /c/src/flutter/bin/flutter test test/data/history_repository_test.dart`
Expected: a compile error naming `listActivities` (`The method 'listActivities' isn't defined for the type 'ActivityRepository'`) — not a assertion failure, not a timeout. Capture the output; it goes in the report.

- [ ] **Step 4: Implement the read**

Add to `track_scribe/lib/data/activity_repository.dart`, after `loadActivityWithPoints`, and import `activity_list_item.dart` at the top of the file:

```dart
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
  /// checkpoint to learn which of them is still open (ر121). `track_points` is
  /// never opened here — that is the whole point of the return type.
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
    final openIds = {
      for (final s in await (_db.select(
        _db.trackState,
      )..where((t) => t.key.equals('resume'))).get())
        s.activityId,
    };
    return [
      for (final r in rows)
        ActivityListItem(
          id: r.id,
          sport: r.sport,
          startWallMillis: r.startWallMillis,
          distanceM: r.distanceM,
          elapsedNanos: r.elapsedNanos,
          fixCount: r.fixCount,
          rejectedCount: r.rejectedCount,
          mockDetected: r.mockDetected,
          isOpen: openIds.contains(r.id),
        ),
    ];
  }
```

- [ ] **Step 5: Run the file again, then the whole suite**

> **Amended by ر123 (Task 1 review, finding I-3).** The block above is what shipped in
> `4fb38c5`; it reports an open activity's totals from the `activities` row, which for a
> never-finished activity holds the unmeasured zeros. The fix round after this review
> replaces `openIds` (a set) with a checkpoint map and takes `distanceM` / `elapsedNanos`
> from `checkpoints[r.id]` for `isOpen` rows, adds a fifth test for the `id DESC` tie-break,
> and varies `fixCount` / `rejectedCount` / `mockDetected` per seed so all nine fields are
> asserted. Task 3 consumes the signatures exactly as written above — the numbers behind
> `isOpen` rows change, the contract does not.

Run: `flutter test test/data/history_repository_test.dart` → expect 4 passes.
Run: `flutter test` → expect **203+ passing** (199 today + 4 new), 1 skipped, `All tests passed!`.
Run: `flutter analyze` → `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd track_scribe
git add lib/data/activity_list_item.dart lib/data/activity_repository.dart test/data/history_repository_test.dart
git commit -m "feat(history): list recorded activities by totals, newest first (خطة 3 task 1)"
```

---

### Task 2: The Arabic date label (`Format.activityDate`)

**Files:**
- Modify: `track_scribe/lib/core/format.dart`
- Test: `track_scribe/test/core/format_test.dart`

**Interfaces:**
- Consumes: nothing outside `dart:core`.
- Produces: `static String Format.activityDate(int startWallMillis, {DateTime? now})` — the string Task 3 prints in each row.

- [ ] **Step 1: Write the failing tests** (append to `test/core/format_test.dart`)

```dart
  // ر118: the month names are ours, not `intl`'s — the app rejected the locale
  // package in R23 and this label is the only date it needs.
  group('activityDate', () {
    test('prints day, Arabic month and year with a 24-hour clock', () {
      final stamp = DateTime(2026, 10, 15, 21, 33).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 11, 2, 9)),
        '15 أكتوبر 2026 · 21:33',
      );
    });

    test('single-digit day and minute are not zero-padded in the day, padded in the clock', () {
      final stamp = DateTime(2026, 4, 5, 7, 3).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 4, 20)),
        '5 أبريل 2026 · 07:03',
      );
    });

    // «اليوم»/«أمس» compare CALENDAR days: 23:50 → 00:10 is one day apart, not
    // 20 minutes, and the row must not claim an old activity happened today.
    test('today and yesterday use words, keyed on the calendar day', () {
      final lateNight = DateTime(2026, 10, 15, 23, 50).millisecondsSinceEpoch;
      expect(Format.activityDate(lateNight, now: DateTime(2026, 10, 15, 23, 55)), 'اليوم · 23:50');
      expect(Format.activityDate(lateNight, now: DateTime(2026, 10, 16, 0, 10)), 'أمس · 23:50');
      expect(
        Format.activityDate(lateNight, now: DateTime(2026, 10, 17)),
        '15 أكتوبر 2026 · 23:50',
      );
    });

    test('a stamp from twelve months back still resolves its month', () {
      final stamp = DateTime(2025, 10, 15, 8, 0).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 10, 15)),
        '15 أكتوبر 2025 · 08:00',
      );
    });

    test('a future stamp is not called today', () {
      final stamp = DateTime(2026, 10, 16, 9).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 10, 15)),
        '16 أكتوبر 2026 · 09:00',
      );
    });

    test('now defaults to the device clock', () {
      expect(Format.activityDate(DateTime.now().millisecondsSinceEpoch), startsWith('اليوم'));
    });
  });
```

Run: `flutter test test/core/format_test.dart` → expect FAIL, `The method 'activityDate' isn't defined for the type 'Format'`.

- [ ] **Step 2: Implement**

Add to the `Format` class in `track_scribe/lib/core/format.dart`:

```dart
  /// The Arabic month names in calendar order (ر118). Hand-rolled because the
  /// app has no locale package — R23 already rejects `flutter_localizations`
  /// for the same reason, and adding `intl` for one label would put locale
  /// data into an app whose whole promise is that nothing is fetched.
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// A start stamp as `15 أكتوبر 2026 · 21:33`, or `اليوم` / `أمس` for the two
  /// most recent CALENDAR days.
  ///
  /// ر1/R21 applies to this function in full: the wall clock is read to label
  /// and order a row, never to produce a duration. The day difference below
  /// chooses which WORD to print and nothing else — which is why it compares
  /// midnight-to-midnight `DateTime`s instead of subtracting the two stamps
  /// (23:50 recorded, 00:10 read is one day ago, not twenty minutes ago).
  ///
  /// `now` is injectable so the test does not depend on when it runs.
  static String activityDate(int startWallMillis, {DateTime? now}) {
    final start = DateTime.fromMillisecondsSinceEpoch(startWallMillis);
    final today = now ?? DateTime.now();
    final dayDiff = DateTime(today.year, today.month, today.day).difference(
      DateTime(start.year, start.month, start.day),
    );
    final int days = dayDiff.inDays;
    final when = days == 0
        ? 'اليوم'
        : days == 1
        ? 'أمس'
        : '${start.day} ${_monthsAr[start.month - 1]} ${start.year}';
    return '$when · ${_pad(start.hour)}:${_pad(start.minute)}';
  }
```

- [ ] **Step 3: Verify**

Run: `flutter test test/core/format_test.dart` → all pass.
Run: `flutter test` → `All tests passed!` (6 new since Task 1's count). `flutter analyze` → `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/format.dart test/core/format_test.dart
git commit -m "feat(history): Arabic activity date label without a locale package (خطة 3 task 2)"
```

---

### Task 3: The history screen

**Files:**
- Create: `track_scribe/lib/ui/history/history_screen.dart`
- Test: `track_scribe/test/ui/history_screen_test.dart`

**Interfaces:**
- Consumes: `ActivityRepository.listActivities()` (Task 1), `Format.activityDate` (Task 2), `activityRepositoryProvider`, `localeSepProvider`, `ActivityDetailScreen(activityId: int)`.
- Produces: `final historyProvider` (`FutureProvider.autoDispose<List<ActivityListItem>>`), `class HistoryScreen extends ConsumerWidget`, and the key `Key('history-row-<id>')` each row carries — Task 4 and the device session both tap by it.

- [ ] **Step 1: Write the failing widget tests**

Create `track_scribe/test/ui/history_screen_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';
import 'package:track_scribe/ui/history/history_screen.dart';

import '../support/stub_vector_style.dart';

/// A repo that counts list reads — the ر116 technique: the cache's lifetime is
/// asserted by behaviour, never by asking Riverpod about a private flag.
class _CountingRepo extends ActivityRepository {
  _CountingRepo(super.db);
  int listReads = 0;
  @override
  Future<List<ActivityListItem>> listActivities() {
    listReads++;
    return super.listActivities();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // R104, already learned the hard way: a pushed detail screen watches
  // `mapStyleProvider`, and the real one pends forever under `testWidgets`
  // (rootBundle + path_provider have no platform here). The same stub the
  // recording-screen test installs therefore goes in every app pumped below —
  // it costs nothing on the history screen itself and is required by its
  // navigation test.
  late BundledStyle style;
  setUpAll(() async => style = await loadStubVectorStyle());
  tearDownAll(() => style.dispose());

  late AppDatabase db;
  late ActivityRepository repo;

  Future<int> seed({
    required int startWallMillis,
    required double distanceM,
    required int elapsedNanos,
    String sport = 'run',
  }) async {
    final id = await repo.insertActivity(
      uuid: 'uuid-$startWallMillis',
      sport: sport,
      startWallMillis: startWallMillis,
    );
    await repo.appendPoints(id, [
      StoredPoint(lat: 36.75, lon: 3.04, timeNanos: 0, accuracyM: 5, type: WaypointType.normal),
    ]);
    await repo.finishActivity(
      activityId: id,
      elapsedNanos: elapsedNanos,
      distanceM: distanceM,
      fixCount: 1,
      rejectedCount: 0,
      mockDetected: false,
    );
    return id;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
  });
  tearDown(() => db.close());

  Widget app({AppDatabase? through}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(through ?? db),
      mapStyleProvider.overrideWith((ref) => Future.value(style)),
    ],
    child: MaterialApp(home: const HistoryScreen()),
  );

  testWidgets('shows one row per activity, newest first, with its totals', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    // Distinct totals on purpose: two rows printing the same number would pass
    // a `findsOneWidget` on the wrong row.
    await seed(
      startWallMillis: 1_700_000_000_000,
      distanceM: 1000,
      elapsedNanos: 1_000_000_000_000,
      sport: 'walk',
    );
    final newer = await seed(
      startWallMillis: 1_800_000_000_000,
      distanceM: 6400,
      elapsedNanos: 2_000_000_000_000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('سجل الأنشطة'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
    expect(find.byKey(Key('history-row-$newer')), findsOneWidget);
    expect(find.text('جري'), findsOneWidget);
    expect(find.text('مشي'), findsOneWidget);
    // 6.40 km over 33:20, and 1.00 km over 16:40 — proof each row renders its
    // OWN row's totals, and the decimal separator is the token (','), never '.'.
    expect(find.textContaining('6,4'), findsOneWidget);
    expect(find.text('33:20'), findsOneWidget);
    expect(find.textContaining('1,0'), findsOneWidget);
    expect(find.text('16:40'), findsOneWidget);
    // ر120: climb_m is an unmeasured zero until ر11, so no row may print it.
    expect(find.textContaining('صعود'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty install says so instead of showing a blank list', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('لا أنشطة بعد'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read that fails shows the error branch, not an empty list', (tester) async {
    // A database closed BEFORE the screen reads it: the SELECT throws, which is
    // the only way to reach this branch without faking the repository. A second
    // DB, so `tearDown` never closes one that is already shut.
    final closed = AppDatabase(NativeDatabase.memory());
    await closed.close();
    await tester.pumpWidget(app(through: closed));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر تحميل السجل'), findsOneWidget);
    expect(find.text('لا أنشطة بعد'), findsNothing);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 1b: the rest of the same file** (still inside that `main()`)

```dart
  // ر121: a killed session leaves a checkpoint behind. The row must be visible
  // AND marked, never presented as a finished activity.
  testWidgets('an activity still being recorded is marked, not hidden', (tester) async {
    final live = await repo.insertActivity(
      uuid: 'uuid-live',
      sport: 'bike',
      startWallMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.saveResume(
      activityId: live,
      lastStored: StoredPoint(lat: 36.75, lon: 3.04, timeNanos: 0, accuracyM: 5, type: WaypointType.normal),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(Key('history-row-$live')), findsOneWidget);
    expect(find.text('قيد التسجيل'), findsOneWidget);
    expect(find.text('دراجة'), findsOneWidget);
    // And it is inert: no route to replay, so no tap target (ر121).
    expect(tester.widget<InkWell>(find.byKey(Key('history-row-$live'))).onTap, isNull);
  });

  testWidgets('tapping a row opens that activity on the detail screen', (tester) async {
    final id = await seed(
      startWallMillis: 1_800_000_000_000,
      distanceM: 6400,
      elapsedNanos: 2_000_000_000_000,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('history-row-$id')));
    await tester.pumpAndSettle();

    final detail = tester.widget<ActivityDetailScreen>(find.byType(ActivityDetailScreen));
    expect(detail.activityId, id);
    expect(find.text('تفاصيل النشاط'), findsOneWidget);
  });

  // ر117 + ر116: the list's value is released when the screen leaves, so
  // re-entering reads afresh — and the read is the totals SELECT, never a
  // point list.
  test('the list value is released when the last listener leaves', () async {
    final counting = _CountingRepo(db);
    final container = ProviderContainer(
      overrides: [activityRepositoryProvider.overrideWithValue(counting)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(historyProvider, (_, _) {});
    await container.read(historyProvider.future);
    expect(counting.listReads, 1);
    await container.read(historyProvider.future);
    expect(counting.listReads, 1, reason: 'still-listening reads are cached');

    sub.close();
    await container.pump();

    final again = container.listen(historyProvider, (_, _) {});
    await container.read(historyProvider.future);
    expect(container.read(historyProvider).value, isNotNull);
    expect(counting.listReads, 2, reason: 'the list must not outlive the screen');
    again.close();
  });
}
```

Run: `flutter test test/ui/history_screen_test.dart` → expect FAIL: `Target of URI doesn't exist: '.../history_screen.dart'`.

- [ ] **Step 2: Implement the screen**

Create `track_scribe/lib/ui/history/history_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/core/format.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/state/locale_providers.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';

/// The history list read (خطة 3).
///
/// `autoDispose` for the reason ر116 ruled on for the detail screen: the
/// screen is this provider's only listener, and re-entering the list must show
/// a recording that ended while the user was elsewhere. The value here is small
/// (totals only, ر117), so the cost of re-reading is two local SELECTs.
///
/// `retry: null` for the reason documented on `mapStyleProvider` (R104):
/// Riverpod 3's default retry would re-run a failed read for ~38 s with the
/// state stuck in AsyncLoading, so the error branch would be unreachable —
/// least of all inside `testWidgets`, whose fake clock owns every timer.
final historyProvider = FutureProvider.autoDispose<List<ActivityListItem>>(
  (ref) => ref.watch(activityRepositoryProvider).listActivities(),
  retry: (retryCount, error) => null,
);

/// Every activity this install recorded, newest first (spec §1 «ويعرض المسار
/// تاريخيًا»). No map, no tiles, no platform channel on this screen — which is
/// why its tests need no style stub.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(historyProvider);
    final sep = ref.watch(localeSepProvider);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        title: Text('سجل الأنشطة', style: Theme.of(context).textTheme.titleLarge),
      ),
      // R23: RTL is set here explicitly — the app has no locale package.
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: items.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Palette.accent),
          ),
          error: (_, _) => const Center(
            child: Text(
              'تعذّر تحميل السجل',
              style: TextStyle(color: Palette.textSecondary),
            ),
          ),
          data: (list) => list.isEmpty
              ? const _NoActivities()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Palette.surface,
                  ),
                  itemBuilder: (_, i) =>
                      _ActivityRow(item: list[i], sep: sep),
                ),
        ),
      ),
    );
  }
}

/// The empty install. Worded as a fact plus the way out — the spec §7 rule for
/// every "nothing to show" state: never a silent blank.
class _NoActivities extends StatelessWidget {
  const _NoActivities();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('لا أنشطة بعد', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'سجّل أول مسار من شاشة التسجيل ليظهر هنا',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.textSecondary),
        ),
      ],
    ),
  );
}

/// Sport → (word, icon). The words are `SportChips`' exactly — one product, one
/// vocabulary (مشي / جري / دراجة).
(String, IconData) _sport(Sport s) => switch (s) {
  Sport.walk => ('مشي', Icons.directions_walk),
  Sport.bike => ('دراجة', Icons.two_wheeler),
  Sport.run => ('جري', Icons.directions_run),
};

/// One activity. The icon and the three numbers are all read from the row's own
/// columns; nothing is recomputed from the wall clock (ر1).
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.sep});

  final ActivityListItem item;
  final String sep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final (label, icon) = _sport(Sport.values.byName(item.sport));
    // The same R19 rule the live panel applies: pace is meaningless below 50 m
    // and prints `--:--` rather than a number invented from a short track.
    final paceSecPerKm = item.distanceM < 50
        ? null
        : (item.elapsedNanos / 1e9) / (item.distanceM / 1000);

    return InkWell(
      key: Key('history-row-${item.id}'),
      // ر121: an open recording has no route to replay yet — its points are in
      // the checkpoint's activity, and its totals are not final. Tapping it
      // would open a screen whose every number lags the recorder.
      onTap: item.isOpen
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ActivityDetailScreen(activityId: item.id),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Palette.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: theme.titleMedium)),
                Text(Format.activityDate(item.startWallMillis),
                    style: theme.labelMedium),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _stat('كم', Format.distance(item.distanceM, sep: sep), theme),
                _stat('الوقت', Format.duration(item.elapsedNanos), theme),
                _stat(
                  'الإيقاع',
                  paceSecPerKm == null
                      ? '--:--'
                      : Format.pace(paceSecPerKm, sep: sep),
                  theme,
                ),
                if (item.isOpen) _stat('الحالة', 'قيد التسجيل', theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, TextTheme theme) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: theme.bodyMedium),
      ],
    ),
  );
}
```

Notes the implementer must NOT silently change:
- No `Palette.accent` anywhere in this file except the loading spinner (spec §5 reserves accent for the route and the big number).
- No raw hex; the separator `Divider` uses `Palette.surface`.
- `Sport.values.byName` is the same call the detail screen already makes on the same column — an unknown sport throws, it is not swallowed into a default row.

- [ ] **Step 3: Verify**

Run: `flutter test test/ui/history_screen_test.dart` → all pass.
Run: `flutter test` → `All tests passed!` (6 more since Task 2). `flutter analyze` → `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/ui/history/history_screen.dart test/ui/history_screen_test.dart
git commit -m "feat(history): dark RTL activity list that opens the detail screen (خطة 3 task 3)"
```

---

### Task 4: The entry point, and the evidence record

**Files:**
- Modify: `track_scribe/lib/ui/recording/recording_screen.dart` (AppBar `actions` only)
- Test: `track_scribe/test/ui/recording_screen_test.dart`
- Modify: `docs/ROADMAP.md`, `docs/superpowers/evidence/2026-10-12-map-implementation.md`

**Interfaces:**
- Consumes: `HistoryScreen` (Task 3).
- Produces: `Key('history-button')` on the recording screen's AppBar — the device session taps it by that key.

- [ ] **Step 1: Write the failing test** — append this `testWidgets` inside the existing `main()` of `test/ui/recording_screen_test.dart`, reusing that file's `_seededDb()`, its `style` from `setUpAll`, and the exact `ProviderScope`-override shape its detail-button test (line 280) already uses:

```dart
  // ر119: history is reachable from the recorder without touching layout B.
  // The AppBar sits outside the 40/60 split, which the test at line 110 already
  // measures (`mapHeight ≈ columnHeight * 0.4`) — so if this button had stolen
  // body height, THAT test would fail first. Nothing here re-pins a number that
  // is already pinned; it pins the wire.
  testWidgets('the app bar opens the activity history', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mapStyleProvider.overrideWith((ref) => Future.value(style)),
        ],
        child: const TrackScribeApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // On a fresh install the recorder's own AppBar gains one action…
    expect(find.byKey(const Key('history-button')), findsOneWidget);
    expect(find.byType(HistoryScreen), findsNothing);

    await tester.tap(find.byKey(const Key('history-button')));
    await tester.pump(const Duration(milliseconds: 400));

    // …and lands on the list, reading the SAME database — empty, because this
    // DB was seeded with nothing but the onboarded flag.
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('سجل الأنشطة'), findsOneWidget);
    expect(find.text('لا أنشطة بعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

Add `import 'package:track_scribe/ui/history/history_screen.dart';` to that file. The test must fail BEFORE the lib edit with a "no widget with key history-button" finder error — not with a pump timeout, and not on the empty-state line. Capture the output for the report.

- [ ] **Step 2: Add the action**

In `track_scribe/lib/ui/recording/recording_screen.dart`, import `package:track_scribe/ui/history/history_screen.dart` and extend the existing `AppBar` with:

```dart
        actions: [
          IconButton(
            key: const Key('history-button'),
            tooltip: 'سجل الأنشطة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            icon: const Icon(Icons.history),
          ),
        ],
```

Nothing else in the file changes — no re-parenting of the body, no padding edit.

- [ ] **Step 3: Verify the whole gate**

Run: `flutter test` → `All tests passed!`, 0 failures, 1 skip.
Run: `flutter analyze` → `No issues found!`

- [ ] **Step 4: Push and watch CI**

```bash
git add -A && git commit -m "feat(history): reach the activity list from the recorder (خطة 3 task 4)"
git push origin plan1-recorder-dark-ui
```
Then `gh run list --limit 3` / `gh run watch <id>` on toufikben/track-scribe. Record the run id, the printed test count and the analyze line. The APK artifact is the build the next device session installs — say which run produced it.

- [ ] **Step 5: Documentation with numbers, not adjectives**

- `docs/ROADMAP.md`: append a «خطة 3: سجل الأنشطة» section — what ships, the ruling numbers (ر117–ر122), the test count before→after, the CI run id, and one plainly-marked «غير مُشغّل على الجهاز» line (the list has never been seen on the Realme).
- `docs/superpowers/evidence/2026-10-12-map-implementation.md` §2: update the number chain to the new count with its run id, the same way ر116 was recorded.
- No claim about distance accuracy, tiles, or video changes because of this plan.

---

## Self-review (written before execution)

- **Spec coverage:** §1 «ويعرض المسار تاريخيًا» → Tasks 1–4. §5 (design layer) → the token rules in Global Constraints + the no-accent note. §7 (error table) → the error and empty branches are both tested. §4 `is_deleted` (ناعم) → Task 1 excludes it; ر122 says writing it is out of scope. §8 → every claim is a test, and the device leg is named as un-run.
- **Placeholders:** none — every code block is the file's content. The one thing a step does not spell out is where to paste it in `test/ui/recording_screen_test.dart`, because that file owns the DB-seeding helper and the style stub; the plan names both by their real identifiers (`_seededDb()`, `style`) rather than inventing a second setup.
- **Type consistency:** `ActivityListItem` fields are exactly the names Task 3 reads; `listActivities()` appears in Task 1's implementation, Task 3's provider and Task 3's counting repo with the same signature; `Format.activityDate` is defined in Task 2 and called in Task 3 with the same named parameter.
- **Deferred on purpose (not gaps in this plan):** ر11 DEM climb (ر120 blocks the column), GPX/FIT/CSV export, delete UI (ر122), a settings surface, the light/sunlight token layer.
