import 'package:track_scribe/engine/raw_fix.dart';

/// The rules every §2أ export format shares, so a GPX file and a TCX file can
/// never disagree about the same activity.
///
/// Both writers take the points straight from [ActivitySummary] in engine
/// order and apply the two gates here: the display filter (ر115) and the
/// monotonic-ordering gate that decides whether a per-point wall time may be
/// printed at all.

/// `track_points.timeNanos` is nanoseconds; the epoch stamps are milliseconds.
const int kNanosPerMillisecond =
    Duration.microsecondsPerMillisecond * Duration.millisecondsPerSecond;

/// One UTC stamp per point, or null when the stored stamps are not a clock.
///
/// R79 lets a resumed activity restart its monotonic clock, so a later rowid
/// can hold a smaller `timeNanos` than an earlier one. The deltas across such
/// a resume measure nothing, and splitting the track at the restart would put
/// a guess into the file: the answer is null, and the writer emits positions
/// without times.
///
/// When the stamps do strictly increase, every entry is
/// `anchorMillis + (timeNanos - firstTimeNanos)`: the differences are measured,
/// while the anchor collapses the press-start→first-fix gap on purpose. That
/// can only make an importer's recomputed duration shorter than the stored
/// `elapsedNanos`, never longer.
List<String>? exportPointTimes(List<StoredPoint> points, int anchorMillis) {
  for (var i = 1; i < points.length; i++) {
    if (points[i].timeNanos <= points[i - 1].timeNanos) return null;
  }
  final first = points.isEmpty ? 0 : points.first.timeNanos;
  return [
    for (final p in points)
      formatIsoUtc(anchorMillis + (p.timeNanos - first) ~/ kNanosPerMillisecond),
  ];
}

/// Six decimal degrees ≈ 0.11 m at the equator — already finer than the
/// metre-level 1σ the fixes were taken at, and fixed-width so a longitude near
/// zero prints `0.000000` instead of Dart's exponent form `1.2e-7`. The prime
/// meridian crosses Algeria, so that is a value this app really records.
String formatDegrees(double value) => value.toStringAsFixed(6);

/// dart:core, not `intl` (ر118): both formats want `xsd:dateTime`, which is
/// exactly what [DateTime.toIso8601String] emits for a UTC instant.
String formatIsoUtc(int millisSinceEpoch) => DateTime.fromMillisecondsSinceEpoch(
  millisSinceEpoch,
  isUtc: true,
).toIso8601String();
