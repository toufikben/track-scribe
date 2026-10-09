import 'dart:math' as math;

const double _earthRadiusM = 6371008.8; // WGS84 mean radius (IUGG)
double _rad(double deg) => deg * math.pi / 180.0;

/// Spherical distance in metres. On segments ≤ 25 m the difference from a
/// full ellipsoidal geodesic is centimetres — far below GPS noise.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _rad(lat1), phi2 = _rad(lat2);
  final dPhi = phi2 - phi1, dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _rad(lat1), phi2 = _rad(lat2), dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
