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

  late BundledStyle style;

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

  // ر107 regression guard: the band must render one VectorTileLayer per
  // stacked pack entry, each bound to its OWN provider — a single-layer
  // regression would hide nowhere else than in this widget tree.
  testWidgets('the band stacks one VectorTileLayer per bundled pack (ر107)', (
    tester,
  ) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(wrap(VectorMapBand(points: points, current: points.last)));
    await tester.pumpAndSettle();

    final layers = tester
        .widgetList<VectorTileLayer>(find.byType(VectorTileLayer))
        .toList();
    expect(layers.length, style.layers.length);
    expect(
      layers.map((l) => identityHashCode(l.tileProviders)).toSet().length,
      style.layers.length,
      reason: 'each layer binds its own pack provider, not one merged one',
    );
  });

  // ر107 review I-2: the camera cap is the DISPLAY ceiling, one constant shared
  // by both bands. A pack's `maximumZoom` is a DATA ceiling the provider
  // clamps to (core/tile_zoom.dart), so the camera must stay above it — free
  // overzoom past the deepest pack is what the ر107 fix rests on.
  testWidgets('the band caps the camera at the shared display ceiling, above the packs', (
    tester,
  ) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(wrap(VectorMapBand(points: points, current: points.last)));
    await tester.pumpAndSettle();

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.maxZoom, kMapDisplayMaxZoom);
    expect(
      options.maxZoom,
      greaterThan(style.maximumZoom.toDouble()),
      reason: 'free overzoom past the deepest pack is the ر107 mechanism',
    );
  });

  // R114: the band stacks one VectorTileLayer per pack and each layer paints
  // its own background for a refused tile (tile_rasterizer.dart:122-131), so
  // the TOP (deep) layer occludes the shallow one everywhere outside its box.
  // The theme must therefore carry no `background` layer — the flat fill lives
  // on MapOptions.backgroundColor, which the same Palette.bg contract already
  // supplies. This test proves the band consumes the stripped BundledStyle
  // verbatim (no re-strip, no added background layer) and hands the fill to
  // FlutterMap.
  testWidgets('the band stacks background-free themes and lets MapOptions supply the fill', (
    tester,
  ) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(wrap(VectorMapBand(points: points, current: points.last)));
    await tester.pumpAndSettle();

    final themes = tester
        .widgetList<VectorTileLayer>(find.byType(VectorTileLayer))
        .map((e) => e.theme)
        .toList();
    expect(themes, isNotEmpty,
        reason: 'the band must build one VectorTileLayer per stacked pack');
    for (final theme in themes) {
      expect(theme.backgroundColor(0), isNull,
          reason: 'a stacked theme that fills its tiles hides the layer below');
    }
    expect(
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.backgroundColor,
      Palette.bg,
      reason: 'the flat fill lives on the map, not on any theme layer',
    );
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
            (ref) => Future<BundledStyle>.error(StateError('no tiles')),
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
            (ref) => Completer<BundledStyle>().future, // never resolves
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
