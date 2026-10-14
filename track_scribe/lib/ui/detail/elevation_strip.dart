import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Grade colour: flat → dim olive, ±8 % slope → the accent (spec §12.1
/// «شريط مقطع الارتفاع مع تظليل الدرجة» — GNSS altitude, ر11 data).
Color gradeColor(double t) =>
    Color.lerp(ElevationStrip.flatColor, ElevationStrip.steepColor, t.clamp(0.0, 1.0))!;

/// The strip's one rule about its own data: a profile needs two measured
/// altitudes, and the ر11 altitudes arrive as NULL when the fix never measured
/// one. Shared by the widget (empty state) and the painter (empty canvas), so
/// the two can never disagree about when there is nothing to draw.
bool hasAltitudeProfile(List<StoredPoint> points) =>
    points.where((p) => p.altitudeM != null).length >= 2;

/// The empty-profile message — a real string in one place, because the strip
/// renders it BOTH ways: as a widget on screen and as the painter's canvas text
/// when it is handed an empty profile directly.
const String kNoAltitudeMessage = 'لا توجد بيانات ارتفاع';

/// A segment is drawable only when BOTH endpoints carry a measured altitude —
/// the painter's skip rule, shared with [drawableSegmentCount] so the count a
/// test asserts is exactly what [ElevationStripPainter] draws.
bool _measuredPair(StoredPoint a, StoredPoint b) => a.altitudeM != null && b.altitudeM != null;

/// How many profile segments the painter will actually stroke: one per
/// consecutive measured pair, none across a null gap. Pure, so "draws segments
/// for measured altitudes and skips null gaps" is asserted rather than painted.
int drawableSegmentCount(List<StoredPoint> points) {
  var n = 0;
  for (var i = 1; i < points.length; i++) {
    if (_measuredPair(points[i - 1], points[i])) n++;
  }
  return n;
}

class ElevationStrip extends StatelessWidget {
  const ElevationStrip({super.key, required this.points});

  final List<StoredPoint> points;

  /// The dim end of the grade ramp — [Palette.rampDim], the same token the
  /// speed ramp starts from; no raw hex lives in a widget file.
  static const Color flatColor = Palette.rampDim;
  static const Color steepColor = Palette.accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    width: double.infinity,
    // An empty profile is a state the user must be able to READ, not pixels on
    // a canvas: rendered as a Text so it reaches the widget tree (and a screen
    // reader). The painter keeps its own canvas message for direct use.
    child: hasAltitudeProfile(points)
        ? CustomPaint(painter: ElevationStripPainter(points))
        : const Center(
            child: Text(
              kNoAltitudeMessage,
              style: TextStyle(fontSize: 11, color: Palette.textSecondary),
            ),
          ),
  );
}

class ElevationStripPainter extends CustomPainter {
  ElevationStripPainter(this.points);

  final List<StoredPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (!hasAltitudeProfile(points)) {
      final tp = TextPainter(
        text: TextSpan(
          text: kNoAltitudeMessage,
          style: const TextStyle(fontSize: 11, color: Palette.textSecondary),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }
    final measured = [
      for (final p in points)
        if (p.altitudeM != null) p.altitudeM!,
    ];
    final minA = measured.reduce(math.min);
    final maxA = measured.reduce(math.max);
    final pad = maxA == minA ? 1.0 : (maxA - minA) * 0.1;
    final lo = minA - pad, hi = maxA + pad;
    double yOf(double a) => size.height - (a - lo) / (hi - lo) * size.height;
    double xOf(int i) => points.length <= 1 ? 0 : i / (points.length - 1) * size.width;

    // grade-shaded segments, gaps where altitude is missing
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (!_measuredPair(a, b)) continue;
      // Horizontal distance from the two fixes (haversine, core/geo.dart):
      // a grade is rise over ground distance, and a 0 m run cannot divide.
      final dist = a.distanceTo(b);
      final grade = dist <= 0 ? 0.0 : (b.altitudeM! - a.altitudeM!) / dist;
      line.color = gradeColor((grade.abs() / 0.08).clamp(0.0, 1.0));
      canvas.drawLine(
        Offset(xOf(i - 1), yOf(a.altitudeM!)),
        Offset(xOf(i), yOf(b.altitudeM!)),
        line,
      );
    }

    final labelStyle = const TextStyle(fontSize: 9, color: Palette.textSecondary);
    TextPainter(text: TextSpan(text: '${maxA.round()} م', style: labelStyle), textDirection: TextDirection.rtl)
      ..layout()
      ..paint(canvas, Offset(4, 2));
    TextPainter(text: TextSpan(text: '${minA.round()} م', style: labelStyle), textDirection: TextDirection.rtl)
      ..layout()
      ..paint(canvas, Offset(4, size.height - 13));
  }

  @override
  bool shouldRepaint(covariant ElevationStripPainter old) => old.points != points;
}
