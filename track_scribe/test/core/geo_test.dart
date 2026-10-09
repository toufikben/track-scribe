import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';

void main() {
  test('one metre of latitude is ~111.19 km per degree', () {
    expect(haversineMeters(36.7538, 3.1856, 36.7539, 3.1856), closeTo(11.12, 0.5));
  });
  test('a known Algiers corridor is within 0.3% of geodesic length', () {
    // 1 km walked due east at 36.75N: longitude delta for 1000 m
    const dLon = 1000 / (111412.0 * 0.8013); // approx m per degree at 36.75N
    final d = haversineMeters(36.7538, 3.1856, 36.7538, 3.1856 + dLon);
    expect((d - 1000).abs() / 1000, lessThan(0.003));
  });
  test('identical points are zero', () => expect(haversineMeters(1, 2, 1, 2), 0));
  test('bearing east is ~90°', () {
    expect(bearingDeg(36.75, 3.18, 36.75, 3.19), closeTo(90, 0.5));
  });
}
