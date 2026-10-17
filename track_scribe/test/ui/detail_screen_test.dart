import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/export_format.dart';
import 'package:track_scribe/export/track_exporter.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';
import 'package:track_scribe/ui/detail/elevation_strip.dart';
import 'package:track_scribe/ui/detail/graded_route_layer.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';

import '../support/stub_vector_style.dart';

/// One point of the seed route: ~22 m of latitude per step, monotonic time,
/// altitude from the caller (R78 stores what the fix measured, NULL if it did
/// not).
StoredPoint _p({
  required double lat,
  required int t,
  double? alt,
  WaypointType type = WaypointType.normal,
}) => StoredPoint(
  lat: lat,
  lon: 3.04,
  timeNanos: t,
  accuracyM: 5,
  type: type,
  altitudeM: alt,
);

/// A synthetic summary for the override path — no database involved, which is
/// why `activityDetailProvider` is a family.
ActivitySummary _synthetic({required List<StoredPoint> points, int id = 7}) =>
    ActivitySummary(
      id: id,
      sport: 'run',
      startWallMillis: 1700000000000,
      distanceM: 6400,
      elapsedNanos: 2_000_000_000_000,
      fixCount: points.length,
      rejectedCount: 0,
      mockDetected: false,
      points: points,
    );

/// ر116: the same repository, with the detail read counted, so the CACHE's
/// lifetime becomes a measured fact instead of a claim about Riverpod.
class _CountingRepo extends ActivityRepository {
  _CountingRepo(super.db);

  int reads = 0;

  @override
  Future<ActivitySummary?> loadActivityWithPoints(int activityId) {
    reads++;
    return super.loadActivityWithPoints(activityId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BundledStyle style;

  // R104: `rootBundle.load()` and the path_provider channel both pend forever
  // under the fake-async binding, so the loaded-map branch is only reachable
  // with a Style read OUTSIDE testWidgets and `mapStyleProvider` overridden —
  // exactly the pattern `vector_map_band_test.dart` established.
  setUpAll(() async {
    style = await loadStubVectorStyle();
  });

  tearDownAll(() => style.dispose());

  late AppDatabase db;
  late ActivityRepository repo;
  late int seededId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
    seededId = await repo.insertActivity(
      uuid: 'act-detail-test',
      sport: 'run',
      startWallMillis: 1700000000000,
    );
    await repo.appendPoints(seededId, [
      _p(lat: 36.7500, t: 0, alt: 10),
      _p(lat: 36.7502, t: 1_000_000_000, alt: 20),
      _p(lat: 36.7504, t: 2_000_000_000, alt: 30),
    ]);
    await repo.finishActivity(
      activityId: seededId,
      elapsedNanos: 2_000_000_000_000,
      distanceM: 6400,
      fixCount: 3,
      rejectedCount: 0,
      mockDetected: false,
    );
  });

  tearDown(() => db.close());

