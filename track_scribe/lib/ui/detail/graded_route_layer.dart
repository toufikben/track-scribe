import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// `Path` hidden: latlong2 exports its own generic `Path<T>` (a route of
// LatLngs), which would shadow dart:ui's `Path` and break the arrow below.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Per-segment speed of the route in m/s: a measured speed when the segment
/// carries one, otherwise distance over the monotonic delta (0 when dt is 0 —
/// never divide, never invent).
///
/// Order is `b` then `a`: Android's `Location.getSpeed()` is the speed of the
/// interval ENDING at that fix, so `b.speedMps` is this segment's own
/// measurement and `a.speedMps` is the nearest one when it is missing (the
/// brief's first test asserts exactly this — a measured 4 beats a computed 0).
/// dist/dt is the last resort, not the first choice.
double segmentSpeedMps(StoredPoint a, StoredPoint b) {
  final measured = b.speedMps ?? a.speedMps;
  if (measured != null) return measured;
  final dtS = (b.timeNanos - a.timeNanos) / 1e9;
  if (dtS <= 0) return 0;
  // `distanceTo` is the project's haversine (core/geo.dart, WGS84 mean radius
  // 6371008.8 m) — latlong2 0.10 has no `LengthUnit.Metre`, so metre distance
  // never comes from that package.
  return a.distanceTo(b) / dtS;
}

/// Slowest → dim olive, fastest → the brand accent (spec §12.1).
Color speedColor(double t) =>
    Color.lerp(GradedRouteLayer.slowColor, GradedRouteLayer.fastColor, t.clamp(0.0, 1.0))!;

/// The finished-activity route: one coloured segment per pair, coloured by
/// each segment's speed percentile over the whole route, plus a direction
/// arrow at the midpoint. A flutter_map child — it re-projects via
/// [MapCamera.of] on every camera change.
class GradedRouteLayer extends StatelessWidget {
  const GradedRouteLayer({super.key, required this.points, required this.strokeWidth});

  final List<StoredPoint> points;
  final double strokeWidth;

  /// The dim end of the speed ramp: [Palette.rampDim], hoisted into the palette
  /// because the UI law admits no raw hex in a widget file (the same precedent
  /// as [Palette.gridOverlay]). Decoration, so the contrast law does not bind
  /// it.
  static const Color slowColor = Palette.rampDim;
  static const Color fastColor = Palette.accent;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return CustomPaint(
      painter: _GradedRoutePainter(points, camera, strokeWidth),
      size: Size.infinite,
    );
  }
}

class _GradedRoutePainter extends CustomPainter {
  _GradedRoutePainter(this.points, this.camera, this.strokeWidth);

  final List<StoredPoint> points;
  final MapCamera camera;
  final double strokeWidth;

  List<StoredPoint> get _route =>
      [for (final p in points) if (p.type != WaypointType.rejected) p];

  @override
  void paint(Canvas canvas, Size size) {
    final route = _route;
    if (route.length < 2) return;
    final speeds = [
      for (var i = 1; i < route.length; i++)
        segmentSpeedMps(route[i - 1], route[i]),
    ];
    final sorted = [...speeds]..sort();
    double percentile(double v) {
      if (sorted.isEmpty) return 0;
      var lo = 0, hi = sorted.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (sorted[mid] < v) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo / sorted.length;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < route.length; i++) {
      final a = camera.latLngToScreenOffset(LatLng(route[i - 1].lat, route[i - 1].lon));
      final b = camera.latLngToScreenOffset(LatLng(route[i].lat, route[i].lon));
      paint.color = speedColor(percentile(speeds[i - 1]));
      canvas.drawLine(a, b, paint);
    }
    _arrow(canvas, route);
  }

  void _arrow(Canvas canvas, List<StoredPoint> route) {
    final mid = route.length ~/ 2;
    if (mid < 1 || mid >= route.length - 1) return;
    final from = route[mid - 1];
    final to = route[mid + 1];
    final o = camera.latLngToScreenOffset(LatLng(route[mid].lat, route[mid].lon));
    final deg = bearingDeg(from.lat, from.lon, to.lat, to.lon);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(deg * math.pi / 180);
    final p = Path()
      ..moveTo(10, 0)
      ..lineTo(-6, -7)
      ..lineTo(-6, 7)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = Palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradedRoutePainter old) =>
      old.points != points || old.camera != camera || old.strokeWidth != strokeWidth;
}
