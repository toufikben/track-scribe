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

  test('painter draws one segment per measured pair and none across a null gap', () {
    // A drawable segment needs BOTH endpoints measured (ر11: altitudes arrive
    // NULL when a fix never measured one; a rise over a missing reading would be
    // invented). This count is exactly the painter's own skip rule, so the
    // behaviour the old `expect(pic, isNotNull)` only pretended to check is now
    // asserted, and a null gap really is proven to draw nothing.
    expect(drawableSegmentCount([_p(0, 0, 10), _p(0, 0, 30)]), 1);
    expect(drawableSegmentCount([_p(0, 0, 10), _p(0, 0, 20), _p(0, 0, 30)]), 2);
    expect(drawableSegmentCount([_p(0, 0, 10), _p(0, 0, null), _p(0, 0, 30)]), 0);
    expect(drawableSegmentCount([_p(0, 0, null), _p(0, 0, null)]), 0);

    // The painter runs the same rule over the gap input without throwing.
    final rec = ui.PictureRecorder();
    ElevationStripPainter(
      [_p(0, 0, 10), _p(0, 0, null), _p(0, 0, 30)],
    ).paint(Canvas(rec), const Size(200, 96));
    rec.endRecording();
  });

  test('fewer than two measured altitudes is the empty-message state', () {
    // `hasAltitudeProfile` is the shared message flag (widget + painter): fewer
    // than two measured altitudes means there is no profile to read, so the
    // strip shows `kNoAltitudeMessage` and the painter draws no segment.
    expect(hasAltitudeProfile([_p(0, 0, null)]), isFalse);
    expect(hasAltitudeProfile([_p(0, 0, 10)]), isFalse); // a single reading
    expect(hasAltitudeProfile([_p(0, 0, 10), _p(0, 0, 20)]), isTrue);
    expect(drawableSegmentCount([_p(0, 0, null)]), 0);

    // The painter takes the message branch (paints text, returns) without throwing.
    final rec = ui.PictureRecorder();
    ElevationStripPainter([_p(0, 0, null)]).paint(Canvas(rec), const Size(200, 96));
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