  /// The production wiring: the real (in-memory, seeded) repository behind
  /// `appDatabaseProvider`, so the read under test is
  /// `activityDetailProvider → loadActivityWithPoints`, not a stub.
  Widget seededApp({required int activityId}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      mapStyleProvider.overrideWith((ref) => Future.value(style)),
    ],
    child: MaterialApp(home: ActivityDetailScreen(activityId: activityId)),
  );

  testWidgets('renders stats, graded route, thickness chooser, elevation strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(seededApp(activityId: seededId));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل النشاط'), findsOneWidget);
    expect(find.byType(StatPanel), findsOneWidget);
    expect(find.byType(GradedRouteLayer), findsOneWidget);
    expect(find.byType(ElevationStrip), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('رفيع'), findsOneWidget);
    expect(find.text('غليظ'), findsOneWidget);
    // The attribution law is per-view, not per-band (plan §Global Constraints).
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    // 6.40 km over 33 min is what the seeded totals format to — proof the
    // screen renders the row's totals, not zeros.
    expect(find.textContaining('6,4'), findsWidgets);

    // The default weight is the middle segment, and the layer reads it.
    expect(
      tester.widget<GradedRouteLayer>(find.byType(GradedRouteLayer)).strokeWidth,
      5,
    );

    // thickness choice changes the layer's strokeWidth without error
    await tester.tap(find.text('رفيع'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GradedRouteLayer>(find.byType(GradedRouteLayer)).strokeWidth,
      3,
    );
    await tester.tap(find.text('غليظ'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GradedRouteLayer>(find.byType(GradedRouteLayer)).strokeWidth,
      8,
    );
    expect(tester.takeException(), isNull);
  });

  // ر107 review I-2: the replay map's camera ceiling must be the SAME shared
  // display ceiling the recording band uses. A pack ceiling is a DATA ceiling
  // (the provider clamps to it, core/tile_zoom.dart); capping the camera at 14
  // also clamps the one-point fit's `CameraFit.coordinates(maxZoom: 16)` below,
  // making it dead configuration.
  testWidgets('the replay map pins its display ceiling and owns its opaque fill', (
    tester,
  ) async {
    await tester.pumpWidget(seededApp(activityId: seededId));
    await tester.pumpAndSettle();

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.maxZoom, kMapDisplayMaxZoom);
    expect(
      options.maxZoom,
      greaterThan(style.maximumZoom.toDouble()),
      reason: 'the detail screen must not sit at a shallower ceiling than the band',
    );
    // R114: the stacked theme carries no `background` layer, so this option is
    // the ONLY thing that makes the replay map opaque. Left unpinned, a future
    // edit could drop it and paint the page's background through the map.
    expect(options.backgroundColor, Palette.bg);
  });

  testWidgets('shows the load error state for a missing activity', (tester) async {
    // An empty DB: `loadActivityWithPoints` returns null for row 999 and the
    // family turns that into its own error, which is what the error branch is
    // written against. No platform work involved — this completes in fake time.
    await tester.pumpWidget(seededApp(activityId: 999));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر تحميل النشاط'), findsOneWidget);
    expect(find.byType(GradedRouteLayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a route with no measured altitude says so, on the grid fallback', (
    tester,
  ) async {
    // The synthetic-injection path the family exists for: no repository read at
    // all, and the style provider throws, so both fallbacks are proven together.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith(
            (ref) => Future<BundledStyle>.error(StateError('no tiles')),
          ),
          activityDetailProvider.overrideWith(
            (ref, id) => Future.value(
              _synthetic(points: [_p(lat: 36.75, t: 0), _p(lat: 36.7502, t: 1_000_000_000)]),
            ),
          ),
        ],
        child: MaterialApp(home: ActivityDetailScreen(activityId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridBasemap), findsOneWidget);
    expect(find.text('لا توجد بيانات ارتفاع'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-point route still fits the camera without throwing', (
    tester,
  ) async {
    // The degenerate branch of `initialCameraFit`: nothing to bound, so the map
    // centres on the single point. `LatLngBounds.fromPoints` of one point would
    // be a zero-area fit, and flutter_map 8.3.2 fits a LIST of coordinates here.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith((ref) => Future.value(style)),
          activityDetailProvider.overrideWith(
            (ref, id) => Future.value(_synthetic(points: [_p(lat: 36.75, t: 0, alt: 12)])),
          ),
        ],
        child: MaterialApp(home: ActivityDetailScreen(activityId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(GradedRouteLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ر115: the profile is a display surface like the route line and the camera
  // fit, so it must be handed the SAME list those two already draw. One filter,
  // at the widget boundary — never a second one inside the strip.
  // M-2: the reject used to be the extreme point as well (999 m, 3.2° away), so
  // a filter by value or by distance passed this case by luck. Now the quiet
  // rejected fix is indistinguishable from a kept one by value, and the wild
  // reading belongs to a KEPT fix: it must survive `displayablePoints`.
  testWidgets('the elevation profile receives the filtered points, not the raw list', (
    tester,
  ) async {
    final climb = _p(lat: 36.7500, t: 0, alt: 10);
    final stop = _p(lat: 36.7501, t: 1_000_000_000, alt: 15, type: WaypointType.idle);
    final spike = _p(lat: 36.75015, t: 2_000_000_000, alt: 12, type: WaypointType.rejected);
    final far = _p(lat: 40.0, t: 3_000_000_000, alt: 999);
    final raw = [climb, stop, spike, far];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith((ref) => Future.value(style)),
          activityDetailProvider.overrideWith(
            (ref, id) => Future.value(_synthetic(points: raw)),
          ),
        ],
        child: MaterialApp(home: ActivityDetailScreen(activityId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    final strip = tester.widget<ElevationStrip>(find.byType(ElevationStrip));
    // The rejected spike is gone — on `type` alone; the ر5 idle stop, the wild
    // kept reading and the order survive.
    expect(strip.points, [climb, stop, far]);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<ElevationStripPainter>()
        .toList();
    expect(painters, hasLength(1));
    expect(painters.single.points, [climb, stop, far]);
    // The false peak disappears with the spike: two segments, not the three the
    // raw list strokes by pairing the rejected fix with both kept neighbours.
    expect(drawableSegmentCount(raw), 3);
    expect(drawableSegmentCount(painters.single.points), 2);
    expect(tester.takeException(), isNull);
  });

  // ر116: an activity summary carries EVERY stored point, and the family key is
  // a row id — an unbounded, user-grown value. On the non-autoDispose default
  // (verified in riverpod 3.4.3 `future_provider.dart:106`, where
  // `isAutoDispose` defaults to `false`) every activity opened in a session
  // kept its full track point list alive until the app died. The detail screen
  // is the provider's only listener, so the cache must end with the screen.
  test('the detail cache is released when the last listener leaves', () async {
    final counting = _CountingRepo(db);
    final container = ProviderContainer(
      overrides: [activityRepositoryProvider.overrideWithValue(counting)],
    );
    addTearDown(container.dispose);

    ProviderSubscription<AsyncValue<ActivitySummary>> open() =>
        container.listen(activityDetailProvider(seededId), (_, _) {});

    final first = open();
    await container.read(activityDetailProvider(seededId).future);
    expect(counting.reads, 1);
    // Same id, still-listening: the family answers from cache, no second read.
    await container.read(activityDetailProvider(seededId).future);
    expect(counting.reads, 1);

    first.close();
    await container.pump();

    final again = open();
    await container.read(activityDetailProvider(seededId).future);
    expect(counting.reads, 2, reason: 'the point list must not outlive the screen');
    again.close();
  });

  // §2أ: the export is a button on the screen that already shows the activity.
  // What is proven HERE is the screen: the affordance appears only with a
  // loaded activity, which format the user's tap resolves to, which row the
  // exporter is handed, and what the user sees when the export fails. The
  // bytes-on-disk and the arguments handed to Kotlin are proven in
  // test/export/track_exporter_test.dart, on a real filesystem.
  group('تصدير (§2أ)', () {
    late _RecordingExporter exporter;

    setUp(() => exporter = _RecordingExporter());

    /// Production wiring with one thing swapped: the exporter records instead
    /// of writing and sharing.
    Widget exportApp({int activityId = -1}) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mapStyleProvider.overrideWith((ref) => Future.value(style)),
        trackExporterProvider.overrideWithValue(exporter),
      ],
      child: MaterialApp(
        home: ActivityDetailScreen(
          activityId: activityId == -1 ? seededId : activityId,
        ),
      ),
    );

    /// Opens the menu and picks [label].
    ///
    /// `onSelected` fires only once the menu route's CLOSE animation has
    /// finished (`showMenu(...).then(...)`), so the settle is what hands the
    /// tap to the exporter — no `runAsync`, because this exporter awaits only
    /// microtasks. Real `dart:io` under this clock is the one thing that must
    /// NOT be attempted here: measured on 2026-10-17, a `writeAsString` started
    /// from a `testWidgets` body never completed, not even when its creation
    /// and await were both wrapped in `tester.runAsync` — the directory was
    /// created, the file was not, and the probe run hung.
    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('the export action appears once the activity is on screen', (
      tester,
    ) async {
      await tester.pumpWidget(exportApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.ios_share), findsOneWidget);

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      expect(find.text('ملف GPX'), findsOneWidget);
      expect(find.text('ملف TCX (Garmin)'), findsOneWidget);
    });

    testWidgets('there is nothing to export while the read has failed', (
      tester,
    ) async {
      await tester.pumpWidget(exportApp(activityId: 999));
      await tester.pumpAndSettle();

      expect(find.text('تعذّر تحميل النشاط'), findsOneWidget);
      expect(find.byIcon(Icons.ios_share), findsNothing);
      expect(exporter.calls, isEmpty);
    });

    testWidgets('choosing GPX hands the loaded row to the exporter as GPX', (
      tester,
    ) async {
      await tester.pumpWidget(exportApp());
      await tester.pumpAndSettle();

      await choose(tester, 'ملف GPX');

      final call = exporter.calls.single;
      expect(call.format, ExportFormat.gpx);
      // The row on screen, not another id and not a summary rebuilt from the
      // widgets: the export must carry the same distance the panel displayed.
      expect(call.summary.id, seededId);
      expect(call.summary.distanceM, 6400);
      expect(call.summary.sport, 'run');
    });

    testWidgets('choosing TCX is a different request, not the GPX one relabelled', (
      tester,
    ) async {
      await tester.pumpWidget(exportApp());
      await tester.pumpAndSettle();

      await choose(tester, 'ملف TCX (Garmin)');

      expect(exporter.calls.single.format, ExportFormat.tcx);
    });

    testWidgets('when the export fails, the screen says so instead of going quiet', (
      tester,
    ) async {
      exporter.failure = PlatformException(
        code: 'no_app',
        message: 'nothing accepts a GPX file',
      );
      await tester.pumpWidget(exportApp());
      await tester.pumpAndSettle();

      await choose(tester, 'ملف GPX');

      expect(exporter.calls, hasLength(1));
      expect(find.text('تعذّرت المشاركة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The bar dismisses on a four-second timer; flush it so the binding does
      // not end the test with a pending timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}

/// The screen's exporter, with the disk and the platform removed.
///
/// A `testWidgets` body runs on a fake clock, and real `dart:io` under it is
/// not drivable: measured on 2026-10-17, a `File.writeAsString` started from
/// this kind of body never completed even with its creation and await wrapped
/// in `tester.runAsync` — the `exports` directory was created, the file inside
/// it was not, and the suite hung. So the widget layer records the request and
/// the byte-level write stays proven in test/export/track_exporter_test.dart,
/// which runs on the real event loop.
class _RecordingExporter extends TrackExporter {
  PlatformException? failure;

  final List<({ActivitySummary summary, ExportFormat format})> calls = [];

  @override
  Future<File> exportAndShare(
    ActivitySummary summary,
    ExportFormat format,
  ) async {
    calls.add((summary: summary, format: format));
    final error = failure;
    if (error != null) throw error;
    return File(exportFileName(summary, format));
  }
}
