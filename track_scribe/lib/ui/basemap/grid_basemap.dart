import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Task 7 stand-in for the Task-10 generated dark basemap: paints a plain
/// grid on `Palette.bg` and plots the engine's stored points as an accent
/// polyline. The constructor contract (`points`) is what the recording screen
/// consumes; Task 10 keeps it and swaps the painter for the real generated
/// tiles.
class GridBasemap extends StatelessWidget {
  const GridBasemap({super.key, required this.points});

  final List<StoredPoint> points;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(points),
    child: const SizedBox.expand(),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.points);

  final List<StoredPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.bg);
    final grid = Paint()
      ..color = Palette.surface
      ..strokeWidth = 1;
    const step = 42.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;

    var minLat = points.first.lat, maxLat = minLat;
    var minLon = points.first.lon, maxLon = minLon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    const pad = 24.0;
    final w = size.width - 2 * pad, h = size.height - 2 * pad;
    final dLat = maxLat - minLat == 0 ? 1e-9 : maxLat - minLat;
    final dLon = maxLon - minLon == 0 ? 1e-9 : maxLon - minLon;
    Offset project(StoredPoint p) => Offset(
      pad + (p.lon - minLon) / dLon * w,
      pad + (maxLat - p.lat) / dLat * h,
    );

    final first = project(points.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = Palette.accent;
    for (final p in points) {
      canvas.drawCircle(project(p), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.points != points;
}
