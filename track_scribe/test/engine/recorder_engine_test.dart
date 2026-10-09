import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

/// Fixture helper kept verbatim from the brief: dLat is a northward offset in
/// degrees-of-latitude units of 1/111111 deg, i.e. ~1.000757 m per unit on the
/// code's mean-radius sphere. Brief comments claimed ~100x smaller distances;
/// per controller ruling R7 the helper stays and the dLat magnitudes were
/// corrected to match each test's written intent.
RawFix walk({required double dLat, required int sec, double acc = 4}) => RawFix(
      lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
      timeNanos: sec * 1000000000, accuracyM: acc);

void main() {
  const cfg = SportConfig(sport: Sport.run, maxSpeedMps: 6.0);

  test('gate: accuracy 4 m → 8 m, and points inside the gate are not stored', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    // spec ر3: max(3, 2 × 4) = 8. The brief asserted 11.0, which its own
    // gateFor(0.5)==3.0 pin also contradicted — spec formula + controller
    // ruling R6 give 8.0.
    expect(cfg.gateFor(4), closeTo(8.0, 1e-9));
    e.onFix(walk(dLat: 0, sec: 0));            // first fix is always stored
    e.onFix(walk(dLat: 5, sec: 1));            // 5.0038 m — inside gate, skipped
    expect(e.storedPoints.length, 1);
    expect(e.distanceMeters, 0.0);
  });

  test('distance accumulates from the LAST STORED point, not the last fix', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 1));
    e.onFix(walk(dLat: 5, sec: 2));   // 5.0038 m from stored → inside gate, skipped
    e.onFix(walk(dLat: 12, sec: 4));  // 12.0091 m from STORED point → stored
    // Measured from last STORED. A last-FIX bug would give 7.0053 m, so this
    // pin discriminates ر2. (Brief's 22.52 ± 0.3 was unreachable with its own
    // constants; value recomputed independently, tolerance kept.)
    expect(e.distanceMeters, closeTo(12.009, 0.01));
    expect(e.storedPoints.length, 2);
  });

  test('re3: gate is capped at 25 m even for terrible accuracy', () {
    expect(cfg.gateFor(99), 25.0);
    expect(cfg.gateFor(0.5), 3.0);
  });

  test('re4: a 300 km teleport adds zero distance and is flagged rejected', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0));
    e.onFix(walk(dLat: 20, sec: 5));   // 20.015 m ≥ gate, 4.0 m/s → legit store
    final before = e.distanceMeters;
    expect(before, closeTo(20.015, 0.01));
    e.onFix(walk(dLat: 300000, sec: 6)); // 300 207 m jump → rejected
    expect(e.distanceMeters, before);      // the jump added ZERO distance
    expect(e.stats.rejectedCount, 1);
    expect(e.storedPoints.last.type, WaypointType.rejected);
    expect(e.storedPoints.last.distanceTo(e.storedPoints[e.storedPoints.length - 3]),
        greaterThan(1000)); // ≈ 300 227 m — the raw point is kept, never deleted
  });

  test('re3 heartbeat: 15 s with no movement still stores a point', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 10, sec: 0));
    e.onFix(walk(dLat: 12, sec: 16)); // 2.0015 m (inside gate) but 16 s ≥ 15 s
    expect(e.storedPoints.length, 2);
  });

  test('non-monotonic timestamps are dropped, not averaged', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 5));
    e.onFix(walk(dLat: 100, sec: 3)); // goes backwards
    expect(e.stats.droppedOutOfOrder, 1);
    expect(e.elapsedNanos, 5_000_000_000);
  });
}
