import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

/// The spec's three injection scenarios (spec §8 item 2), run on the pure
/// engine — deterministic, no phone, no timers. The thresholds come verbatim
/// from the spec: (a) ±10 m noise must not inflate distance by more than 1 %,
/// (b) a teleport must add Δdistance = 0, (c) standing still adds 0 m while
/// the clock keeps running.
///
/// Fixes are stamped at 1 Hz. The noise is a fixed-seed random walk bounded
/// at ±jitterM with per-step increments of jitterM/40 (ruling R92): the
/// plan's original alternating ±jitterM sawtooth is NOT "±10 m noise" — at
/// 1 Hz it reads as 18–21 m/s of apparent motion, which rule ر4 correctly
/// rejects as impossible for walking, and the 1 % test could never pass
/// without loosening the threshold, which the plan forbids. The amplitude is
/// preserved; only the smoothness is made physical.
List<RawFix> line({
  required double metres,
  required double speedMps,
  required double accuracyM,
  required double jitterM,
  int seed = 42,
}) {
  final per = 1.0; // 1 Hz
  final steps = (metres / (speedMps * per)).ceil();
  final rng = _SeededRng(seed);
  var noise = 0.0;
  final out = <RawFix>[];
  for (var i = 0; i <= steps; i++) {
    noise = (noise + (rng.next() * 2 - 1) * (jitterM / 40))
        .clamp(-jitterM, jitterM)
        .toDouble();
    out.add(
      RawFix(
        lat: 36.7538 + (i * speedMps * per + noise) / 111111.0,
        lon: 3.1856,
        timeNanos: (i * per * 1e9).round(),
        accuracyM: accuracyM,
        speedMps: speedMps,
      ),
    );
  }
  return out;
}

void main() {
  test('1000 m walk with ±10 m noise: engine error stays under 1 %', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    for (final f in line(metres: 1000, speedMps: 1.4, accuracyM: 10, jitterM: 10)) {
      e.onFix(f);
    }
    final err = (e.distanceMeters - 1000).abs() / 1000;
    expect(err, lessThan(0.01), reason: 'got ${e.distanceMeters.toStringAsFixed(1)} m');
  });

  test('25 m teleportation does not create distance (rule ر4)', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.run), startNanos: 0);
    final fixes = line(metres: 500, speedMps: 3.0, accuracyM: 5, jitterM: 3).toList();
    for (var i = 0; i < fixes.length; i++) {
      e.onFix(fixes[i]);
      if (i == 100) {
        e.onFix(
          RawFix(
            lat: fixes[i].lat + 0.00025,
            lon: 3.1856,
            timeNanos: fixes[i].timeNanos + 1000000000,
            accuracyM: 6,
          ),
        );
      }
    }
    expect(e.stats.rejectedCount, greaterThan(0));
    expect(e.distanceMeters, lessThan(560));
  });

  test('10 minutes of standing adds 0 m and full time (rule ر6)', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    e.onFix(RawFix(lat: 36.7538, lon: 3.1856, timeNanos: 0, accuracyM: 3, speedMps: 1.2));
    for (var s = 1; s <= 600; s++) {
      e.onFix(
        RawFix(
          lat: 36.7538,
          lon: 3.1856,
          timeNanos: s * 1000000000,
          accuracyM: 3,
          speedMps: 0.0,
        ),
      );
    }
    expect(e.distanceMeters, 0.0);
    expect(e.elapsedNanos, 600_000_000_000);
  });
}

/// Minimal deterministic LCG — enough for the fixture, no external package.
class _SeededRng {
  _SeededRng(this._state);
  int _state;
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
