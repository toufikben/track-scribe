enum Sport { walk, run, bike }

/// Per-sport engine constants — spec rules ر3–ر6.
class SportConfig {
  const SportConfig({
    required this.sport, required this.maxSpeedMps,
    this.minStoreDistanceM = 3.0, this.accuracyFactor = 2.0,
    this.maxStoreDistanceM = 25.0, this.forceStoreAfterS = 15.0,
    this.maxJumpM = 200.0, this.idleSpeedMps = 0.4, this.idleAfterS = 12.0,
  });
  final Sport sport;
  final double maxSpeedMps;      // ر5
  final double minStoreDistanceM, maxStoreDistanceM, accuracyFactor; // ر3
  final double forceStoreAfterS; // ر3 heartbeat
  final double maxJumpM;         // ر4
  final double idleSpeedMps, idleAfterS; // ر6

  /// Store gate: max(3 m, 2 × accuracy), capped at 25 m (spec ر3 verbatim).
  /// Note: the task-4 brief's code had `minStoreDistanceM + accuracyFactor *
  /// accuracyM` (3 + 2a); that contradicts both the spec and the brief's own
  /// gateFor(0.5)==3.0 test, so the spec formula wins (controller ruling R6).
  double gateFor(double accuracyM) =>
      (accuracyFactor * accuracyM).clamp(minStoreDistanceM, maxStoreDistanceM).toDouble();

  factory SportConfig.forSport(Sport s) => switch (s) {
        Sport.walk => const SportConfig(sport: Sport.walk, maxSpeedMps: 2.5),
        Sport.run => const SportConfig(sport: Sport.run, maxSpeedMps: 6.0),
        Sport.bike => const SportConfig(sport: Sport.bike, maxSpeedMps: 20.0),
      };
}
