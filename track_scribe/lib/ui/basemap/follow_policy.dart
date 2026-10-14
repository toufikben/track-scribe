import 'package:latlong2/latlong.dart';
import 'package:track_scribe/core/geo.dart';

/// Fraction of the half band a fix may drift before the camera chases it.
const double _toleranceFactor = .6;

/// Whether the live map should move its centre to [target] while [center] is
/// the camera's current centre.
///
/// Chasing every fix is what blanked the map on the realme: each programmatic
/// move restarts the vector tile fetch, and on a two-core phone the decode
/// takes longer than the gap between fixes, so nothing ever finished painting.
/// A fix that still lands inside the band is therefore not worth a move — the
/// marker slides toward the edge and the map catches up before it can leave.
///
/// [metresPerPixel] is the band's own scale (0 = no camera yet, in which case
/// there is no tolerance to measure against and the first fix centres),
/// [bandShortSidePx] the shorter side of the map viewport in logical pixels.
bool shouldRecenter({
  required LatLng center,
  required LatLng target,
  required double metresPerPixel,
  required double bandShortSidePx,
}) {
  if (metresPerPixel <= 0 || bandShortSidePx <= 0) return true;
  final tolerance =
      _toleranceFactor * metresPerPixel * bandShortSidePx / 2;
  final drift = haversineMeters(
    center.latitude,
    center.longitude,
    target.latitude,
    target.longitude,
  );
  return drift > tolerance;
}
