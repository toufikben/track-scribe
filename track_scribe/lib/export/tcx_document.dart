import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/track_export.dart';

/// Writes the same activity out as Garmin TCX, for the apps that read Garmin
/// and not GPX (borrow §2أ, shape ported from trailmark's `portable/Tcx.kt`).
///
/// One activity, one lap, one track — and the two §2أ gates shared with the
/// GPX writer through `track_export.dart`, so a `.gpx` and a `.tcx` of the
/// same walk cannot disagree: rejected fixes stay home (ر115) and an
/// untrusted height stays absent.
///
/// Where TCX is richer than GPX it prints stored numbers, and every one of
/// them was measured: `<TotalTimeSeconds>` is `activities.elapsedNanos` (the
/// monotonic accumulator of ر1/ر81, not a clock subtraction) and
/// `<DistanceMeters>` is `activities.distanceM`. GPX has no honest place for
/// either, so its document carries positions only.
///
/// `<AltitudeMeters>` is never emitted, unlike trailmark, which writes
/// `altitudeM` whenever it is non-null: our `alt_gnss` measured ≈60–63 m near
/// Khemis El Khechna where ~590 m is expected (docs/BORROW-FROM-TRAILMARK.md
/// §3), so the field is untrusted until the device round resolves it.
String buildTcxDocument(ActivitySummary summary) {
  final points = displayablePoints(summary.points);
  final times = exportPointTimes(points, summary.startWallMillis);
  final start = formatIsoUtc(summary.startWallMillis);
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<TrainingCenterDatabase')
    ..writeln('    xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
    ..writeln('  <Activities>')
    ..writeln('    <Activity Sport="${_tcxSport(summary.sport)}">')
    ..writeln('      <Id>$start</Id>')
    ..writeln('      <Lap StartTime="$start">')
    ..writeln('        <TotalTimeSeconds>${_seconds(summary.elapsedNanos)}</TotalTimeSeconds>')
    ..writeln('        <DistanceMeters>${summary.distanceM.toStringAsFixed(1)}</DistanceMeters>')
    ..writeln('        <Track>');
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    out.writeln('          <Trackpoint>');
    if (times != null) out.writeln('            <Time>${times[i]}</Time>');
    out
      ..writeln('            <Position>')
      ..writeln('              <LatitudeDegrees>${formatDegrees(p.lat)}</LatitudeDegrees>')
      ..writeln('              <LongitudeDegrees>${formatDegrees(p.lon)}</LongitudeDegrees>')
      ..writeln('            </Position>')
      ..writeln('          </Trackpoint>');
  }
  return (out
        ..writeln('        </Track>')
        ..writeln('      </Lap>')
        ..writeln('    </Activity>')
        ..writeln('  </Activities>')
        ..writeln('</TrainingCenterDatabase>'))
      .toString();
}

/// Milliseconds first (integer division, so no rounding drift), then the
/// three decimals TCX consumers expect from a monotonic accumulator.
String _seconds(int elapsedNanos) => ((elapsedNanos ~/ kNanosPerMillisecond) /
        Duration.millisecondsPerSecond)
    .toStringAsFixed(3);

/// `TrainingCenterDatabasev2.xsd` enumerates `Sport` as Running | Biking |
/// Other, and there is no walking token in v2. A walk therefore exports as
/// `Other` rather than as a value the schema would reject; the real sport
/// still travels in the GPX file, whose `<type>` is free text.
String _tcxSport(String storedSport) => switch (storedSport) {
  'run' => 'Running',
  'bike' => 'Biking',
  _ => 'Other',
};
