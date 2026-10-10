import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';

void main() {
  test('0.0001 degrees of latitude is ~11.12 m', () {
    expect(
      haversineMeters(36.7538, 3.1856, 36.7539, 3.1856),
      closeTo(11.12, 0.5),
    );
  });
  test('a known Algiers corridor is within 0.3% of geodesic length', () {
    // 1 km walked due east at 36.75N: longitude delta for 1000 m
    const dLon = 1000 / (111412.0 * 0.8013); // approx m per degree at 36.75N
    final d = haversineMeters(36.7538, 3.1856, 36.7538, 3.1856 + dLon);
    expect((d - 1000).abs() / 1000, lessThan(0.003));
  });
  test(
    'identical points are zero',
    () => expect(haversineMeters(1, 2, 1, 2), 0),
  );
  test('bearing east is ~90°', () {
    expect(bearingDeg(36.75, 3.18, 36.75, 3.19), closeTo(90, 0.5));
  });
  test('Earth radius is pinned to ~1e-5 relative', () {
    // One degree of latitude on the IUGG mean sphere R=6371008.8 is exactly
    // 2*R*asin(sin(0.5deg)) = R*pi/180 = 111195.080234 m. A tolerance of 1.0 m
    // (~9e-6 relative) rejects the equatorial 6378137 (111319.49 m) and the
    // polar 6356752 (110946.25 m) radii, so the constant cannot be swapped
    // silently.
    expect(haversineMeters(0, 0, 1, 0), closeTo(111195.08, 1.0));
  });
}
