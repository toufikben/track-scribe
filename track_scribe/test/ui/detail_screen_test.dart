import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
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
  testWidgets('the elevation profile receives the filtered points, not the raw list', (
    tester,
  ) async {
    final climb = _p(lat: 36.7500, t: 0, alt: 10);
    final stop = _p(lat: 36.7501, t: 1_000_000_000, alt: 15, type: WaypointType.idle);
    final spike = _p(lat: 40.0, t: 2_000_000_000, alt: 999, type: WaypointType.rejected);
    final resumed = _p(lat: 36.7502, t: 3_000_000_000, alt: 20);
    final raw = [climb, stop, spike, resumed];

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
    // The rejected spike is gone; the ر5 idle stop and the order survive.
    expect(strip.points, [climb, stop, resumed]);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<ElevationStripPainter>()
        .toList();
    expect(painters, hasLength(1));
    expect(painters.single.points, [climb, stop, resumed]);
    // The false peak disappears with the spike: two segments, not the three the
    // raw list strokes by pairing the rejected fix with both kept neighbours.
    expect(drawableSegmentCount(raw), 3);
    expect(drawableSegmentCount(painters.single.points), 2);
    expect(tester.takeException(), isNull);
  });
}
