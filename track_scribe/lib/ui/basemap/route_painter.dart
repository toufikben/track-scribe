import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Equirectangular projection about the bounds centre (valid for a single
/// route's extent). Longitude is scaled by cos(centreLat) and both axes share
/// one px-per-degree factor, so shapes keep their aspect (R90) and one metre
/// is the same pixel count in every direction — which is what lets the scale
/// bar read a single honest number.
class RouteProjection {
  RouteProjection(this.points, this.size);

  final List<StoredPoint> points;
  final Size size;

  /// A route is never cut off: the padded rect (24 px) bounds the projection.
  static const double pad = 24;

  late final double minLat = _fold((p) => p.lat, math.min);
  late final double maxLat = _fold((p) => p.lat, math.max);
  late final double minLon = _fold((p) => p.lon, math.min);
  late final double maxLon = _fold((p) => p.lon, math.max);
  late final double centreLat = (minLat + maxLat) / 2;
  late final double centreLon = (minLon + maxLon) / 2;
  late final double scale = _fit();

  double _fold(double Function(StoredPoint) pick, double Function(double, double) op) =>
      points.map(pick).reduce(op);

  double _fit() {
    final w = math.max(1.0, size.width - 2 * pad);
    final h = math.max(1.0, size.height - 2 * pad);
    final xDeg = (maxLon - minLon) * math.cos(centreLat * math.pi / 180);
    final dLat = maxLat - minLat;
    final sx = xDeg > 0 ? w / xDeg : double.infinity;
    final sy = dLat > 0 ? h / dLat : double.infinity;
    final fit = math.min(sx, sy);
    // Zero extent (one point, or a ر6 standing-still trail of identical
    // positions) has no pixels-per-degree at all. 0 is the honest answer and
    // `metresPerPixel` propagates it as "no scale"; a 1.0 sentinel would let
    // the scale bar print a fabricated figure for a route that spans nothing.
    return fit == double.infinity ? 0 : fit;
  }

  Offset of(StoredPoint p) => Offset(
    size.width / 2 +
        (p.lon - centreLon) * math.cos(centreLat * math.pi / 180) * scale,
    size.height / 2 - (p.lat - centreLat) * scale,
  );

  /// Metres per canvas pixel — uniform in both axes thanks to the
  /// cos-correction (1° of latitude ≈ 111 320 m). 0 means "this projection
  /// spans nothing, so it has no scale to report".
  double get metresPerPixel => scale <= 0 ? 0 : 111320 / scale;
}

/// Paints the stored trail on the generated basemap: the honest polyline in
/// the accent colour, rejected raw points as faint dots (ر4/ر9 — nothing is
/// deleted, but a reject never reads as the route), and start/end markers.
class RoutePainter extends CustomPainter {
  RoutePainter(this.points);

  /// All stored points, unfiltered.
  final List<StoredPoint> points;

  /// The route: every stored point except ر4 rejects.
  List<StoredPoint> get polylinePoints =>
      [for (final p in points) if (p.type != WaypointType.rejected) p];

  List<StoredPoint> get rejectedPoints =>
      [for (final p in points) if (p.type == WaypointType.rejected) p];

  bool get hasPolyline => polylinePoints.length >= 2;

  List<StoredPoint> get _boundsPoints =>
      polylinePoints.isNotEmpty ? polylinePoints : points;

  /// Canvas offsets for every point under the production projection —
  /// public so tests and the scale bar read this math, not a copy of it.
  Map<StoredPoint, Offset> project(Size size) {
    if (points.isEmpty) return const {};
    final projection = RouteProjection(_boundsPoints, size);
    return {for (final p in points) p: projection.of(p)};
  }

  /// Metres per pixel of the projection for [size] — the scale bar's truth.
  double metresPerPixel(Size size) {
    if (points.isEmpty) return 0;
    return RouteProjection(_boundsPoints, size).metresPerPixel;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.surface);
    _grid(canvas, size);
    if (points.isEmpty) return;

    final offsets = project(size);
    // R91: rejected dots are decoration in textSecondary at low alpha —
    // never danger (reserved for stop) and no contrast claim is made.
    final rejectedPaint = Paint()
      ..color = Palette.textSecondary.withValues(alpha: .35);
    for (final p in rejectedPoints) {
      canvas.drawCircle(offsets[p]!, 3, rejectedPaint);
    }

    if (!hasPolyline) {
      // < 2 routable points: only the start dot renders, nothing throws.
      canvas.drawCircle(
        offsets[points.first]!,
        9,
        Paint()..color = Palette.accent,
      );
      return;
    }

    final route = Paint()
      ..color = Palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final start = offsets[polylinePoints.first]!;
    path.moveTo(start.dx, start.dy);
    for (final p in polylinePoints.skip(1)) {
      final o = offsets[p]!;
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, route);

    canvas.drawCircle(start, 9, Paint()..color = Palette.accent);
    canvas.drawCircle(
      offsets[polylinePoints.last]!,
      9,
      Paint()
        ..color = Palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _grid(Canvas canvas, Size size) {
    // The grid is decoration, not text — the contrast law does not bind it.
    final grid = Paint()
      ..color = Palette.gridOverlay
      ..strokeWidth = 1;
    const step = 40.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) =>
      // List identity, not content: the controller hands over a freshly built
      // snapshot per frame while a session runs, so any new instance means the
      // trail may have grown and must repaint. A content compare would be an
      // O(n) walk of a list that only grows; the paint itself is cheap.
      oldDelegate.points != points;
}
