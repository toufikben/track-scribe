import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/route_painter.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart';

import '../support/stub_vector_style.dart';

StoredPoint _p(
  double lat,
  double lon, {
  WaypointType type = WaypointType.normal,
}) => StoredPoint(
  lat: lat,
  lon: lon,
  timeNanos: 0,
  accuracyM: 5,
  type: type,
  bearingDeg: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Style style;

  setUpAll(() async {
    style = await loadStubVectorStyle();
  });

  tearDownAll(() => style.dispose());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [mapStyleProvider.overrideWith((ref) => Future.value(style))],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('renders map, route, halo, marker and the attribution row', (
    tester,
  ) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(wrap(VectorMapBand(points: points, current: points.last)));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.byType(MarkerLayer), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byKey(const Key('map-recenter')), findsOneWidget);
    expect(find.byKey(const Key('basemap-scale')), findsOneWidget);
  });

  testWidgets('IDLE point draws the idle badge and no halo', (tester) async {
    final idle = _p(36.7520, 3.0420, type: WaypointType.idle);
    await tester.pumpWidget(wrap(VectorMapBand(points: [idle], current: idle)));
    await tester.pumpAndSettle();
    expect(find.byType(CircleLayer), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('style failure falls back to the grid basemap with the route', (
    tester,
  ) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith(
            (ref) => Future<Style>.error(StateError('no tiles')),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VectorMapBand(points: points, current: points.last),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('basemap-canvas')), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    // The law is "the route stays visible in the fallback", so prove the
    // fallback canvas actually has a polyline to paint — not just that a
    // GridBasemap exists with a field forwarded to it.
    final canvas = tester.widget<CustomPaint>(
      find.byKey(const Key('basemap-canvas')),
    );
    final painter = canvas.painter;
    expect(painter, isA<RoutePainter>());
    expect(
      (painter as RoutePainter).hasPolyline,
      isTrue,
      reason: 'both points must reach the fallback polyline',
    );
  });

  testWidgets('while the style loads: flat Palette.bg, no map, attribution stays', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith(
            (ref) => Completer<Style>().future, // never resolves
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VectorMapBand(
              points: [_p(36.7500, 3.0400), _p(36.7520, 3.0420)],
              current: _p(36.7520, 3.0420),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(GridBasemap), findsNothing);
    // The law is about the MAP AREA, not "any ColoredBox with that colour":
    // the attribution strip is a Container(color: Palette.bg), and Container
    // builds a ColoredBox internally — so a bare predicate would pass even if
    // the loading branch painted something else. Read the band's own child.
    final bandColumn = tester.widget<Column>(
      find
          .descendant(
            of: find.byType(VectorMapBand),
            matching: find.byType(Column),
          )
          .first,
    );
    final mapArea = (bandColumn.children.first as Expanded).child;
    expect(
      mapArea,
      isA<ColoredBox>(),
      reason: 'the loading branch must be a flat box, spec §12',
    );
    expect(
      (mapArea as ColoredBox).color,
      Palette.bg,
      reason: 'the loading branch must be exactly Palette.bg',
    );
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('recenter button returns without throwing on an empty route', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const VectorMapBand(points: [], current: null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map-recenter')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
