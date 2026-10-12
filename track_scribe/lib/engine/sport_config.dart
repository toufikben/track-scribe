import 'dart:math' as math;

enum Sport { walk, run, bike }

/// Per-sport engine constants — spec rules ر3–ر6.
class SportConfig {
  const SportConfig({
    required this.sport, required this.maxSpeedMps,
    this.minStoreDistanceM = 3.0, this.accuracyFactor = 2.0,
    this.forceStoreAfterS = 15.0,
    this.maxJumpM = 200.0, this.idleSpeedMps = 0.4, this.idleAfterS = 12.0,
  });
  final Sport sport;
  final double maxSpeedMps;      // ر5
  final double minStoreDistanceM, accuracyFactor; // ر3
  final double forceStoreAfterS; // ر3 heartbeat
  final double maxJumpM;         // ر4
  final double idleSpeedMps, idleAfterS; // ر6

  /// Store gate: `max(3 m, 2 × accuracy)` — spec ر3's floor and factor verbatim
  /// (the task-4 brief's draft had `3 + 2 × accuracy`, which contradicted the
  /// spec and its own `gateFor(0.5) == 3.0` test — controller ruling R6).
  ///
  /// R99 dropped ر3's 25 m CEILING. It was written for a good signal, and with
  /// one the clamp never binds (2 × 12.5 m reaches the same 25 m); with a poor
  /// one it sat BELOW the receiver's own error, so the gate demanded less
  /// movement than the fix was uncertain about and the engine billed the
  /// difference as distance. Measured on the Realme C33: four desk sessions at
  /// accuracy 24.9–53.5 m (`test/evidence/fixtures/real/stationary/`) billed
  /// 25.2–375.1 m for a phone that never moved. A gate may never ask for less
  /// displacement than the fix itself is uncertain about, so with
  /// `unmeasuredAccuracyM` (R74's infinity sentinel) the gate is infinite and
  /// nothing is billed against a 1σ that was never measured.
  double gateFor(double accuracyM) =>
      math.max(minStoreDistanceM, accuracyFactor * accuracyM);

  factory SportConfig.forSport(Sport s) => switch (s) {
        Sport.walk => const SportConfig(sport: Sport.walk, maxSpeedMps: 2.5),
        Sport.run => const SportConfig(sport: Sport.run, maxSpeedMps: 6.0),
        Sport.bike => const SportConfig(sport: Sport.bike, maxSpeedMps: 20.0),
      };
}
