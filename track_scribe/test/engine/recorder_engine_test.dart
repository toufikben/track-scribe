import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/gps_quality.dart' show unmeasuredAccuracyM;

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

  test('re3/R99: the gate follows the noise instead of capping under it', () {
    // Spec ر3 read `max(3, 2a)` capped at 25 m. With a good signal the cap
    // never binds (2 × 12.5 = the same 25 m); with a poor one it demanded less
    // movement than the fix was uncertain about, and the difference became
    // phantom distance — 375.1 m for a phone on a desk
    // (test/evidence/fixtures/real/stationary/). R99 removed the ceiling.
    expect(cfg.gateFor(12.5), 25.0);  // the cap's old saturation point: unchanged
    expect(cfg.gateFor(99), 198.0);   // R99: 2 × accuracy, no ceiling
    expect(cfg.gateFor(0.5), 3.0);    // ر3's floor: unchanged
  });

  // R99, measured: the desk sessions at accuracy 18.7–82 m stored every point
  // the old 25 m cap allowed and billed the noise between them.
  test('R99: at accuracy 30 m a 30 m noise step is below the gate, not a store', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0, acc: 30));
    e.onFix(walk(dLat: 30, sec: 10, acc: 30)); // 30.02 m in 10 s = 3.0 m/s: legit speed, under gate
    expect(e.storedPoints.length, 1);
    expect(e.distanceMeters, 0.0);
    e.onFix(walk(dLat: 70, sec: 20, acc: 30)); // 70.05 m ≥ gate 60 → the first real store
    expect(e.distanceMeters, closeTo(70.05, 0.05));
  });

  // R100: the Realme's provider reported 1.1–4.7 m/s for a phone lying on a
  // desk (test/evidence/fixtures/real/stationary/). The speed claim still
  // drives ر6's LABEL exactly as the spec words it — what R100 removes is its
  // reach into the odometer. Distance honesty is carried by R99 (the gate
  // tracks the noise) and R101 (the heartbeat never bills below it), so a
  // fabricated speed cannot mint a metre whatever it claims.
  test('R100: a fabricated speed cannot mint distance from a phone on a desk', () {
    RawFix desk(int sec) => RawFix(
          lat: 36.7538 + (sec.isEven ? 8 : -8) / 111111.0, lon: 3.1856,
          timeNanos: sec * 1000000000, accuracyM: 30, speedMps: 4.7,
        );
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(RawFix(
        lat: 36.7538, lon: 3.1856, timeNanos: 0, accuracyM: 30, speedMps: 4.5));
    for (var s = 1; s <= 40; s++) {
      e.onFix(desk(s));
      expect(e.distanceMeters, 0.0, reason: 'phantom drift at second $s');
    }
    expect(
      e.storedPoints.skip(1)
          .every((p) => p.type == WaypointType.idle || p.type == WaypointType.rejected),
      isTrue,
      reason: 'the desk produced no billed point: every append after the first '
          'is a ر3 marker or a ر5 rejection (±8 m in 1 s implies 16 m/s)',
    );
    expect(e.elapsedNanos, 40_000_000_000); // ر6: time keeps flowing
  });

  // R74's sentinel with R99: a fix whose 1σ was never measured bounds no
  // distance at all. The gate is infinite, so nothing bills and nothing moves
  // the yardstick — maximum caution, never permissiveness.
  test('R74/R99: an unmeasured accuracy bills nothing even at running speed', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0, acc: unmeasuredAccuracyM));
    for (var s = 1; s <= 20; s++) {
      e.onFix(walk(dLat: 5.0 * s, sec: s, acc: unmeasuredAccuracyM)); // 5 m/s of real position
      expect(e.distanceMeters, 0.0, reason: 'billed against an unmeasured 1σ at $s');
    }
    expect(e.storedPoints.first.type, WaypointType.normal);
    expect(
      e.storedPoints.skip(1).every((p) => p.type == WaypointType.idle),
      isTrue,
      reason: 'with an infinite gate only the ر3 heartbeat markers can be '
          'appended, and a marker bills nothing',
    );
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

  test('re3/R101 heartbeat: 15 s with no movement stores a point and no distance', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 10, sec: 0));
    e.onFix(walk(dLat: 12, sec: 16)); // 2.0015 m (inside gate) but 16 s ≥ 15 s
    expect(e.storedPoints.length, 2); // ر3 keeps its promise: a point exists
    // R101: it is a marker, not progress. The old heartbeat branch billed
    // whatever sub-gate displacement the noise happened to reach — one of the
    // two doors the desk phantom came through (375.1 m at 12.5 m per store).
    expect(e.storedPoints.last.type, WaypointType.idle);
    expect(e.distanceMeters, 0.0);
  });

  test('R101: a heartbeat below the gate appends without billing, above it still bills', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0)); // gate(acc 4) = 8 m
    e.onFix(walk(dLat: 6, sec: 15)); // 6.005 m: below the gate, heartbeat due
    expect(e.storedPoints.length, 2); // the point is kept (ر3/ر9)
    expect(e.distanceMeters, 0.0); // and is not billed (R101)
    e.onFix(walk(dLat: 20, sec: 20)); // 20.02 m ≥ gate → real movement, billed once
    expect(e.distanceMeters, closeTo(20.015, 0.01));
    expect(e.storedPoints.length, 3);
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

  test('fix-r2 #1: idle→resume appends EXACTLY one point and bills the pending movement once', () {
    // Scenario A: the resume movement exceeds the store gate. Buggy flow:
    // _updateIdle's resume branch appended the fix (addDistance:false), then
    // the gate branch re-ran for the SAME fix and appended it again with
    // +0 m (the anchor was already the fix itself) — double polyline entry,
    // zero billing of the real 10 m.
    final seen = <(int, WaypointType)>[];
    final e = RecorderEngine(cfg, startNanos: 0,
        rawSink: (fix, verdict) => seen.add((fix.timeNanos ~/ 1000000000, verdict)));
    e.onFix(walk(dLat: 0, sec: 0));
    for (int t = 1; t <= 13; t++) { e.onFix(walk(dLat: 0, sec: t)); } // entry marker @13
    expect(e.isIdle, isTrue);
    expect(e.storedPoints.length, 2);            // normal@0 + idle marker@13
    e.onFix(walk(dLat: 10, sec: 15));            // dt=2 s → 5.00 m/s resumes, d=10.008 m ≥ gate
    expect(e.isIdle, isFalse);
    expect(e.storedPoints.length, 3);            // exactly ONE append for fix@15
    expect(e.distanceMeters, closeTo(10.0076, 0.01)); // the pending d billed ONCE
    expect(seen.last, (15, WaypointType.normal));// truthful verdict for an appended fix
    expect(seen.length, e.stats.fixCount);       // sink still called exactly once

    // Scenario B (fix round 3, R100/R101): movement BELOW the gate that ENDS
    // the idle label. The shipped build billed 5.0038 m here because the resume
    // itself was treated as evidence of movement — a table claiming 5 m/s
    // therefore minted metres. Under R100 the speed claim only clears the flag;
    // the sub-gate displacement stays pending, nothing is appended and nothing
    // is billed until the gate (R99) actually opens.
    final seenB = <(int, WaypointType)>[];
    final b = RecorderEngine(cfg, startNanos: 0,
        rawSink: (fix, verdict) => seenB.add((fix.timeNanos ~/ 1000000000, verdict)));
    b.onFix(walk(dLat: 0, sec: 0));
    for (int t = 1; t <= 13; t++) { b.onFix(walk(dLat: 0, sec: t)); } // entry marker @13
    b.onFix(walk(dLat: 5, sec: 14));             // dt=1 s → 5.0038 m < gate 8 m
    expect(b.storedPoints.length, 2);            // no append: below the noise floor
    expect(b.distanceMeters, 0.0);
    expect(seenB.last, (14, WaypointType.skipped)); // no append → the honest verdict
    b.onFix(walk(dLat: 10, sec: 16));            // 10.008 m ≥ gate → one append, billed once
    expect(b.storedPoints.length, 3);
    expect(b.distanceMeters, closeTo(10.0076, 0.01));
    expect(b.isIdle, isFalse);
    expect(seenB.last, (16, WaypointType.normal));
    expect(seenB.length, b.stats.fixCount);      // sink still called exactly once
  });

  test('fix-r2 #2: ر3 idle heartbeat fires while idle with a stale anchor (ر6 keeps distance frozen)', () {
    // Enter idle @13, then creep at 0.3 m/s — below idleSpeedMps, so the user
    // is "moving while flagged idle". Buggy flow: the heartbeat compared
    // against the anchor, which during idle only moves via idle appends, and
    // the _lastWasIdleMarker guard suppressed them permanently → @28 (15 s
    // after the last append) nothing was appended.
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0));
    for (int t = 1; t <= 13; t++) { e.onFix(walk(dLat: 0, sec: t)); }
    expect(e.storedPoints.length, 2);            // normal + entry marker
    expect(e.isIdle, isTrue);
    for (int t = 14; t <= 27; t++) { e.onFix(walk(dLat: 0.3 * (t - 13), sec: t)); }
    expect(e.storedPoints.length, 2);            // 14 s since last append < 15 s
    expect(e.distanceMeters, 0.0);               // no premature billing
    e.onFix(walk(dLat: 4.5, sec: 28));           // exactly 15 s after the marker
    expect(e.isIdle, isTrue);                    // 0.3 m/s — still idle (ر6)
    expect(e.storedPoints.length, 3);            // the idle heartbeat fired
    final hb = e.storedPoints.last;
    expect(hb.type, WaypointType.idle);
    expect(hb.timeNanos, 28_000_000_000);
    expect(e.distanceMeters, 0.0);               // ر6: time flows, distance stops
    // Next heartbeat is 15 s after that APPEND, not after the anchor.
    for (int t = 29; t <= 42; t++) { e.onFix(walk(dLat: 0.3 * (t - 13), sec: t)); }
    expect(e.storedPoints.length, 3);            // 14 s — nothing yet
    e.onFix(walk(dLat: 8.7, sec: 43));           // 15 s after the @28 append
    expect(e.storedPoints.length, 4);
    expect(e.storedPoints.last.type, WaypointType.idle);
    expect(e.storedPoints.last.timeNanos, 43_000_000_000);
    expect(e.distanceMeters, 0.0);
  });
}
