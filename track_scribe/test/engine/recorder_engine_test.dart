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

  test('R39 freeze: a rejected jump must not become the yardstick for later fixes', () {
    // max(3, 2 x 4) = 8 m gate, v_max 2.5 m/s (ر3/ر5).
    final walkCfg = SportConfig.forSport(Sport.walk);
    final e = RecorderEngine(walkCfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0));       // first fix: anchor + stored
    e.onFix(walk(dLat: 50000, sec: 1));   // ~50 km impossible jump → rejected
    expect(e.storedPoints.last.type, WaypointType.rejected);
    // Honest 1.4 m/s walking resumes. At sec 6 the walker is 8.4 m from the
    // untouched anchor → the gate opens and distance must grow. da1c404's
    // bug: the jump became the yardstick, so sec 2 was rejected too (a real
    // fix that agrees with the anchor must never be rejected), later stores
    // accumulated from the bogus reference, and sustained noise freezes
    // accumulation entirely (controller: 100 % loss under alternating jitter).
    for (int k = 2; k <= 6; k++) { e.onFix(walk(dLat: 1.4 * k, sec: k)); }
    expect(e.stats.rejectedCount, 1);            // ONLY the jump was rejected
    expect(e.distanceMeters, greaterThan(0.0));  // distance grows after the jump
    final mid = e.distanceMeters;
    for (int k = 7; k <= 12; k++) { e.onFix(walk(dLat: 1.4 * k, sec: k)); }
    expect(e.distanceMeters, greaterThan(mid));  // accumulation keeps flowing
    // Pinned against the untouched anchor: two gate stores, 8.4 m each.
    // The buggy build yields 8.406 (one store measured from sec 2 dLat 1.4).
    expect(e.distanceMeters, closeTo(16.813, 0.05));
    expect(e.distanceMeters, lessThan(30.0));    // the 50 km jump is never billed
    expect(
      e.storedPoints.where((p) =>
              p.type == WaypointType.rejected &&
              p.distanceTo(e.storedPoints.first) > 10000)
          .length,
      greaterThanOrEqualTo(1)); // the jump raw point is kept, never deleted (ر9)
  });

  test('R40 re-acquisition: honest walking accrues again after a 500 m transport, gap never billed', () {
    final walkCfg = SportConfig.forSport(Sport.walk);
    final e = RecorderEngine(walkCfg, startNanos: 0);
    // Walk ~30 s at 1.4 m/s (1 dLat unit ≈ 1.000757 m).
    for (int t = 0; t <= 30; t++) { e.onFix(walk(dLat: 1.4 * t, sec: t)); }
    final preTransport = e.distanceMeters; // ~42 m walked, stored every 8 m gate
    expect(preTransport, closeTo(42.03, 0.2));
    // Teleport 500 m (car), then walk ~30 s more at the same honest speed.
    e.onFix(walk(dLat: 42 + 500, sec: 31));
    for (int k = 1; k <= 30; k++) { e.onFix(walk(dLat: 542 + 1.4 * k, sec: 31 + k)); }
    final total = e.distanceMeters;
    // R39 alone (anchor holds forever) would plateau at ~42 m; anchoring on
    // the jump point (da1c404) is the freeze bug. Post-transport walking
    // (≈ 4.2 m chain + four 8.4 m gate stores ≈ 37.8 m) must accrue.
    expect(total, greaterThan(preTransport + 20));
    expect(total, lessThan(100.0)); // 84 m of real walking — the 500 m gap never enters
    // The teleport itself is kept and flagged rejected (ر4/ر9), ~500 m from
    // the last honest store before it.
    final tp = e.storedPoints.firstWhere((p) => p.timeNanos == 31000000000);
    expect(tp.type, WaypointType.rejected);
    expect(tp.distanceTo(e.storedPoints[e.storedPoints.indexOf(tp) - 1]),
        closeTo(500.38, 1.0));
  });

  test('R41 sink: one synchronous verdict per accepted fix; dropped fixes never reach it', () {
    final seen = <(int, WaypointType)>[];
    final e = RecorderEngine(cfg, startNanos: 0,
        rawSink: (fix, verdict) => seen.add((fix.timeNanos ~/ 1000000000, verdict)));
    e.onFix(walk(dLat: 0, sec: 0));            // first fix stored → normal
    e.onFix(walk(dLat: 3, sec: 1));            // 3.002 m < gate 8 → skipped
    e.onFix(walk(dLat: 300000, sec: 2));       // 300 km jump → rejected
    expect(seen, [
      (0, WaypointType.normal),
      (1, WaypointType.skipped),
      (2, WaypointType.rejected),
    ]);
    e.onFix(walk(dLat: 100000, sec: 1));       // non-monotonic → dropped by ر1
    expect(e.stats.droppedOutOfOrder, 1);
    expect(seen.length, 3);                    // never reached the sink
    expect(seen.length, e.stats.fixCount);     // exactly one call per accepted fix

    // Idle verdicts: standing still (implied speed ~0 < 0.4 m/s) for > 12 s.
    final idleSeen = <WaypointType>[];
    final still = RecorderEngine(cfg, startNanos: 0,
        rawSink: (fix, verdict) => idleSeen.add(verdict));
    for (int t = 0; t <= 14; t++) { still.onFix(walk(dLat: 0.1, sec: t)); }
    expect(idleSeen.first, WaypointType.normal);          // first fix stored
    expect(idleSeen.sublist(1, 13),
        List.filled(12, WaypointType.skipped));           // still, not idle yet
    expect(idleSeen[13], WaypointType.idle);              // ر6 marker at t=13
    expect(idleSeen[14], WaypointType.idle);              // stays idle, time flows
    expect(still.distanceMeters, 0.0);
  });
}
