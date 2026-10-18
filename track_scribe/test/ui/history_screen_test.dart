import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/format.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/import/gpx_track.dart';
import 'package:track_scribe/import/track_importer.dart';
import 'package:track_scribe/theme/palette.dart';
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
    // a `findsOneWidget` on the wrong row. The walk is seeded at 1020 m rather
    // than the brief's 1000 m because at exactly 1.00 km the pace equals the
    // duration by arithmetic (1000 s / 1.00 km = 16:40 /km), and the row's two
    // `Text("16:40")` widgets — time AND pace — made the brief's
    // `findsOneWidget` unsatisfiable (verified RED: "Found 2 widgets with text
    // 16:40 ... Which: is too many"). 1020 m still prints through the same
    // "1,0" token while its pace reads 16:20.
    final older = await seed(
      startWallMillis: 1_700_000_000_000,
      distanceM: 1020,
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
    // 6.40 km over 33:20, and 1.02 km over 16:40 — proof each row renders its
    // OWN row's totals, and the decimal separator is the token (','), never '.'.
    expect(find.textContaining('6,4'), findsOneWidget);
    expect(find.text('33:20'), findsOneWidget);
    expect(find.textContaining('1,0'), findsOneWidget);
    expect(find.text('16:40'), findsOneWidget);
    // I-3: the pace column's value. The walk's 1020 m / 1000 s is
    // `Format.pace(980.39…)` = `16:20` (the newer row's pace is
    // `Format.pace(312.5)` = `5:12`), a string no other column prints — so a
    // flipped pace formula or a deleted pace `_stat` is caught here. The
    // `--:--` branch is NOT reachable from any row this file seeds: every row
    // is at or above the 50 m guard (120, 1020, 6400 m), which is why the open
    // row below pins its real pace instead.
    expect(find.text('16:20'), findsOneWidget);
    // I-4: `Format.activityDate` must reach the screen, per row, from that
    // row's OWN startWallMillis. The label's hour/minute come from the local
    // time zone, so the expected value is derived by calling the function
    // itself on the seed's millis rather than a literal string: this keeps the
    // test zone-proof (a clock-dependent assertion is the one thing that must
    // not be introduced here) while a deleted date Text findsNothing, and a
    // cross-row swap makes each row's own date find nothing under its own key.
    expect(
      find.descendant(
        of: find.byKey(Key('history-row-$newer')),
        matching: find.text(Format.activityDate(1_800_000_000_000)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('history-row-$older')),
        matching: find.text(Format.activityDate(1_700_000_000_000)),
      ),
      findsOneWidget,
    );
    // M-1: "newest first", asserted on the vertical axis (RTL does not change
    // it). Ordering itself is already pinned in test/data/history_repository_
    // test.dart; this catches a screen-side re-shuffle only.
    expect(
      tester.getTopLeft(find.byKey(Key('history-row-$newer'))).dy,
      lessThan(tester.getTopLeft(find.byKey(Key('history-row-$older'))).dy),
    );
    // M-3: the older row's key is captured too, so a duplicate-key or
    // dropped-row bug cannot hide behind a single `findsOneWidget`.
    expect(find.byKey(Key('history-row-$older')), findsOneWidget);
    // ر120: climb_m is an unmeasured zero until ر11, so no row may print it.
    expect(find.textContaining('صعود'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty install says so instead of showing a blank list', (tester) async {
    await tester.pumpWidget(app());
    // I-1: the one place this screen may use the accent token (spec §5) is the
    // in-flight spinner. Without `pumpAndSettle` the read is still pending, so
    // this is the only way the loading branch is ever on screen — and the only
    // thing that notices if the accent (or the whole spinner) disappears.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      ).color,
      Palette.accent,
    );
    await tester.pumpAndSettle();

    expect(find.text('لا أنشطة بعد'), findsOneWidget);
    // M-2: the empty state's second line — the spec §7 «way out» half.
    expect(
      find.text('سجّل أول مسار من شاشة التسجيل ليظهر هنا'),
      findsOneWidget,
    );
    expect(find.byType(InkWell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read that fails shows the error branch, not an empty list', (tester) async {
    // The brief seeded this with a `NativeDatabase.memory()` closed BEFORE any
    // statement ran, asserting "the SELECT throws". Verified false twice: such
    // a database re-opens silently and the screen rendered the EMPTY branch
    // (verified RED: "Found 0 widgets with text تعذّر تحميل السجل"), and a
    // LazyDatabase whose opener always throws never delivers its rejection
    // under the fake-async binding (verified: the spinner pended to the 10-min
    // test timeout). What DOES throw is a database that was really used and
    // then closed: the next SELECT rejects with drift's own
    // "Can't re-open a database after closing it" — a genuine failing read on
    // a real AppDatabase, with no faked repository. A second DB, so the shared
    // `tearDown` never closes one that is already shut.
    final closed = AppDatabase(NativeDatabase.memory());
    await ActivityRepository(closed).insertActivity(
      uuid: 'closed-uuid',
      sport: 'run',
      startWallMillis: 1,
    );
    await closed.close();
    await tester.pumpWidget(app(through: closed));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر تحميل السجل'), findsOneWidget);
    expect(find.text('لا أنشطة بعد'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ر121: a killed session leaves a checkpoint behind. The row must be visible
  // AND marked, never presented as a finished activity.
  testWidgets('an activity still being recorded is marked, not hidden', (tester) async {
    // M-4: this is the only row carrying FOUR `Expanded` columns (the state
    // chip joins the three stats), and at the default 800×600 view that layout
    // has never been exercised. The same phone size the populated test pins.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

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
    // ر123: the «قيد التسجيل» row prints the checkpoint's MEASURED totals as
    // ordinary numbers — no dash, no zero, no special case. This is the only
    // assertion that covers the ruling on the surface it was written for.
    // Derived, not guessed: localeSepProvider is ',' (lib/state/
    // locale_providers.dart:6), so Format.distance(120, sep: ',') = `0,12`
    // and Format.duration(60e9 ns) = `01:00`. An `isOpen ? '—' : …` dash of
    // the open row fails the first of these.
    expect(find.textContaining('0,12'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    // I-3 (R19 guard): 120 m is AT OR ABOVE the 50 m guard, so the open row
    // must print a real pace, not `--:--`: 60 s / 0.12 km = 500 s/km →
    // Format.pace(500) = `8:20`. Pinned instead of a `--:--` assertion,
    // because no row this file seeds falls below the guard.
    expect(find.text('8:20'), findsOneWidget);
    // And it is inert: no route to replay, so no tap target (ر121).
    expect(tester.widget<InkWell>(find.byKey(Key('history-row-$live'))).onTap, isNull);
    expect(tester.takeException(), isNull);
  });

  // Review I-1: the user-visible half of the bug. A finished row that still has
  // a checkpoint (the stop path wrote the totals and died before clearing it)
  // used to be masked, labelled «قيد التسجيل» AND given `onTap: null` — the
  // recording existed but nothing could open it, and the recorder's own detail
  // button is already gone once the session resets.
  testWidgets('a finished activity with a surviving checkpoint opens on tap', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final id = await repo.insertActivity(
      uuid: 'uuid-orphan',
      sport: 'run',
      startWallMillis: 1_800_000_000_000,
    );
    await repo.saveResume(
      activityId: id,
      lastStored: StoredPoint(lat: 36.75, lon: 3.04, timeNanos: 0, accuracyM: 5, type: WaypointType.normal),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );
    await repo.finishActivity(
      activityId: id,
      elapsedNanos: 900_000_000_000,
      distanceM: 3400,
      fixCount: 40,
      rejectedCount: 2,
      mockDetected: false,
    );

    await tester.pumpWidget(app(through: db));
    await tester.pumpAndSettle();

    final row = find.byKey(Key('history-row-$id'));
    expect(row, findsOneWidget);
    // ر121 does NOT apply: this recording was stopped, not killed.
    expect(find.text('قيد التسجيل'), findsNothing);
    // The finished totals, not the stale checkpoint's: 3400 m → `3,40`,
    // 900 s → `15:00`, pace 900/3.4 = 264 s/km → `4:24` (derived from
    // lib/core/format.dart, the same derivation the populated test uses).
    expect(find.text('3,40'), findsWidgets);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('4:24'), findsOneWidget);
    expect(find.text('0,12'), findsNothing);
    expect(find.text('01:00'), findsNothing);
    // …and the row is live again.
    expect(tester.widget<InkWell>(row).onTap, isNotNull);

    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(
      tester.widget<ActivityDetailScreen>(find.byType(ActivityDetailScreen)).activityId,
      id,
    );
    expect(tester.takeException(), isNull);
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
    expect(tester.takeException(), isNull);
  });

  // R125 + ر99: an imported file is shown as what it is. Its row carries no
  // stated clock, so `elapsed_nanos` is the schema default 0 — an ABSENCE — and
  // the list must print «غير معروف» where a recording would print its own
  // measured time. Seeded through the real TrackImporter, not a hand-written
  // row, so the provenance column and the read that consumes it are both in
  // the path under test.
  testWidgets(
    'an imported activity is marked as imported and prints no invented duration',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      const fileStart = 1_700_000_000_000;
      final imported = await TrackImporter(db, repo).importTrack(
        ImportedTrack(
          points: const [
            ImportedPoint(lat: 36.75, lon: 3.04),
            ImportedPoint(lat: 36.76, lon: 3.05),
          ],
          rawType: 'run',
          sport: ImportSport.run,
          startWallMillis: null,
          rejectedPoints: 0,
          droppedTimes: 0,
        ),
        sport: ImportSport.run,
        startWallMillis: fileStart,
      );
      expect(imported.elapsedKnown, isFalse);
      final ownId = await seed(
        startWallMillis: 1_800_000_000_000,
        distanceM: 6400,
        elapsedNanos: 2_000_000_000_000,
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(Key('history-row-${imported.activityId}')), findsOneWidget);
      expect(find.byKey(Key('history-row-$ownId')), findsOneWidget);
      expect(find.text('مستورد'), findsOneWidget);
      expect(find.text('غير معروف'), findsOneWidget);
      expect(
        find.text('--:--'),
        findsOneWidget,
        reason:
            "the imported row's pace cell is the only `--:--`: a duration of 0 ns "
            'divided by its own distance is not a pace (R19 + R125)',
      );
      expect(
        find.text('00:00'),
        findsNothing,
        reason: 'the absence of a clock must not read as a zero-length activity',
      );
      expect(tester.takeException(), isNull);
    },
  );

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
