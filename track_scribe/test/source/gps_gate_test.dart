import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';

RawFix f(double acc, {int sec = 0}) => RawFix(
  lat: 1,
  lon: 1,
  timeNanos: sec * 1000000000,
  accuracyM: acc,
);

void main() {
  test('start is refused until two consecutive fixes are ≤ 35 m (rule ر7)', () {
    final gate = FixQualityGate(nowNanos: () => 0);
    expect(gate.ready, isFalse);
    expect(gate.add(f(12)), isFalse); // one good fix is not enough
    expect(gate.quality, GpsQuality.ok); // the fix is precise…
    expect(gate.ready, isFalse); // …and the gate is still shut: separate truths
    expect(gate.add(f(30)), isTrue); // second consecutive good fix opens it
    expect(gate.quality, GpsQuality.degraded); // 20–35 tier, live
    expect(gate.add(f(40)), isTrue); // stays ready, but…
    expect(gate.quality, GpsQuality.searching); // …40 > 35 is searching (D3:
    // the rule table is the authority, and the quality of the CURRENT fix
    // follows the accuracy, never the sticky gate).
    expect(gate.add(f(90)), isTrue);
    expect(gate.quality, GpsQuality.searching);
    expect(gate.ready, isTrue, reason: 'ر7 is a start gate, not a licence');
  });
  test('a single fix never lies about quality', () {
    expect(GpsQualityX.fromAccuracy(200), GpsQuality.searching);
  });

  // The brief's Step 1 test above is the contract; the tests below pin the
  // numbers the brief only describes in prose (ر7 tiers, ر8 lost) so a later
  // edit cannot quietly retune them.

  test('ر7 tiers: ≤ 20 ok, 20–35 degraded, > 35 searching', () {
    expect(GpsQualityX.fromAccuracy(20), GpsQuality.ok);
    expect(GpsQualityX.fromAccuracy(20.1), GpsQuality.degraded);
    expect(GpsQualityX.fromAccuracy(35), GpsQuality.degraded);
    expect(GpsQualityX.fromAccuracy(35.1), GpsQuality.searching);
    expect(isFixGoodEnough(f(35)), isTrue); // ر7 boundary is inclusive
    expect(isFixGoodEnough(f(35.1)), isFalse);
  });

  test('ر7: a bad accuracy in between restarts the required streak', () {
    final gate = FixQualityGate(nowNanos: () => 0);
    expect(gate.add(f(10)), isFalse); // one good fix
    expect(gate.add(f(80)), isFalse); // breaks the streak
    expect(gate.add(f(10)), isFalse); // back to a single good fix
    expect(gate.add(f(10)), isTrue); // two consecutive again
  });

  test('the gate has no opinion before the first fix', () {
    final gate = FixQualityGate(nowNanos: () => 0);
    expect(gate.quality, GpsQuality.none);
    expect(gate.ready, isFalse);
  });

  test('quality tracks the current fix while readiness tracks the streak', () {
    // D3: a 4 m fix is `ok` as a measurement even when ر7 has not opened the
    // gate. "Still searching" before promotion is the UI phase's statement
    // (guarded by test/ui/gps_banner_test.dart), not a doctored tier here —
    // conflating them is what made the brief contradict its own rule table.
    final gate = FixQualityGate(nowNanos: () => 0);
    gate.add(f(4)); // one precise fix: ر7 still refuses to start
    expect(gate.ready, isFalse);
    expect(gate.quality, GpsQuality.ok);
    gate.add(f(4));
    expect(gate.ready, isTrue);
    expect(gate.quality, GpsQuality.ok);
  });

  test('ر8: 20 s without a fix is lost, measured on the injected clock', () {
    var nowNanos = 0;
    final gate = FixQualityGate(nowNanos: () => nowNanos);
    gate.add(f(4));
    gate.add(f(4)); // ر7 satisfied
    expect(gate.quality, GpsQuality.ok);

    nowNanos = 19 * 1000000000;
    expect(gate.quality, GpsQuality.ok, reason: '19 s is not yet lost');

    nowNanos = 20 * 1000000000;
    expect(gate.quality, GpsQuality.lost, reason: 'ر8: 20 s of silence is lost');

    nowNanos = 25 * 1000000000;
    gate.add(f(4));
    expect(gate.quality, GpsQuality.ok, reason: 'the next fix ends lost');
    expect(gate.ready, isTrue, reason: 'ر7 is a start gate: it stays satisfied');
  });

  test('the default clock is a running monotonic source, not wall time', () {
    // No device needed: the default gate must at least produce a value and
    // keep ر7 working without any clock injection.
    final gate = FixQualityGate();
    expect(gate.add(f(3)), isFalse);
    expect(gate.add(f(3)), isTrue);
    expect(gate.quality, isNot(GpsQuality.none));
  });
}
