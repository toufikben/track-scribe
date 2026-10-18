import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_source.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';
import 'package:track_scribe/ui/history/history_screen.dart';

import '../support/stub_vector_style.dart';

// R80: a session now reads the resume checkpoint and writes points to sqlite;
// these tests drive the real app, so they pin the database to memory — never
// getApplicationDocumentsDirectory(). R86: home is AppGate, so the DB must be
// seeded with the onboarded flag or the app boots into PermissionScreen.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

Widget _appWithDb(AppDatabase db) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
  ],
  child: const TrackScribeApp(),
);

/// A throwaway summary so the pushed detail screen mounts without a repository
/// read: `activityDetailProvider` is overridden, which is the whole reason it is
/// a family (the detail tests already prove the screen renders from this).
ActivitySummary _detailSummary(int id) => ActivitySummary(
  id: id,
  sport: 'run',
  startWallMillis: 1700000000000,
  distanceM: 100,
  elapsedNanos: 60_000_000_000,
  source: kSourceRecorded,
  fixCount: 2,
  rejectedCount: 0,
  mockDetected: false,
  points: [
    StoredPoint(
      lat: 36.75,
      lon: 3.04,
      timeNanos: 0,
      accuracyM: 5,
      type: WaypointType.normal,
      altitudeM: 10,
    ),
    StoredPoint(
      lat: 36.7502,
      lon: 3.04,
      timeNanos: 1_000_000_000,
      accuracyM: 5,
      type: WaypointType.normal,
      altitudeM: 20,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BundledStyle style;

  // R104: a pushed detail screen watches `mapStyleProvider`; loading the real
  // bundled style would `rootBundle.load()` inside the fake-async zone and pend
  // forever, so the stub Style is read ONCE here (outside testWidgets) and
  // injected per-test — the pattern `detail_screen_test.dart` establishes.
  setUpAll(() async {
    style = await loadStubVectorStyle();
  });

  tearDownAll(() => style.dispose());

  testWidgets('layout B2: dominant map on top, stat panel below, RTL, dark', (
    tester,
  ) async {
    // R20: the tester.binding.window form is deprecated on Flutter 3.47.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(_appWithDb(db));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).last)
          .textDirection,
      TextDirection.rtl,
    );
    expect(find.text('المسافة · كم'), findsOneWidget);
    expect(find.text('جري'), findsOneWidget);
    expect(find.text('مشي'), findsOneWidget);
    expect(find.text('دراجة'), findsOneWidget);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Palette.bg,
    );

    // Layout contract (ر124, supersedes spec layout B): the map takes 60 % of
    // the body Column and the panel 40 % (Expanded flex 6 / 4). R104: the band
    // is now VectorMapBand — its rect is the flex-6 area, attribution included.
    final bodyColumn = tester
        .element(find.byType(VectorMapBand))
        .findAncestorWidgetOfExactType<Column>();
    expect(bodyColumn, isNotNull);
    final columnHeight = tester.getSize(find.byWidget(bodyColumn!)).height;
    final mapHeight = tester.getSize(find.byType(VectorMapBand)).height;
    expect(mapHeight, closeTo(columnHeight * 0.6, 1.0));

    // Before start the counters render real formatted values, not
    // placeholders. The distance appears twice (big number + panel row).
    expect(find.text('0,00'), findsNWidgets(2));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);

    // R53: start is NOT danger — Palette.text on Palette.surface.
    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'ابدأ التسجيل'),
    );
    final startStyle = startButton.style!;
    expect(
      startStyle.backgroundColor!.resolve(const <WidgetState>{}),
      Palette.surface,
    );
    expect(
      startStyle.foregroundColor!.resolve(const <WidgetState>{}),
      Palette.text,
    );
    expect(startStyle.minimumSize!.resolve(const <WidgetState>{})!.height, 56);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(seconds: 2));
    // R21 + Task 9a: pump drives the synthetic source's Timer.periodic (but
    // NOT its Stopwatch), so the fake 2 s delivers enough ≤ 35 m fixes to
    // cross the ر7 gate and reach `recording` — asserted only as the button
    // change, never as a specific non-zero distance.
    expect(find.text('إيقاف'), findsOneWidget);

    // R53: while recording, the stop button is danger-as-background carrying
    // Palette.text (the certified 6.08:1 pair), never danger as a foreground.
    final stopButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إيقاف'),
    );
    final stopStyle = stopButton.style!;
    expect(
      stopStyle.backgroundColor!.resolve(const <WidgetState>{}),
      Palette.danger,
    );
    expect(
      stopStyle.foregroundColor!.resolve(const <WidgetState>{}),
      Palette.text,
    );
    expect(stopStyle.minimumSize!.resolve(const <WidgetState>{})!.height, 56);

    // Stop the session so the synthetic source's periodic timer is cancelled
    // before the fake-async zone teardown (pending timers fail the test).
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });

  // Review I-3, spec §5 «احترام حجم الخط الديناميكي»: ر124 cut the stat panel
  // from 60 % of the body to 40 %, and nothing in `lib/` or `test/` had ever
  // referenced a text scaler. This is that panel's only dynamic-type guard: the
  // big number, the three-stat row and the 56 dp control must still fit the
  // flex-4 band when the user turns the system font up.
  //
  // 1.5 is Android's «Large», 2.0 is «Largest» — the top of the real slider.
  // The first caught a real defect: the three-stat Row overflowed by 97 dp on
  // the right, which `StatPanel._stat` now fixes with a bounded, scaled-down
  // cell.
  Future<void> pumpAtTextScale(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final db = await _seededDb();
    addTearDown(db.close);

    await tester.pumpWidget(_appWithDb(db));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the 40 % stat panel survives a 1.5x text scale (ر124 + §5)', (
    tester,
  ) async {
    await pumpAtTextScale(tester, 1.5);

    expect(tester.takeException(), isNull);
    // The panel is still the panel: its numbers and its wide control are on
    // screen, not pushed out by the enlarged text.
    expect(find.text('المسافة · كم'), findsOneWidget);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });

  testWidgets('the 40 % stat panel survives the 2.0x «Largest» text scale', (
    tester,
  ) async {
    await pumpAtTextScale(tester, 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('المسافة · كم'), findsOneWidget);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });

  testWidgets(
    'start is enabled, and Task 9a keeps it enabled through `starting` as a cancel',
    (tester) async {
      final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(_appWithDb(db));
      await tester.pump(const Duration(milliseconds: 400));
      final f = find.widgetWithText(ElevatedButton, 'ابدأ التسجيل');
      expect(
        tester.widget<ElevatedButton>(f).enabled,
        isTrue,
        reason: 'the ر7 gate (Task 9a) ships as an honest `starting` phase with '
            'a cancel button — there is deliberately no disabled start state',
      );
    },
  );

  testWidgets('screen rebuilds from the recording state machine', (
    tester,
  ) async {
    // Sanity: the widgets under test are the screen's own, so a full
    // start→stop cycle returns to the start label.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(_appWithDb(db));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('إيقاف'), findsOneWidget);
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });

  testWidgets('a second session starts after the first one stopped', (
    tester,
  ) async {
    // start → stop → start is the ordinary gesture of anyone recording twice
    // in one app session, with no restart in between.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(_appWithDb(db));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('إيقاف'), findsOneWidget);
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('إيقاف'),
      findsOneWidget,
      reason: 'the second session must reach recording, not stall in starting',
    );
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the post-stop «تفاصيل النشاط» button exists only for a session '
      'that stored a row', (tester) async {
    // Task 5's `lastActivityId` is the whole affordance: no button before a
    // recording has ever closed a row, one button the moment it does.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(_appWithDb(db));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('تفاصيل النشاط'),
      findsNothing,
      reason: 'a stopped app whose session never made a row has nothing to open',
    );

    await tester.tap(find.text('ابدأ التسجيل'));
    // ~0.14 m per fake 100 ms tick at 1.4 m/s, and the ر3 gate wants 6 m
    // (max(3, 2 × 3 m accuracy)) — 6 s of fake time is what lets one point be
    // stored, so the session really does close an activity row.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('إيقاف'), findsOneWidget);
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('detail-button')), findsOneWidget);
    expect(find.text('تفاصيل النشاط'), findsOneWidget);

    // And it goes away when a new session starts: the button belongs to the
    // activity that FINISHED, never to the live one (start clears the id).
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('detail-button')), findsNothing);
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the post-stop detail button pushes the activity detail screen', (
    tester,
  ) async {
    // The wire itself — `onPressed` -> Navigator.push -> ActivityDetailScreen —
    // the only line connecting the two screens. The two overrides are exactly
    // what the detail tests use to mount that screen safely (stub style loaded
    // in setUpAll, synthetic summary), so the push runs without awaiting a real
    // platform channel inside the fake-async zone (R104).
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
          activityDetailProvider.overrideWith((ref, id) => Future.value(_detailSummary(id))),
        ],
        child: const TrackScribeApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('detail-button')), findsOneWidget);
    expect(find.byType(ActivityDetailScreen), findsNothing);

    await tester.tap(find.byKey(const Key('detail-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ر119: history is reachable from the recorder without touching the layout.
  // The AppBar sits outside the 60/40 split that the measuring test above pins
  // (`mapHeight ≈ columnHeight * 0.6`) — so if this button had stolen body
  // height, THAT test would fail first. Nothing here re-pins a number that
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
    // The brief's single `pump(400 ms)` here fails: `Navigator.push` inserts its
    // OverlayEntry from a POST-frame callback, so the pushed route needs one
    // frame to exist before the 400 ms transition pump can build it. Measured
    // (probe run): tap → pump(400 ms) finds 0 HistoryScreen; tap → pump() →
    // pump(400 ms) finds it with its title and its empty state. The frame is
    // added, no assertion is weakened, and `pumpAndSettle` is deliberately NOT
    // used — the list's loading `CircularProgressIndicator` ticks forever under
    // the fake clock if the read has not landed, which is the pump-timeout the
    // brief rules out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // …and lands on the list, reading the SAME database — empty, because this
    // DB was seeded with nothing but the onboarded flag.
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('سجل الأنشطة'), findsOneWidget);
    expect(find.text('لا أنشطة بعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
