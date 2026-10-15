import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/elevation_strip.dart';

StoredPoint _p(double lat, double lon, double? alt) => StoredPoint(
    lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: WaypointType.normal, altitudeM: alt);

StoredPoint _rejected(double lat, double lon, double? alt) => StoredPoint(
    lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: WaypointType.rejected, altitudeM: alt);

StoredPoint _idle(double lat, double lon, double? alt) => StoredPoint(
    lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: WaypointType.idle, altitudeM: alt);

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

  // ر115: the route painter and the camera fit both drop `rejected` fixes, while
  // the profile was handed the full list — so the jump the recorder refused was
  // stroked against its kept neighbours as a peak the rider never made.
  // M-2: the reject now carries an ORDINARY altitude in an ordinary place, and
  // the wild reading belongs to a KEPT point. The law is about `type`, so the
  // fixture must say so: a filter by `altitudeM > 500` or by position step was
  // indistinguishable from the real rule here, and now fails.
  test('displayablePoints drops the spike the profile must not stroke', () {
    final up = _p(0, 0, 10);
    final spike = _rejected(0.0002, 0, 12); // nothing marks it out by value
    final peak = _p(0.0004, 0, 999); // the wild reading is a real one: it stays

    // The defect, pinned first: unfiltered, the rejected fix pairs with BOTH kept
    // neighbours, so the strip reports a segment the route never drew.
    expect(drawableSegmentCount([up, spike, peak]), 2);

    // The law: the two kept points, in order, and one honest segment.
    expect(displayablePoints([up, spike, peak]), [up, peak]);
    expect(drawableSegmentCount(displayablePoints([up, spike, peak])), 1);
  });

  test('displayablePoints removes only rejected — the ر5 idle gaps survive', () {
    final normal = _p(0, 0, 10);
    final gap = _idle(0.0002, 0, 15);
    final after = _p(0.0004, 0, 999); // wild value on a kept point — it survives
    final spike = _rejected(0.0006, 0, 12); // ordinary value — and still dropped

    // An idle marker is a real stop the rider made, not GPS noise: the filter's
    // sole exclusion is `rejected`, and the surviving order is untouched.
    expect(displayablePoints([normal, gap, after, spike]), [normal, gap, after]);
  });

  // ر115: the filter lives at the widget boundary, NOT inside the strip. That
  // division of labour is part of the fix: `hasAltitudeProfile`,
  // `drawableSegmentCount` and the painter loop must all read the SAME list, so
  // a second filter inside the widget would silently redefine the segment count.
  // Pin the contract from the other side: hand the widget a list that already
  // contains a rejected fix and show it draws it untouched.
  testWidgets('the strip draws exactly the list it is handed — it never filters', (
    tester,
  ) async {
    final up = _p(0, 0, 10);
    final spike = _rejected(0.0002, 0, 12); // ordinary by value, rejected by type
    final peak = _p(0.0004, 0, 999); // the wild reading is a kept one

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ElevationStrip(points: [up, spike, peak]))),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<ElevationStripPainter>()
        .single;
    // Untouched: all three entries, in the order given, including the reject.
    expect(painter.points, [up, spike, peak]);
    expect(drawableSegmentCount(painter.points), 2);
  });
}
