import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/ui/basemap/follow_policy.dart';

/// Device-found defect (realme, 2026-10-14): while a session ran, the band
/// recentered on every rebuild — the timer alone rebuilds once a second — and
/// each programmatic move restarts the vector tile fetch. On a two-core phone
/// the decode takes longer than the interval between moves, so the map went
/// blank for the whole recording and only came back after a finger gesture
/// turned following off (screenshots 10/12 vs 13/14 in the round notes).
///
/// The rule that prevents it: a fix that still lands inside the visible band
/// is not worth a move.
void main() {
  const centre = LatLng(36.7525, 3.042);
  const mpp = 2.0; // metres per pixel
  const shortSide = 500.0; // px → half band = 250 px = 500 m, tolerance 300 m

  LatLng northBy(double metres) =>
      LatLng(centre.latitude + metres / 111320, centre.longitude);

  test('a fix at the camera centre never moves the map', () {
    expect(
      shouldRecenter(
        center: centre,
        target: centre,
        metresPerPixel: mpp,
        bandShortSidePx: shortSide,
      ),
      isFalse,
    );
  });

  test('jitter inside the band is absorbed, not chased', () {
    for (final metres in [10.0, 100.0, 290.0]) {
      expect(
        shouldRecenter(
          center: centre,
          target: northBy(metres),
          metresPerPixel: mpp,
          bandShortSidePx: shortSide,
        ),
        isFalse,
        reason: '$metres m of drift is still ${metres / (mpp * shortSide / 2) * 100}% into the half band',
      );
    }
  });

  test('a fix past the tolerance recenters', () {
    for (final metres in [310.0, 1000.0]) {
      expect(
        shouldRecenter(
          center: centre,
          target: northBy(metres),
          metresPerPixel: mpp,
          bandShortSidePx: shortSide,
        ),
        isTrue,
        reason: '$metres m would push the marker off the visible band',
      );
    }
  });

  test('with no camera scale yet the first fix always centers', () {
    expect(
      shouldRecenter(
        center: centre,
        target: northBy(1),
        metresPerPixel: 0,
        bandShortSidePx: shortSide,
      ),
      isTrue,
      reason: 'a scale-less camera cannot host a marker — centre it once',
    );
  });

  test('the tolerance scales with zoom: the same drift moves at high zoom', () {
    final target = northBy(200);
    expect(
      shouldRecenter(
        center: centre,
        target: target,
        metresPerPixel: 2.0,
        bandShortSidePx: shortSide,
      ),
      isFalse,
    );
    expect(
      shouldRecenter(
        center: centre,
        target: target,
        metresPerPixel: 0.5, // zoomed in → the band shows only 125 m
        bandShortSidePx: shortSide,
      ),
      isTrue,
    );
  });
}
