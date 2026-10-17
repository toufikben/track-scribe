import 'package:flutter_test/flutter_test.dart';
import 'package:gpx/gpx.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/gpx_document.dart';

/// One activity as the detail screen hands it to a reader: the row's totals
/// plus its points in engine order.
ActivitySummary activity(
  List<StoredPoint> points, {
  int startWallMillis = 1760000000000,
  int elapsedNanos = 60000000000,
  String sport = 'walk',
}) => ActivitySummary(
  id: 7,
  sport: sport,
  startWallMillis: startWallMillis,
  distanceM: 1234.5,
  elapsedNanos: elapsedNanos,
  fixCount: points.length,
  rejectedCount: 0,
  mockDetected: false,
  points: points,
);

StoredPoint fix(
  double lat,
  double lon,
  int timeNanos, {
  double? altitudeM,
  WaypointType type = WaypointType.normal,
}) => StoredPoint(
  lat: lat,
  lon: lon,
  timeNanos: timeNanos,
  accuracyM: 4.2,
  type: type,
  altitudeM: altitudeM,
);

void main() {
  group('GPX 1.1 document (§2أ)', () {
    test('root declares GPX 1.1, the TopoGrafix namespace and TrackScribe', () {
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
      ]));
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(
        xml,
        contains(
          '<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" '
          'creator="TrackScribe"',
        ),
      );
      expect(xml.trimRight(), endsWith('</gpx>'));
    });

    test('sport becomes the track type inside exactly one track segment', () {
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(36.7540, 3.1860, 5000000000),
      ], sport: 'bike'));
      expect('<trk>'.allMatches(xml).length, 1);
      expect('<trkseg>'.allMatches(xml).length, 1);
      expect(xml, contains('<type>bike</type>'));
      expect('<trkpt lat="36.753800" lon="3.185600">'.allMatches(xml).length, 1);
    });

    test('degrees print six decimals — never exponent notation', () {
      // The prime meridian crosses Algeria, so lon ~0 is a real recorded
      // value, and Dart's default double.toString() would print 1.0e-7.
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(36.5, 0.00000012, 1000000000),
      ]));
      expect(xml, contains('<trkpt lat="36.753800" lon="3.185600">'));
      expect(xml, contains('<trkpt lat="36.500000" lon="0.000000">'));
      expect(xml, isNot(contains('e-7')));
    });

    test('a rejected fix never leaves the device (ر115)', () {
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(37.1000, 4.9000, 1000000000, type: WaypointType.rejected),
        fix(36.7540, 3.1860, 2000000000),
      ]));
      expect('<trkpt'.allMatches(xml).length, 2);
      expect(xml, isNot(contains('37.100000')));
      expect(xml, isNot(contains('4.900000')));
    });

    test('no elevation is exported while alt_gnss is untrusted (§2أ gate)', () {
      // Field measurement near Khemis El Khechna returned alt_gnss ≈60–63 m
      // where ~590 m is expected (docs/BORROW-FROM-TRAILMARK.md §3), and
      // climb_m is 0 pending ر11. An unverified height must stay absent from
      // the file, not be written into it as if it were a measurement.
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0, altitudeM: 61.5),
        fix(36.7540, 3.1860, 1000000000, altitudeM: 62.0),
      ]));
      expect(xml, isNot(contains('<ele')));
      expect(xml, isNot(contains('61.5')));
    });

    test('point times keep the measured monotonic deltas from the row start', () {
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(36.7540, 3.1860, 5000000000),
        fix(36.7542, 3.1864, 11000000000),
      ]));
      expect(xml, contains('<time>2025-10-09T08:53:20.000Z</time>'));
      expect(xml, contains('<time>2025-10-09T08:53:25.000Z</time>'));
      expect(xml, contains('<time>2025-10-09T08:53:31.000Z</time>'));
    });

    test('a track whose monotonic stamps go backwards exports no point time', () {
      // R79 lets a resumed session restart its clock, so a later rowid can
      // carry a smaller timeNanos than an earlier one. The deltas then mean
      // nothing, and guessing across the resume would print a number nobody
      // measured — so the times are dropped and the positions survive.
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 5000000000),
        fix(36.7540, 3.1860, 1000000000),
      ]));
      expect('<time>'.allMatches(xml).length, 1);
      expect(xml, contains('<metadata>'));
      expect(xml, contains('<time>2025-10-09T08:53:20.000Z</time>'));
      expect('<trkpt'.allMatches(xml).length, 2);
    });

    test('the ordering gate reads displayed points, not rejected evidence', () {
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(37.1000, 4.9000, 900000000000, type: WaypointType.rejected),
        fix(36.7540, 3.1860, 1000000000),
      ]));
      expect('<time>'.allMatches(xml).length, 3);
      expect(xml, contains('<time>2025-10-09T08:53:21.000Z</time>'));
    });

    test('an activity with no points still writes a readable, empty document', () {
      final xml = buildGpxDocument(activity(const []));
      expect('<trkpt'.allMatches(xml).length, 0);
      expect(xml, contains('<metadata>'));
      expect(xml, contains('<time>2025-10-09T08:53:20.000Z</time>'));
      expect(xml.trimRight(), endsWith('</gpx>'));
    });

    test('the file carries positions only — no totals, no extensions', () {
      // distanceM/elapsedNanos are row accumulators the importer can recompute
      // from the track; climb_m is 0 pending ر11. Writing them as assertions
      // would dress an unmeasured number up as file metadata.
      final xml = buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0),
      ]));
      expect(xml, isNot(contains('<extensions')));
      expect(xml, isNot(contains('<desc')));
      expect(xml, isNot(contains('1234.5')));
    });
  });

  // String matching cannot prove a document is readable. This group parses our
  // bytes with `package:gpx`, an upstream GPX 1.1 consumer, so an export the
  // wider ecosystem cannot open fails the suite instead of the user.
  group('an upstream GPX reader opens what we write', () {
    Trkseg segmentOf(ActivitySummary summary) =>
        GpxReader().fromString(buildGpxDocument(summary)).trks.single.trksegs.single;

    test('metadata, sport and the six-decimal positions survive parsing', () {
      final gpx = GpxReader().fromString(buildGpxDocument(activity([
        fix(36.7538, 3.1856, 0, altitudeM: 61.5),
        fix(37.1000, 4.9000, 1000000000, type: WaypointType.rejected),
        fix(36.7540, 3.1860, 5000000000),
      ])));
      expect(gpx.version, '1.1');
      expect(gpx.creator, 'TrackScribe');
      expect(gpx.metadata?.time?.toUtc().toIso8601String(), '2025-10-09T08:53:20.000Z');
      expect(gpx.trks.single.type, 'walk');
      final pts = gpx.trks.single.trksegs.single.trkpts;
      expect(pts.length, 2);
      expect(pts[0].lat, closeTo(36.7538, 1e-9));
      expect(pts[0].lon, closeTo(3.1856, 1e-9));
      expect(pts[1].lat, closeTo(36.7540, 1e-9));
    });

    test('the reader sees no elevation and the measured time deltas', () {
      final pts = segmentOf(activity([
        fix(36.7538, 3.1856, 0, altitudeM: 61.5),
        fix(36.7540, 3.1860, 5000000000),
      ])).trkpts;
      expect(pts[0].ele, isNull);
      expect(pts[1].ele, isNull);
      expect(pts[0].time?.toUtc().toIso8601String(), '2025-10-09T08:53:20.000Z');
      expect(pts[1].time?.toUtc().toIso8601String(), '2025-10-09T08:53:25.000Z');
    });

    test('a resumed track still opens, with positions and no times', () {
      final pts = segmentOf(activity([
        fix(36.7538, 3.1856, 5000000000),
        fix(36.7540, 3.1860, 1000000000),
      ])).trkpts;
      expect(pts.length, 2);
      expect(pts[0].time, isNull);
      expect(pts[1].time, isNull);
      expect(pts[1].lat, closeTo(36.7540, 1e-9));
    });
  });
}
