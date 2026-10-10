import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// One completed kilometre of the travelled path (spec ر9 polyline semantics:
/// rejected points are raw archive entries, not path, and are skipped).
class Split {
  const Split({required this.kmIndex, required this.distanceM,
               required this.elapsedNanos, required this.paceSecPerKm});
  final int kmIndex;
  final double distanceM;
  final int elapsedNanos;
  final double paceSecPerKm;
}

/// Interpolates the exact position/time at each 1000 m crossing along the
/// stored polyline. Never extrapolates beyond the last point.
List<Split> computeSplits(List<StoredPoint> points) {
  final out = <Split>[];
  double travelled = 0;
  int km = 1;
  StoredPoint? prev;
  final int startNanos = points.isNotEmpty ? points.first.timeNanos : 0;

  for (final p in points) {
    if (p.type == WaypointType.rejected) continue;
    if (prev != null) {
      final seg = haversineMeters(prev.lat, prev.lon, p.lat, p.lon);
      final segTime = p.timeNanos - prev.timeNanos;
      double remaining = seg;
      while (travelled + remaining >= km * 1000.0) {
        final need = km * 1000.0 - travelled;
        final frac = seg == 0 ? 0.0 : need / seg;
        final nanosAt = prev.timeNanos + (segTime * frac).round();
        // R11: segment pace in ABSOLUTE time. Split.elapsedNanos is relative
        // to startNanos, so the previous boundary must be re-anchored before
        // subtraction; mixing the two inflates every km >= 2 by startNanos.
        final prevNanosAbs =
            out.isEmpty ? startNanos : startNanos + out.last.elapsedNanos;
        out.add(Split(kmIndex: km, distanceM: km * 1000.0,
            elapsedNanos: nanosAt - startNanos,
            paceSecPerKm: (nanosAt - prevNanosAbs) / 1e9));
        travelled += need; remaining -= need; km++;
      }
      travelled += remaining;
    }
    prev = p;
  }
  return out;
}
