import 'package:gpx/gpx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_source.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/gpx_document.dart';
import 'package:track_scribe/import/gpx_track.dart';

/// A GPX document in the shape our own writer emits: default namespace, no
/// prefix, six-decimal degrees, UTC stamps.
const _ownStyle = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="TrackScribe">
  <metadata><time>2025-10-09T08:53:20.000Z</time></metadata>
  <trk>
    <type>run</type>
    <trkseg>
      <trkpt lat="36.753800" lon="3.185600"><time>2025-10-09T08:53:20.000Z</time></trkpt>
      <trkpt lat="36.754000" lon="3.186000"><time>2025-10-09T08:53:25.000Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>
''';

String _oneTrack(String segmentBody, {String? type}) =>
    '<gpx version="1.1"><trk>${type == null ? '' : '<type>$type</type>'}'
    '<trkseg>$segmentBody</trkseg></trk></gpx>';

void main() {
  group('قراءة ملف GPX (2أ استيراد)', () {
    test('positions, stamps and the type token come out of a default-namespace file', () {
      final track = parseGpxTrack(_ownStyle);
      expect(track.points, hasLength(2));
      expect(track.points[0].lat, closeTo(36.7538, 1e-9));
      expect(track.points[0].lon, closeTo(3.1856, 1e-9));
      expect(track.points[1].lat, closeTo(36.7540, 1e-9));
      expect(track.rawType, 'run');
      expect(track.sport, ImportSport.run);
      expect(
        track.points[0].wallMillis,
        DateTime.parse('2025-10-09T08:53:20.000Z').millisecondsSinceEpoch,
      );
      expect(
        track.startWallMillis,
        DateTime.parse('2025-10-09T08:53:20.000Z').millisecondsSinceEpoch,
      );
    });

    test(
      'a prefixed namespace is the same file: the lookup is by local name',
      () {
        // `findAllElements('trkpt')` compares the FULLY qualified name, so this
        // only works by asking for the local name with any namespace — and a
        // prefixed GPX really exists in the wild.
        final track = parseGpxTrack('''
        <gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1" version="1.1">
          <gpx:trk><gpx:trkseg>
            <gpx:trkpt lat="36.75" lon="3.18"/>
          </gpx:trkseg></gpx:trk>
        </gpx:gpx>
      ''');
        expect(track.points, hasLength(1));
        expect(track.points.single.lat, 36.75);
      },
    );

    test('an upstream GPX writer is readable: what we did not write still imports', () {
      // package:gpx is not our code, and `gpx11` mode gives the file a real
      // default namespace plus an xsi:schemaLocation. If this test fails, some
      // real app's file is a file our users cannot open.
      final from = GpxWriter().asString(
        Gpx()
          ..creator = 'Strava Macrostrat'
          ..metadata = Metadata(time: DateTime.utc(2026, 3, 1, 8))
          ..trks = [
            Trk(
              type: 'run',
              trksegs: [
                Trkseg(
                  trkpts: [
                    Wpt(
                      lat: 36.7538,
                      lon: 3.1856,
                      ele: 61.5,
                      time: DateTime.utc(2026, 3, 1, 8, 0, 1),
                    ),
                    Wpt(
                      lat: 36.7540,
                      lon: 3.1860,
                      ele: 62.0,
                      time: DateTime.utc(2026, 3, 1, 8, 0, 6),
                    ),
                  ],
                ),
              ],
            ),
          ],
        compatibility: GpxCompatibilityMode.gpx11,
      );
      final track = parseGpxTrack(from);
      expect(track.points, hasLength(2));
      expect(track.sport, ImportSport.run);
      expect(track.points[0].eleM, closeTo(61.5, 1e-6));
      expect(track.points[1].eleM, closeTo(62.0, 1e-6));
      expect(
        track.points[1].wallMillis,
        DateTime.utc(2026, 3, 1, 8, 0, 6).millisecondsSinceEpoch,
      );
    });

    test("the elevation in the FILE is kept: it is another device's claim, not ours", () {
      // §2أ's بوّابة الصدق forbids us PUBLISHING altitudes we measured and know
      // to be wrong. Reading a file that carries `<ele>` is the other half: the
      // number is the file's own, kept as-is and attributed to the import.
      final track = parseGpxTrack(
        _oneTrack(
          '<trkpt lat="36.75" lon="3.18"><ele>61.5</ele></trkpt>'
          '<trkpt lat="36.76" lon="3.19"><ele>NaN</ele></trkpt>',
        ),
      );
      expect(track.points[0].eleM, 61.5);
      expect(track.points[1].eleM, isNull);
    });

    test('an absent <ele> stays absent, never a zero', () {
      final track = parseGpxTrack(_ownStyle);
      expect(track.points[0].eleM, isNull);
      expect(track.points[1].eleM, isNull);
    });

    test('a stamp with no zone designator is not a time', () {
      // A naive `2025-10-09T08:53:20` means a different instant in every zone:
      // Dart reads it as local, so the same file would be two different tracks
      // on two phones. §2أ drops the stamp rather than picking a zone.
      final track = parseGpxTrack(
        _oneTrack(
          '<trkpt lat="36.75" lon="3.18"><time>2025-10-09T08:53:20</time></trkpt>'
          '<trkpt lat="36.76" lon="3.19"><time>2025-10-09T08:53:25Z</time></trkpt>',
        ),
      );
      expect(track.points[0].wallMillis, isNull);
      expect(track.points[1].wallMillis, isNotNull);
      expect(track.droppedTimes, 1);
    });

    test('a stamp that moved backwards is dropped: no duration may come out negative', () {
      final track = parseGpxTrack(
        _oneTrack(
          '<trkpt lat="36.75" lon="3.18"><time>2025-10-09T08:53:25Z</time></trkpt>'
          '<trkpt lat="36.76" lon="3.19"><time>2025-10-09T08:53:20Z</time></trkpt>',
        ),
      );
      // The first kept stamp survives (nothing precedes it); the second would
      // make the elapsed negative, the same claim R79 already refuses, so it is
      // dropped and counted instead.
      expect(track.points[0].wallMillis, isNotNull);
      expect(track.points[1].wallMillis, isNull);
      expect(track.droppedTimes, 1);
    });

    test('the start is a point stamp, never the document creation stamp', () {
      // GPX 1.1: <metadata><time> is "the date and time at which the document
      // was created". An app that exported a 2023 ride in 2026 would enter the
      // history list three years late — and the list sorts by start.
      final track = parseGpxTrack(
        '<gpx version="1.1">'
        '<metadata><time>2026-01-01T00:00:00Z</time></metadata>'
        '<trk><trkseg>'
        '<trkpt lat="36.75" lon="3.18"><time>2023-05-05T08:00:00Z</time></trkpt>'
        '<trkpt lat="36.76" lon="3.19"><time>2023-05-05T08:00:05Z</time></trkpt>'
        '</trkseg></trk></gpx>',
      );
      expect(
        track.startWallMillis,
        DateTime.parse('2023-05-05T08:00:00Z').millisecondsSinceEpoch,
      );
    });

    test('a file whose points state no usable instant has no start', () {
      // The metadata stamp is not a fallback either: with no point clock there
      // is no instant this reader can attribute to the activity.
      final track = parseGpxTrack(
        '<gpx version="1.1"><trk><trkseg>'
        '<trkpt lat="36.75" lon="3.18"><time>2025-10-09T08:53:20</time></trkpt>'
        '<trkpt lat="36.76" lon="3.19"><time>2025-10-09T08:53:25</time></trkpt>'
        '</trkseg></trk></gpx>',
      );
      expect(track.startWallMillis, isNull);
      expect(track.droppedTimes, 2);
    });

    test('a known vocabulary maps, and everything else says null instead of guessing', () {
      ImportSport? of(String? token) => parseGpxTrack(
        _oneTrack('<trkpt lat="36.75" lon="3.18"/>', type: token),
      ).sport;
      for (final token in [
        'run',
        'running',
        'Run',
        'RUNNING',
        '  run  ',
        'jogging',
      ]) {
        expect(of(token), ImportSport.run, reason: token);
      }
      for (final token in [
        'bike',
        'biking',
        'cycling',
        'cyclotourisme',
        'ride',
        'mtb',
        'ebike',
        'virtualride',
      ]) {
        expect(of(token), ImportSport.bike, reason: token);
      }
      for (final token in ['walk', 'walking', 'hike', 'hiking']) {
        expect(of(token), ImportSport.walk, reason: token);
      }
      // `other` is the token TCX v2 is allowed to write for a walk, and the one
      // a lot of apps write when they do not know. Neither is a guess we make.
      // `drive` and `trail` are refused because a car trip and a trail marker are
      // not activities this app may label from a word it half-recognises.
      // `motorcycle` is the token that proves the table matches a PREFIX: "cycl"
      // is inside it, and a motorbike is not a bicycle.
      for (final token in [
        'other',
        '',
        'sailing',
        'skiing',
        'drive',
        'trail',
        'motorcycle',
      ]) {
        expect(of(token), isNull, reason: token);
      }
      // No <type> at all is the same as one we do not know.
      expect(of(null), isNull);
      expect(
        parseGpxTrack(_oneTrack('<trkpt lat="36.75" lon="3.18"/>')).rawType,
        isNull,
      );
    });

    test('a point outside the earth is refused, and refused where the user can see the count', () {
      final track = parseGpxTrack(
        _oneTrack(
          '<trkpt lat="91.0" lon="3.18"/>'
          '<trkpt lat="36.75" lon="181.0"/>'
          '<trkpt lat="36.75" lon="3.18"/>',
        ),
      );
      expect(track.points, hasLength(1));
      expect(track.rejectedPoints, 2);
    });

    test(
      'a non-numeric coordinate is refused like any other, not read as zero',
      () {
        final track = parseGpxTrack(
          _oneTrack(
            '<trkpt lat="abc" lon="3.18"/><trkpt lat="36.75" lon="3.18"/>',
          ),
        );
        expect(track.points, hasLength(1));
        expect(track.rejectedPoints, 1);
      },
    );

    test(
      'a missing coordinate attribute is refused, not read as the origin',
      () {
        // lat/lon defaulting to 0.0 would put the whole track in the Gulf of
        // Guinea — the prime meridian crosses Algeria, so this is a real place
        // a real user's broken file could claim.
        final track = parseGpxTrack(
          _oneTrack('<trkpt lon="3.18"/><trkpt lat="36.75" lon="3.18"/>'),
        );
        expect(track.points, hasLength(1));
        expect(track.rejectedPoints, 1);
      },
    );

    test('a file with no track points is rejected, not imported as an empty activity', () {
      expect(
        () => parseGpxTrack(
          '<gpx version="1.1"><trk><trkseg></trkseg></trk></gpx>',
        ),
        throwsA(isA<GpxParseException>()),
      );
      expect(
        () => parseGpxTrack(
          '<gpx version="1.1"><wpt lat="36.75" lon="3.18"/></gpx>',
        ),
        throwsA(isA<GpxParseException>()),
      );
    });

    test(
      'malformed XML says so instead of pretending to be an empty track',
      () {
        expect(
          () => parseGpxTrack('<gpx><trk>'),
          throwsA(isA<GpxParseException>()),
        );
        expect(
          () => parseGpxTrack('not xml at all'),
          throwsA(isA<GpxParseException>()),
        );
      },
    );

    test('a well-formed XML document that is not GPX is refused', () {
      // Without the root check this file would import: it has a <trk> and valid
      // points. A picker can be pointed at anything named .gpx.
      expect(
        () => parseGpxTrack(
          '<kml><trk><trkseg>'
          '<trkpt lat="36.75" lon="3.18"/>'
          '</trkseg></trk></kml>',
        ),
        throwsA(isA<GpxParseException>()),
      );
      // The prefixed spelling of the same root still passes.
      expect(
        parseGpxTrack(
          '<gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1">'
          '<gpx:trk><gpx:trkseg>'
          '<gpx:trkpt lat="36.75" lon="3.18"/>'
          '</gpx:trkseg></gpx:trk></gpx:gpx>',
        ).points,
        hasLength(1),
      );
    });

    test('a planned route is not a recorded activity: <rte> is refused', () {
      // A route has no times and nobody walked it; importing one as an activity
      // would write a distance for a trip that never happened.
      expect(
        () => parseGpxTrack(
          '<gpx version="1.1"><rte><rtept lat="36.75" lon="3.18"/></rte></gpx>',
        ),
        throwsA(isA<GpxParseException>()),
      );
    });

    test(
      'duplicate positions are kept: the file said the phone stood there twice',
      () {
        final track = parseGpxTrack(
          _oneTrack(
            '<trkpt lat="36.75" lon="3.18"/><trkpt lat="36.75" lon="3.18"/>'
            '<trkpt lat="36.76" lon="3.19"/>',
          ),
        );
        expect(track.points, hasLength(3));
        expect(track.rejectedPoints, 0);
      },
    );

    test('several segments concatenate in document order', () {
      final track = parseGpxTrack(
        '<gpx version="1.1"><trk>'
        '<trkseg><trkpt lat="36.75" lon="3.18"/></trkseg>'
        '<trkseg><trkpt lat="36.76" lon="3.19"/></trkseg>'
        '</trk></gpx>',
      );
      expect(track.points, hasLength(2));
      expect(track.points[0].lat, 36.75);
      expect(track.points[1].lat, 36.76);
    });

    test('several tracks are refused: one file must be one activity', () {
      expect(
        () => parseGpxTrack(
          '<gpx version="1.1">'
          '<trk><trkseg><trkpt lat="36.75" lon="3.18"/></trkseg></trk>'
          '<trk><trkseg><trkpt lat="36.76" lon="3.19"/></trkseg></trk>'
          '</gpx>',
        ),
        throwsA(isA<GpxParseException>()),
      );
    });

    test('our own export re-imports: same positions, same sport, still no elevation', () {
      final summary = ActivitySummary(
        id: 7,
        sport: 'bike',
        startWallMillis: DateTime.parse('2025-10-09T08:53:20.000Z')
            .millisecondsSinceEpoch,
        distanceM: 6400,
        elapsedNanos:
            5000 *
            Duration.millisecondsPerSecond *
            Duration.microsecondsPerMillisecond,
        source: kSourceRecorded,
        fixCount: 2,
        rejectedCount: 0,
        mockDetected: false,
        points: [
          StoredPoint(
            lat: 36.7538,
            lon: 3.1856,
            timeNanos: 0,
            accuracyM: 8,
            type: WaypointType.normal,
            altitudeM: 61.5,
          ),
          StoredPoint(
            lat: 36.7540,
            lon: 3.1860,
            timeNanos:
                5000 *
                Duration.millisecondsPerSecond *
                Duration.microsecondsPerMillisecond,
            accuracyM: 8,
            type: WaypointType.normal,
            altitudeM: 62.0,
          ),
        ],
      );
      final track = parseGpxTrack(buildGpxDocument(summary));
      expect(track.sport, ImportSport.bike);
      expect(track.points, hasLength(2));
      expect(track.points[0].lat, closeTo(36.7538, 5e-7));
      expect(track.points[0].lon, closeTo(3.1856, 5e-7));
      // The writer never emits <ele> (§2أ), so the reader must not invent one.
      expect(track.points[0].eleM, isNull);
      // The stamps the writer anchored on the row's start come back as itself.
      expect(track.startWallMillis, summary.startWallMillis);
      expect(track.droppedTimes, 0);
    });
  });

  group('بوّابة الحجم', () {
    test('a file over the cap is refused before it is parsed', () {
      final huge =
          _oneTrack('<trkpt lat="36.75" lon="3.18"/>' * 2) +
          ' ' * kMaxGpxSourceChars;
      expect(huge.length, greaterThan(kMaxGpxSourceChars));
      expect(() => parseGpxTrack(huge), throwsA(isA<GpxParseException>()));
    });

    test('an ordinary file is under the cap', () {
      expect(kMaxGpxSourceChars, greaterThan(2 * 1024 * 1024));
      expect(parseGpxTrack(_ownStyle).points, hasLength(2));
    });
  });
}
