import 'package:track_scribe/core/geo.dart';

/// Waypoint classification per spec rules ر4/ر6 (waypoint_type in §4).
/// `skipped` is NOT a persisted waypoint_type (spec §4 lists NORMAL, IDLE,
/// REJECTED, SEGPOINT): it is the sink verdict (ر9/R41) for an accepted fix
/// the store gate did not keep, so the persistence layer still sees every
/// raw point.
enum WaypointType { normal, idle, rejected, skipped }

/// One GPS fix as delivered by the platform, in monotonic time.
class RawFix {
  const RawFix({
    required this.lat, required this.lon, required this.timeNanos,
    required this.accuracyM, this.altitudeM, this.speedMps,
    this.bearingDeg, this.isMocked = false, this.wallMillis = 0,
  });
  final double lat, lon;
  final int timeNanos;      // monotonic (see Global Constraints deviation 1)
  final double accuracyM;   // Android 1σ radius
  final double? altitudeM, speedMps, bearingDeg;
  final bool isMocked;
  final int wallMillis;     // display only, never used for durations
}

/// A point the engine decided to keep (normal store, idle marker, or
/// rejected-but-preserved raw point — ر4/ر9: nothing is ever deleted).
class StoredPoint {
  const StoredPoint({
    required this.lat, required this.lon, required this.timeNanos,
    required this.accuracyM, required this.type,
    this.altitudeM, this.speedMps, this.bearingDeg,
  });
  final double lat, lon, accuracyM;
  final int timeNanos;
  final WaypointType type;
  final double? altitudeM, speedMps, bearingDeg;
  double distanceTo(StoredPoint o) => haversineMeters(lat, lon, o.lat, o.lon);
}

/// The points a display surface may DRAW. Rejected spikes stay in the database as
/// evidence of what the recorder refused, but every surface must refuse them
/// identically: if the route line and the elevation profile disagree about which
/// fixes exist, the profile shows jumps the rider never made (ر115).
List<StoredPoint> displayablePoints(List<StoredPoint> points) => [
  for (final p in points)
    if (p.type != WaypointType.rejected) p,
];
