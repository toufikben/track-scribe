import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/route_painter.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import 'package:track_scribe/ui/recording/widgets/sport_chips.dart';

const _p1 = StoredPoint(
  lat: 36.7538,
  lon: 3.1856,
  timeNanos: 0,
  accuracyM: 4,
  type: WaypointType.normal,
);
const _p2 = StoredPoint(
  lat: 36.7558,
  lon: 3.1876,
  timeNanos: 1000000000,
  accuracyM: 4,
  type: WaypointType.normal,
);
const _rejected = StoredPoint(
  lat: 36.7568,
  lon: 3.1886,
  timeNanos: 2000000000,
  accuracyM: 4,
  type: WaypointType.rejected,
);

/// R86: home is AppGate — an unseeded DB boots into PermissionScreen.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

void main() {
  test('rejected points split out of the polyline but stay in the trail', () {
    final painter = RoutePainter(const [_p1, _rejected, _p2]);
    expect(painter.polylinePoints.length, 2);
    expect(painter.rejectedPoints.length, 1);
    expect(painter.rejectedPoints.single.type, WaypointType.rejected);
    expect(painter.hasPolyline, isTrue);
  });

  test('R90: the projection preserves aspect (cos-corrected longitude)', () {
    // Δlat == Δlon × cos(lat) must land at equal pixel distances, or a square
    // courtyard renders as a wide rectangle. The pair is symmetric about the
    // test latitude because the projection is defined about the bounds centre
    // (RouteProjection.centreLat) — that is where the cos must be read.
    const lat = 36.7538;
    const lon = 3.1856;
    final c = math.cos(lat * math.pi / 180);
    const dLon = 0.002;
    final pts = [
      StoredPoint(
        lat: lat - dLon * c / 2,
        lon: lon - dLon / 2,
        timeNanos: 0,
        accuracyM: 4,
        type: WaypointType.normal,
      ),
      StoredPoint(
        lat: lat + dLon * c / 2,
        lon: lon + dLon / 2,
        timeNanos: 1000000000,
        accuracyM: 4,
        type: WaypointType.normal,
      ),
    ];
    final offsets = RoutePainter(pts).project(const Size(300, 300));
    final delta = offsets[pts[1]]! - offsets[pts[0]]!;
    expect(
      delta.dx.abs(),
      closeTo(delta.dy.abs(), 0.001),
      reason: 'Δlat=${dLon * c} must span the same pixels as Δlon=$dLon',
    );
  });

  test('one point: no polyline, the projection still places it', () {
    final painter = RoutePainter(const [_p1]);
    expect(painter.hasPolyline, isFalse);
    expect(painter.project(const Size(300, 300)).keys.single, _p1);
  });

  test('empty route projects nothing and never throws', () {
    final painter = RoutePainter(const []);
    expect(painter.hasPolyline, isFalse);
    expect(painter.polylinePoints, isEmpty);
    expect(painter.rejectedPoints, isEmpty);
    expect(painter.project(const Size(300, 300)), isEmpty);
  });

  testWidgets('empty route renders a grid with a RoutePainter, never throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: GridBasemap(points: []),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(GridBasemap),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(paint.painter, isA<RoutePainter>());
  });

  testWidgets('a two-point route paints without throwing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: GridBasemap(points: [_p1, _rejected, _p2]),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(GridBasemap),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    final painter = paint.painter! as RoutePainter;
    expect(painter.hasPolyline, isTrue);
    expect(painter.rejectedPoints.length, 1);
  });

  testWidgets(
    'map overlays never collide at 360dp: north × chips, scale × banner',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 2.75, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final db = await _seededDb();
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const TrackScribeApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // Start a session so the synthetic source feeds points: the scale bar
      // only exists once there is a projected route to read (R90 truth).
      await tester.tap(find.text('ابدأ التسجيل'));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      final map = tester.getRect(find.byType(GridBasemap));
      final north = tester.getRect(find.byKey(const Key('basemap-north')));
      final scale = tester.getRect(find.byKey(const Key('basemap-scale')));
      final chips = tester.getRect(find.byType(SportChips));
      final banner = tester.getRect(find.byType(GpsStatusBanner));

      bool inside(Rect r) =>
          r.left >= map.left - 0.5 &&
          r.top >= map.top - 0.5 &&
          r.right <= map.right + 0.5 &&
          r.bottom <= map.bottom + 0.5;
      expect(inside(north), isTrue, reason: 'north $north outside map $map');
      expect(inside(scale), isTrue, reason: 'scale $scale outside map $map');
      expect(
        north.overlaps(chips),
        isFalse,
        reason: 'north $north × chips $chips at 360dp',
      );
      expect(
        scale.overlaps(banner),
        isFalse,
        reason: 'scale $scale × banner $banner at 360dp',
      );

      // Stop so the synthetic source's periodic timer is cancelled before the
      // fake-async zone teardown (pending timers fail the test).
      await tester.tap(find.text('إيقاف'));
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
