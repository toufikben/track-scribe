import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/engine/splits.dart';

RawFix at({required double dLat, required int sec, double? speed}) => RawFix(
      lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
      timeNanos: sec * 1000000000, accuracyM: 3, speedMps: speed);

void main() {
  test('re6: 5 minutes standing still costs zero distance but full time', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    e.onFix(at(dLat: 0, sec: 0, speed: 1.4));
    for (var s = 1; s <= 300; s++) {
      e.onFix(at(dLat: 0, sec: s, speed: 0.0));   // same coordinates, stopped
      expect(e.distanceMeters, 0.0, reason: 'drift inflated at second $s');
    }
    expect(e.isIdle, isTrue);
    expect(e.elapsedNanos, 300_000_000_000);
    expect(e.storedPoints.where((p) => p.type == WaypointType.idle), isNotEmpty);
  });

  test('a 1 km straight-line walk yields one full split at true distance', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    // Ruling R9: at accuracy 3 m the spec ر3 gate is max(3, 2*3) = 6 m — NOT
    // the 3 + 2*3 = 9 m arithmetic the brief's draft comment carried.
    // 5.004 m single steps stay under the gate; the anchor only advances on
    // every second fix (10.008 m), so stores land every other step.
    const mPerStep = 5.0;
    for (var i = 0; i * mPerStep <= 1000; i++) {
      e.onFix(at(dLat: i * mPerStep, sec: i * 4, speed: 1.25));
    }
    expect(e.distanceMeters, closeTo(1000, 6));
    final splits = computeSplits(e.storedPoints);
    expect(splits.length, 1);
    expect(splits.first.kmIndex, 1);
    expect(splits.first.paceSecPerKm, greaterThan(0));
  });

  test('computeSplits is empty before the first kilometre', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    for (var i = 0; i <= 60; i++) { e.onFix(at(dLat: i * 10.0, sec: i * 8, speed: 1.25)); }
    expect(e.distanceMeters, greaterThan(400));
    expect(computeSplits(e.storedPoints), isEmpty);
  });

  // R11 regression: the brief's pace note computed
  //   prevNanos = out.isEmpty ? startNanos : out.last.elapsedNanos
  // which mixes a RELATIVE split time (elapsedNanos is nanosAt - startNanos)
  // with an ABSOLUTE fix time (nanosAt). With startNanos == 0 the two coincide,
  // so the brief's own tests cannot see the defect — this fixture offsets the
  // session by 1000 s to expose it: the buggy split-2 pace comes out ~1000 s
  // too large.
  test('R11: second split pace is the second kilometre only', () {
    final sessionStart = 1000 * 1000000000;
    RawFix atOffset({required double dLat, required int sec, double? speed}) => RawFix(
          lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
          timeNanos: sessionStart + sec * 1000000000, accuracyM: 3, speedMps: speed);
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: sessionStart);
    const mPerStep = 5.0;
    for (var i = 0; i * mPerStep <= 2000; i++) {
      e.onFix(atOffset(dLat: i * mPerStep, sec: i * 4, speed: 1.25));
    }
    expect(e.distanceMeters, closeTo(2000, 12));
    final pts = e.storedPoints;
    final splits = computeSplits(pts);
    expect(splits.length, 2);
    expect(splits[0].kmIndex, 1);
    expect(splits[1].kmIndex, 2);
    expect(splits[1].elapsedNanos, greaterThan(splits[0].elapsedNanos));

    // Expected pace derived from the fixture's OWN timestamps, independently
    // of computeSplits' interpolation: stores form a uniform meridian polyline
    // (each stored segment is the identical dLat arc, 8 s apart), so covering
    // 1000 m of path takes exactly 1000/segM segments no matter where the
    // kilometre starts. Tolerance 0.5 s is generous: the only errors are the
    // sub-ns (segTime*frac).round() and float drift over ~200 identical arcs
    // (sub-millimetre => sub-millisecond of time), while the buggy formula is
    // off by the full 1000 s session offset.
    final segM = pts[0].distanceTo(pts[1]);
    final segNs = (pts[1].timeNanos - pts[0].timeNanos) / 1e9;
    final kmSecs = 1000.0 / segM * segNs; // ~799.4 s, i.e. 1.25 m/s
    expect(kmSecs, closeTo(799.4, 0.5));
    expect(splits[0].paceSecPerKm, closeTo(kmSecs, 0.5));
    expect(splits[1].paceSecPerKm, closeTo(kmSecs, 0.5));
    // Elapsed at each crossing is relative to startNanos (R10): km2 is crossed
    // at ~2 * kmSecs into the session.
    expect(splits[1].elapsedNanos / 1e9, closeTo(2 * kmSecs, 0.5));
  });

  // ر9 polyline semantics + ر6 zero-length segments, exercised directly on
  // computeSplits so the rejected-skip and the seg == 0 guard are pinned
  // without depending on engine fixture tuning.
  test('computeSplits skips rejected points and survives zero-length idle segments', () {
    StoredPoint sp(double dLat, int sec, WaypointType type) => StoredPoint(
        lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
        timeNanos: sec * 1000000000, accuracyM: 3, type: type);
    final m500 = haversineMeters(36.7538, 3.1856, 36.7538 + 500 / 111111.0, 3.1856);
    expect(m500, closeTo(500.378, 1)); // sanity: 1 dLat unit ~ 1.00076 m here
    final pts = [
      sp(0, 0, WaypointType.normal),
      sp(60000, 10, WaypointType.rejected), // 60 km ghost: never part of the path
      sp(500, 20, WaypointType.normal),     // ~500.4 m along the true path
      sp(500, 35, WaypointType.idle),       // idle heartbeat, same coords — seg == 0
      sp(500, 50, WaypointType.idle),       // again — must not divide by zero
      sp(1000, 60, WaypointType.normal),    // crosses 1000 m on this segment
      sp(1000, 75, WaypointType.idle),      // trailing idle — no extrapolation past it
    ];
    final splits = computeSplits(pts);
    // If rejected points were treated as path, the 60 km jump would place the
    // first crossing between t=0 and t=10 instead of near t=60.
    expect(splits.length, 1);
    expect(splits.single.kmIndex, 1);
    expect(splits.single.distanceM, 1000.0);
    // Crossing fraction on the 500->1000 segment, then linear time: expected
    // within 1 ms (only the sub-ns .round() and float noise separate us).
    final frac = (1000.0 - m500) / m500;
    expect(splits.single.elapsedNanos, closeTo((50 + 10 * frac) * 1e9, 1e6));
    expect(splits.single.paceSecPerKm, closeTo(50 + 10 * frac, 0.001));
  });
}
