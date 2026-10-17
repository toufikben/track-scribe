import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/tcx_document.dart';
import 'package:xml/xml.dart';

ActivitySummary activity(
  List<StoredPoint> points, {
  int startWallMillis = 1760000000000,
  int elapsedNanos = 60000000000,
  double distanceM = 1234.5,
  String sport = 'walk',
}) => ActivitySummary(
  id: 7,
  sport: sport,
  startWallMillis: startWallMillis,
  distanceM: distanceM,
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
  group('TCX 2.0 document (§2أ)', () {
    test('root declares the TrainingCenterDatabase v2 namespace', () {
      final xml = buildTcxDocument(activity([fix(36.7538, 3.1856, 0)]));
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(
        xml,
        contains('xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"'),
      );
      expect(xml.trimRight(), endsWith('</TrainingCenterDatabase>'));
    });

    test('the stored sport maps to the TCX v2 enum — walk is Other, not invented', () {
      // TrainingCenterDatabasev2.xsd enumerates Sport as Running | Biking |
      // Other, so a walk has no honest token in v2 and `Other` is the only
      // schema-valid answer. GPX keeps the truth (its <type> is free text).
      final walk = buildTcxDocument(activity([], sport: 'walk'));
      final run = buildTcxDocument(activity([], sport: 'run'));
      final bike = buildTcxDocument(activity([], sport: 'bike'));
      expect(walk, contains('Sport="Other"'));
      expect(run, contains('Sport="Running"'));
      expect(bike, contains('Sport="Biking"'));
      expect(walk, isNot(contains('Walking')));
      expect('<Activity '.allMatches(walk).length, 1);
    });

    test('the activity id and lap start are the measured row stamp', () {
      final xml = buildTcxDocument(activity([fix(36.7538, 3.1856, 0)]));
      expect(xml, contains('<Id>2025-10-09T08:53:20.000Z</Id>'));
      expect(xml, contains('<Lap StartTime="2025-10-09T08:53:20.000Z">'));
    });

    test('the lap totals are the stored accumulators, printed as measured', () {
      // elapsedNanos is the monotonic total (ر1/ر81) and distanceM the engine's
      // haversine sum — the two numbers the detail screen already shows.
      final xml = buildTcxDocument(activity([fix(36.7538, 3.1856, 0)]));
      expect(xml, contains('<TotalTimeSeconds>60.000</TotalTimeSeconds>'));
      expect(xml, contains('<DistanceMeters>1234.5</DistanceMeters>'));
    });

    test('no altitude element while alt_gnss is untrusted (§2أ gate)', () {
      final xml = buildTcxDocument(activity([
        fix(36.7538, 3.1856, 0, altitudeM: 61.5),
      ]));
      expect(xml, isNot(contains('AltitudeMeters')));
      expect(xml, isNot(contains('61.5')));
    });

    test('a rejected fix never leaves the device (ر115)', () {
      final xml = buildTcxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(37.1000, 4.9000, 1000000000, type: WaypointType.rejected),
        fix(36.7540, 3.1860, 2000000000),
      ]));
      expect('<Trackpoint>'.allMatches(xml).length, 2);
      expect(xml, isNot(contains('37.100000')));
    });

    test('trackpoints keep positions and drop times when the clock restarted', () {
      final xml = buildTcxDocument(activity([
        fix(36.7538, 3.1856, 5000000000),
        fix(36.7540, 3.1860, 1000000000),
      ]));
      expect('<Time>'.allMatches(xml).length, 0);
      expect(xml, contains('<LatitudeDegrees>36.753800</LatitudeDegrees>'));
      expect(xml, contains('<LongitudeDegrees>3.186000</LongitudeDegrees>'));
      // The lap totals do not depend on the per-point clock, so they stay.
      expect(xml, contains('<TotalTimeSeconds>60.000</TotalTimeSeconds>'));
    });

    test('trackpoint times carry the measured monotonic deltas', () {
      final xml = buildTcxDocument(activity([
        fix(36.7538, 3.1856, 0),
        fix(36.7540, 3.1860, 5000000000),
      ]));
      expect(xml, contains('<Time>2025-10-09T08:53:20.000Z</Time>'));
      expect(xml, contains('<Time>2025-10-09T08:53:25.000Z</Time>'));
    });

    test('an activity with no points still writes one empty lap', () {
      final xml = buildTcxDocument(activity(const []));
      expect('<Trackpoint'.allMatches(xml).length, 0);
      expect('<Lap '.allMatches(xml).length, 1);
      expect(xml, contains('<TotalTimeSeconds>60.000</TotalTimeSeconds>'));
    });
  });

  // `XmlDocument.parse` throws on a malformed document, so this group is the
  // well-formedness proof the string assertions above cannot give — and it
  // reads namespaced elements the way a Garmin importer does.
  group('a real XML parser reads the TCX document', () {
    const ns = 'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2';

    test('one activity, one lap, only displayed trackpoints, no altitude', () {
      final doc = XmlDocument.parse(buildTcxDocument(activity([
        fix(36.7538, 3.1856, 0, altitudeM: 61.5),
        fix(37.1000, 4.9000, 1000000000, type: WaypointType.rejected),
        fix(36.7540, 3.1860, 5000000000),
      ])));
      expect(doc.rootElement.name.local, 'TrainingCenterDatabase');
      expect(
        doc.findAllElements('Activity', namespaceUri: ns).single.getAttribute('Sport'),
        'Other',
      );
      expect(doc.findAllElements('Lap', namespaceUri: ns).length, 1);
      expect(doc.findAllElements('Trackpoint', namespaceUri: ns).length, 2);
      expect(doc.findAllElements('AltitudeMeters', namespaceUri: ns), isEmpty);
      expect(doc.findAllElements('Time', namespaceUri: ns).length, 2);
      expect(
        doc.findAllElements('TotalTimeSeconds', namespaceUri: ns).single.innerText,
        '60.000',
      );
      expect(
        doc.findAllElements('DistanceMeters', namespaceUri: ns).single.innerText,
        '1234.5',
      );
      expect(
        doc.findAllElements('LatitudeDegrees', namespaceUri: ns).first.innerText,
        '36.753800',
      );
    });

    test('a resumed track parses with times absent and the lap totals intact', () {
      final doc = XmlDocument.parse(buildTcxDocument(activity([
        fix(36.7538, 3.1856, 5000000000),
        fix(36.7540, 3.1860, 1000000000),
      ])));
      expect(doc.findAllElements('Time', namespaceUri: ns), isEmpty);
      expect(doc.findAllElements('Trackpoint', namespaceUri: ns).length, 2);
      expect(
        doc.findAllElements('TotalTimeSeconds', namespaceUri: ns).single.innerText,
        '60.000',
      );
    });
  });
}
