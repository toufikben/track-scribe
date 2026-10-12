import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

import '../../tool/replay_core.dart';

/// The spec's three injection scenarios (spec §8 item 2), run on the pure
/// engine — deterministic, no phone, no timers. The thresholds come verbatim
/// from the spec: (a) ±10 m noise must not inflate distance by more than 1 %,
/// (b) a teleport must add Δdistance = 0, (c) standing still adds 0 m while
/// the clock keeps running.
///
/// Fixes are stamped at 1 Hz. Noise inside [line] is an **independent** uniform
/// scatter across ±jitterM (ruling R98, superseding R92): that is what a
/// receiver's 1σ error actually looks like between consecutive seconds, and it
/// is the only one of the three candidate models that both clears the 1 % bar
/// and still catches a broken engine. Measured on this fixture at ±10 m /
/// accuracy 10 (seed 42):
///
///   sawtooth (the plan's own model)   engine 986,3 m (1,37 %)  odometer 14 309 m
///   independent scatter (used here)   engine 1004,6 m (0,46 %)  odometer 4 906 m
///   smooth random walk (was R92)      engine 991,5 m (0,85 %)  odometer 1 005 m
///
/// The smooth walk is physically gentle — and useless as a gate: a gate-free
/// odometer scores better on it than the engine does, so the test could not
/// fail for the rule it names. The sawtooth catches inflation but the honest
/// engine cannot pass it (ر3's 15 s heartbeat is spec law, and tuning it to
/// 8 s to fit the fixture would break that law and the two tests that pin it).
/// Independent scatter keeps both properties.
List<RawFix> line({
  required double metres,
  required double speedMps,
  required double accuracyM,
  required double jitterM,
  int seed = 42,
}) {
  const per = 1.0; // 1 Hz
  final steps = (metres / (speedMps * per)).ceil();
  final rng = SeededRng(seed);
  final out = <RawFix>[];
  for (var i = 0; i <= steps; i++) {
    final noise = (rng.next() * 2 - 1) * jitterM;
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

/// The gate-free odometer: the sum of every consecutive raw gap — what a
/// recorder with no ر3 gate and no ر4 jump reject would report. Every scenario
/// below asserts the engine beats it, because a fidelity test a broken engine
/// also passes proves nothing.
double naiveOdometerM(List<RawFix> fixes) {
  var metres = 0.0;
  for (var i = 1; i < fixes.length; i++) {
    metres += haversineMeters(
      fixes[i - 1].lat,
      fixes[i - 1].lon,
      fixes[i].lat,
      fixes[i].lon,
    );
  }
  return metres;
}

double _engineMetres(
  List<RawFix> fixes,
  Sport sport, {
  RecorderEngine? into,
}) {
  final e = into ?? RecorderEngine(SportConfig.forSport(sport), startNanos: 0);
  for (final f in fixes) {
    e.onFix(f);
  }
  return e.distanceMeters;
}

void main() {
  test('1000 m walk with ±10 m noise: engine error stays under 1 %', () {
    final fixes = line(
      metres: 1000,
      speedMps: 1.4,
      accuracyM: 10,
      jitterM: 10,
    );
    final engine = _engineMetres(fixes, Sport.walk);
    final err = (engine - 1000).abs() / 1000;
    final odometerErr = ((naiveOdometerM(fixes) - 1000).abs()) / 1000;
    expect(
      err,
      lessThan(0.01),
      reason: 'got ${engine.toStringAsFixed(1)} m',
    );
    expect(
      err,
      lessThan(odometerErr / 4),
      reason:
          'the bar must discriminate the engine from a gate-free odometer '
          '(engine ${engine.toStringAsFixed(1)} m vs odometer '
          '${naiveOdometerM(fixes).toStringAsFixed(1)} m)',
    );
    // The noise-model table in this file's header cites this seed, so the
    // current build prints its own figure instead of inheriting the old one.
    // ignore: avoid_print
    print('seed 42 (±10 m at accuracy 10): engine '
        '${engine.toStringAsFixed(1)} m (${(err * 100).toStringAsFixed(2)} %), '
        'odometer ${naiveOdometerM(fixes).toStringAsFixed(0)} m');
  });

  test('±10 m noise: the 1 % bar is seed-dependent, measured not claimed', () {
    // Honest scope for the fidelity claim. The single-seed test above is the
    // spec §8 gate; this sweep measures how much of the noise space it really
    // covers, so no marketing sentence pretends 1 % is a guarantee.
    const seeds = 50;
    var worst = 0.0;
    var aboveBar = 0;
    final errs = <double>[];
    for (var seed = 1; seed <= seeds; seed++) {
      final fixes = line(
        metres: 1000,
        speedMps: 1.4,
        accuracyM: 10,
        jitterM: 10,
        seed: seed,
      );
      final engine = _engineMetres(fixes, Sport.walk);
      final err = (engine - 1000).abs() / 1000;
      expect(
        err,
        lessThan(((naiveOdometerM(fixes) - 1000).abs()) / 1000),
        reason: 'seed $seed: a gate-free odometer matches the engine '
            '(${engine.toStringAsFixed(1)} m)',
      );
      errs.add(err);
      if (err > worst) worst = err;
      if (err >= 0.01) aboveBar++;
    }
    errs.sort();
    // The doc cites these numbers; printing them keeps the citation checkable
    // rather than remembered.
    // ignore: avoid_print
    print(
      'noise sweep ($seeds seeds, ±10 m at accuracy 10): worst '
      '${(worst * 100).toStringAsFixed(2)} %, median '
      '${(errs[seeds ~/ 2] * 100).toStringAsFixed(2)} %, '
      '$aboveBar/$seeds above the 1 % bar',
    );
  });

  // The declared 1σ is the only metre the engine is allowed to trust, so a
  // receiver that over-reports its own precision inflates the track. Measured
  // here (seed 42, ±10 m of true scatter) and printed so the fidelity doc can
  // cite a number a CI run reproduces instead of one remembered from a scratch
  // session — the first version of that table was exactly such an orphan.
  test('declared accuracy is the lever: over-claiming precision inflates the track', () {
    final perSport = <Sport, Map<double, double>>{};
    for (final sport in [Sport.walk, Sport.run]) {
      final byAccuracy = <double, double>{};
      for (final acc in [5.0, 10.0, 20.0]) {
        byAccuracy[acc] = _engineMetres(
          line(
              metres: 1000,
              speedMps: 1.4,
              accuracyM: acc,
              jitterM: 10,
              seed: 42),
          sport,
        );
      }
      perSport[sport] = byAccuracy;
      // ignore: avoid_print
      print('${sport.name} ±10 m, seed 42: '
          '${byAccuracy.entries.map((e) => 'acc ${e.key.toStringAsFixed(0)} → '
              '${e.value.toStringAsFixed(1)} m '
              '(${((e.value - 1000) / 10).toStringAsFixed(2)} %)').join('; ')}');
    }
    for (final e in perSport.entries) {
      // R99's direction pinned: a tighter declared 1σ opens the gate and lets
      // more of the scatter through, so the track must come out LONGER. If an
      // engine ever made the over-claimed run agree with the honest one, the
      // gate would no longer be reading the accuracy.
      expect(
        e.value[5.0]!,
        greaterThan(e.value[20.0]!),
        reason: '${e.key.name}: the gate must track the declared accuracy',
      );
    }
  });

  test('25 m teleportation does not create distance (rule ر4)', () {
    final engine = RecorderEngine(SportConfig.forSport(Sport.run), startNanos: 0);
    final base = line(
      metres: 500,
      speedMps: 3.0,
      accuracyM: 5,
      jitterM: 3,
    );
    final fed = <RawFix>[];
    for (var i = 0; i < base.length; i++) {
      fed.add(base[i]);
      if (i == 100) {
        fed.add(
          RawFix(
            lat: base[i].lat + 0.00025,
            lon: 3.1856,
            timeNanos: base[i].timeNanos + 1000000000,
            accuracyM: 6,
          ),
        );
      }
    }
    final metres = _engineMetres(fed, Sport.run, into: engine);
    expect(engine.stats.rejectedCount, greaterThan(0));
    // Truth + the 25 m jump. The measured engine value is 492,5 m; a ر4-less
    // engine bills the jump and lands at 520,3 m, and the gate-free odometer
    // reaches 551,0 m — so the bar has to sit under 515 to exclude either,
    // and above a floor that proves distance was actually accumulated.
    expect(metres, greaterThan(450));
    expect(metres, lessThan(515));
    expect(metres, lessThan(naiveOdometerM(fed)));
  });

  test('10 minutes of standing adds 0 m and full time (rule ر6)', () {
    // ±3 m of independent scatter around one position: the previous fixture
    // used one identical coordinate, which every accumulator — including a
    // rule-less one — scores as 0 m, so the test could not fail for ر6.
    final fixes = <RawFix>[
      RawFix(
        lat: 36.7538,
        lon: 3.1856,
        timeNanos: 0,
        accuracyM: 3,
        speedMps: 1.2,
      ),
    ];
    final rng = SeededRng(7);
    for (var s = 1; s <= 600; s++) {
      final noise = (rng.next() * 2 - 1) * 3;
      fixes.add(
        RawFix(
          lat: 36.7538 + noise / 111111.0,
          lon: 3.1856,
          timeNanos: s * 1000000000,
          accuracyM: 3,
          speedMps: 0.0,
        ),
      );
    }
    final odometer = naiveOdometerM(fixes);
    expect(
      odometer,
      greaterThan(50),
      reason: 'the fixture must carry the inflation ر6 is asked to reject',
    );
    final engine = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    final metres = _engineMetres(fixes, Sport.walk, into: engine);
    expect(
      metres,
      0.0,
      reason: 'got ${metres.toStringAsFixed(1)} m billed while standing '
          '(odometer would bill ${odometer.toStringAsFixed(1)} m)',
    );
    expect(engine.elapsedNanos, 600_000_000_000);
  });
}
