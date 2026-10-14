import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/graded_route_layer.dart';

StoredPoint _p({required double lat, required double lon, required int t, double? speed}) =>
    StoredPoint(lat: lat, lon: lon, timeNanos: t, accuracyM: 5, type: WaypointType.normal, speedMps: speed);

void main() {
  test('segmentSpeedMps prefers the measured speed, falls back to dist/dt', () {
    final a = _p(lat: 36.75, lon: 3.00, t: 0, speed: 4);
    final b = _p(lat: 36.75, lon: 3.00, t: 1_000_000_000); // 1 s
    expect(segmentSpeedMps(a, b), 4); // measured wins
    final c = _p(lat: 36.75, lon: 3.001, t: 1_000_000_000);
    final fallback = segmentSpeedMps(a, c);
    expect(fallback, greaterThan(0));
    expect(fallback, lessThan(200));
  });

  // The brief's first case pins "measured wins" but cannot reach the dist/dt
  // branch (its `a` carries a speed), so the fallback the same sentence
  // promises gets its own case: neither endpoint measured => project haversine
  // over the monotonic delta, never a latlong2 LengthUnit (0.10 has none).
  test('segmentSpeedMps is dist/dt when neither point carries a speed', () {
    final a = _p(lat: 36.75, lon: 3.0000, t: 0);
    final b = _p(lat: 36.75, lon: 3.0009, t: 10_000_000_000); // 10 s
    expect(
      segmentSpeedMps(a, b),
      closeTo(haversineMeters(36.75, 3.0000, 36.75, 3.0009) / 10, 1e-9),
    );
  });

  test('segmentSpeedMps is 0 when dt is zero (never divide)', () {
    final a = _p(lat: 36.75, lon: 3.00, t: 5);
    expect(segmentSpeedMps(a, a), 0);
  });

  test('speedColor maps the ramp endpoints exactly and is monotonic', () {
    expect(speedColor(0), GradedRouteLayer.slowColor);
    expect(speedColor(1), GradedRouteLayer.fastColor);
    expect(GradedRouteLayer.fastColor, Palette.accent); // #C6FF3D
    final mid = speedColor(0.5);
    expect(mid.r, inInclusiveRange(GradedRouteLayer.slowColor.r, Palette.accent.r));
    expect(mid.g, inInclusiveRange(GradedRouteLayer.slowColor.g, Palette.accent.g));
  });

  // The arrow template's tip sits on +x, which in canvas (y-down) coordinates
  // is screen east = bearing 90. The rendered heading must therefore equal the
  // compass bearing, not `bearing` added on top of that east base. A unit-level
  // assertion of the transformed tip for known bearings pins the direction the
  // way no widget test can (the arrow is painted, never hit-tested).
  test('direction arrow tip points at the true compass bearing', () {
    void expectTip(double bearing, double x, double y) {
      final tip = arrowTipOffset(bearing);
      expect(tip.dx, closeTo(x, 1e-6), reason: 'tip x at bearing $bearing');
      expect(tip.dy, closeTo(y, 1e-6), reason: 'tip y at bearing $bearing');
    }

    expectTip(0, 0, -10); // north  -> up
    expectTip(90, 10, 0); // east   -> right
    expectTip(180, 0, 10); // south -> down
    expectTip(270, -10, 0); // west  -> left
  });
}
