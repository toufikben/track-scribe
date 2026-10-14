import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/elevation_strip.dart';

StoredPoint _p(double lat, double lon, double? alt) => StoredPoint(
    lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: WaypointType.normal, altitudeM: alt);

void main() {
  test('gradeColor: flat is the dim end, steep saturates to the bright end', () {
    expect(gradeColor(0), ElevationStrip.flatColor);
    // The brief wrote `gradeColor(0.5)` here, which its own `Color.lerp`
    // implementation cannot return (a lerp hits the midpoint, not the end).
    // Step 5 of the brief settles it — «the endpoints are the contract» — and
    // the painter's mapping (`|grade| / 0.08`) puts full saturation at a ±8 %
    // slope, exactly where spec §12.1 says the accent belongs.
    expect(gradeColor(1), ElevationStrip.steepColor);
    expect(ElevationStrip.steepColor, Palette.accent);
    final mid = gradeColor(0.5);
    expect(mid.r, inInclusiveRange(ElevationStrip.flatColor.r, Palette.accent.r));
    expect(mid.g, inInclusiveRange(ElevationStrip.flatColor.g, Palette.accent.g));
  });

  test('painter draws segments for measured altitudes and skips null gaps', () {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    ElevationStripPainter(
      [_p(0, 0, 10), _p(0, 0, null), _p(0, 0, 30)],
    ).paint(canvas, const Size(200, 96));
    final pic = rec.endRecording();
    expect(pic, isNotNull); // no throw, real draw calls recorded
  });

  test('fewer than two measured altitudes paints the empty message', () {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    ElevationStripPainter([_p(0, 0, null)]).paint(canvas, const Size(200, 96));
    rec.endRecording();
  });

  testWidgets('an empty profile reads as a message, a profile draws a canvas', (
    tester,
  ) async {
    // The strip's own contract: an empty state a person can read (and a screen
    // reader can find), not pixels on a canvas. This is the assertion that was
    // RED when the message existed only inside the painter.
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ElevationStrip(points: [_p(0, 0, null)]))),
    );
    expect(find.text('لا توجد بيانات ارتفاع'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ElevationStrip),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevationStrip(points: [_p(0, 0, 10), _p(0.0002, 0, 30)]),
        ),
      ),
    );
    expect(find.text('لا توجد بيانات ارتفاع'), findsNothing);
  });
}
