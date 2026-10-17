import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/track_export.dart';

/// Writes a stored activity out as a GPX 1.1 document (borrow §2أ, shape
/// ported from trailmark's `portable/src/main/kotlin/dev/toufik/trailmark/portable/Gpx.kt`).
///
/// Pure: no file, no share sheet, no plugin, no clock. Everything it needs
/// arrives in [summary], which is the same object the detail screen reads, so
/// the exported file and the on-screen route cannot disagree about which
/// fixes exist.
///
/// Three rules this writer will not bend:
///
/// * **No elevation, ever, for now** (§2أ بوّابة الصدق). `alt_gnss` measured
///   ≈60–63 m near Khemis El Khechna where ~590 m is expected
///   (docs/BORROW-FROM-TRAILMARK.md §3) and `climb_m` is 0 pending ر11, so an
///   `<ele>` would publish a number we know to be wrong. Absent, not invented.
/// * **Only displayed points** (ر115). A rejected spike is kept in the
///   database as evidence of what the recorder refused; it must not leave the
///   device as a jump the rider never made.
/// * **A time only where the deltas are measured** — the ordering gate and the
///   anchor rule both live in `track_export.dart`, shared with the TCX writer
///   so the two formats can never drift apart on how a resumed track is
///   stamped.
///
/// GPX is the lossless of the two exports: `<type>` is free text, so the real
/// sport travels here even when TCX v2 has no token for it.
String buildGpxDocument(ActivitySummary summary) {
  final points = displayablePoints(summary.points);
  final times = exportPointTimes(points, summary.startWallMillis);
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" '
      'creator="TrackScribe">',
    )
    ..writeln('  <metadata>')
    ..writeln('    <time>${formatIsoUtc(summary.startWallMillis)}</time>')
    ..writeln('  </metadata>')
    ..writeln('  <trk>')
    // `activities.sport` is written as `Sport.name` (recording_controller.dart:349),
    // so it is one of walk|run|bike: our own ASCII token, like every other
    // string here. That is why nothing in this writer escapes anything — and
    // why GPX, whose <type> is free text, keeps the real sport that TCX v2
    // cannot name for a walk.
    ..writeln('    <type>${summary.sport}</type>')
    ..writeln('    <trkseg>');
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final position = 'lat="${formatDegrees(p.lat)}" lon="${formatDegrees(p.lon)}"';
    if (times == null) {
      out.writeln('      <trkpt $position />');
    } else {
      out
        ..writeln('      <trkpt $position>')
        ..writeln('        <time>${times[i]}</time>')
        ..writeln('      </trkpt>');
    }
  }
  return (out
        ..writeln('    </trkseg>')
        ..writeln('  </trk>')
        ..writeln('</gpx>'))
      .toString();
}
