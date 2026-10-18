import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/import/gpx_track.dart';
import 'package:track_scribe/import/track_importer.dart';
import 'package:track_scribe/source/gps_quality.dart';

/// Nanoseconds in [seconds], written the way the importer has to: dart:core's
/// `Duration` stops at microseconds, so the last step is explicit.
int nanosOfSeconds(int seconds) =>
    Duration(seconds: seconds).inMicroseconds * 1000;

/// R125 (§2أ import): the writer half of importing a foreign GPX file.
///
/// The reader refuses to invent anything; the importer must not invent either.
/// Every number it stores is either copied from the file (`<ele>`, the stated
/// stamps) or computed from what the file states (the polyline), and the row
/// carries `source = 'gpx'` so a view can never present it as one of the
/// owner's own recordings.
void main() {
  late AppDatabase db;
  late ActivityRepository repo;
  late TrackImporter importer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
    importer = TrackImporter(db, repo);
  });
  tearDown(() => db.close());

  ImportedTrack track(
    List<ImportedPoint> points, {
    int rejectedPoints = 0,
    int droppedTimes = 0,
  }) => ImportedTrack(
    points: points,
    rawType: 'run',
    sport: ImportSport.run,
    startWallMillis: points.isEmpty ? null : points.first.wallMillis,
    rejectedPoints: rejectedPoints,
    droppedTimes: droppedTimes,
  );

  Future<Activity> rowOf(int id) =>
      (db.select(db.activities)..where((t) => t.id.equals(id))).getSingle();

  Future<ActivitySummary> summaryOf(int id) async {
    final summary = await repo.loadActivityWithPoints(id);
    if (summary == null) throw StateError('the imported row is not there');
    return summary;
  }

  group('TrackImporter', () {
    test('one import writes one activity and every point it kept, and calls '
        'itself a file, not a recording', () async {
      const start = 1700000000000;
      final out = await importer.importTrack(
        track(const [
          ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
          ImportedPoint(lat: 36.7538, lon: 3.1866, wallMillis: start + 60000),
          ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 120000),
        ]),
        sport: ImportSport.run,
        startWallMillis: start,
      );

      expect(out.pointCount, 3);
      expect(await repo.pointCount(out.activityId), 3);

      final row = await rowOf(out.activityId);
      // A file at latitude 36.75° advancing 0.001° of longitude twice is
      // about 89.1 m per leg; pinned from the geodesic, not from our formula.
      expect(out.distanceM, closeTo(178.2, 0.3));
      expect(row.distanceM, closeTo(178.2, 0.3));
      expect(row.source, 'gpx');
      expect(row.sport, 'run');
      expect(row.startWallMillis, start);
      expect(row.fixCount, 3);
      expect(row.isDeleted, isFalse);
    });

    test('an imported row is never «قيد التسجيل»: the history list reads it as '
        'finished, with its own totals', () async {
      const start = 1700000000000;
      final out = await importer.importTrack(
        track(const [
          ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
          ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 60000),
        ]),
        sport: ImportSport.bike,
        startWallMillis: start,
      );
      final items = await repo.listActivities();
      expect(items, hasLength(1));
      expect(items.single.id, out.activityId);
      expect(items.single.isOpen, isFalse);
      expect(items.single.sport, 'bike');
      expect(items.single.distanceM, greaterThan(0));
    });

    test(
      'a file whose clock survived the reader intact states its own elapsed',
      () async {
        const start = 1700000000000;
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
            ImportedPoint(lat: 36.7538, lon: 3.1866, wallMillis: start + 30000),
            ImportedPoint(
              lat: 36.7538,
              lon: 3.1876,
              wallMillis: start + 150000,
            ),
          ]),
          sport: ImportSport.run,
          startWallMillis: start,
        );
        expect(out.elapsedKnown, isTrue);
        expect(out.elapsedNanos, nanosOfSeconds(150));
        expect((await rowOf(out.activityId)).elapsedNanos, out.elapsedNanos);
      },
    );

    test(
      'a file with a broken clock gets no fake duration: zero stored, and the '
      'caller is told the elapsed is unknown',
      () async {
        const start = 1700000000000;
        // One stamp of three was unusable (the reader counted it), so the span
        // between the surviving stamps is not the activity's elapsed.
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
            ImportedPoint(lat: 36.7538, lon: 3.1866),
            ImportedPoint(
              lat: 36.7538,
              lon: 3.1876,
              wallMillis: start + 150000,
            ),
          ], droppedTimes: 1),
          sport: ImportSport.run,
          startWallMillis: start,
        );
        expect(out.elapsedKnown, isFalse);
        expect(out.elapsedNanos, 0);
        expect((await rowOf(out.activityId)).elapsedNanos, 0);
        // The route is still worth importing: refusing the whole file over its
        // clock would throw away positions the file did state.
        expect(out.pointCount, 3);
        expect(out.distanceM, greaterThan(0));
      },
    );

    test(
      'a file whose FIRST point has no stamp describes only part of its track: '
      'the span is not the elapsed, so none is stored',
      () async {
        const start = 1700000000000;
        // droppedTimes stays 0 — the reader had nothing to refuse, the file
        // simply never wrote a `<time>` for the opening point. The two stamps
        // that exist bracket 60 s of a longer activity, and 60 s would be a
        // smaller number printed as if it were the whole one (ر99).
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(lat: 36.7538, lon: 3.1846),
            ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
            ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 60000),
          ]),
          sport: ImportSport.run,
          startWallMillis: start,
        );
        expect(out.droppedTimes, 0);
        expect(out.elapsedKnown, isFalse);
        expect(out.elapsedNanos, 0);
        expect(out.pointCount, 3);
      },
    );

    test(
      'imported points carry no accuracy the file never stated (R76)',
      () async {
        const start = 1700000000000;
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
            ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 60000),
          ]),
          sport: ImportSport.walk,
          startWallMillis: start,
        );
        final stored = await summaryOf(out.activityId);
        for (final p in stored.points) {
          expect(p.accuracyM, unmeasuredAccuracyM);
        }
        final nulls = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM track_points WHERE accuracy_m IS NULL',
            )
            .getSingle();
        expect(nulls.read<int>('n'), 2);
      },
    );

    test(
      'the file states an altitude, we keep it verbatim; where it states none, '
      'the column stays NULL',
      () async {
        const start = 1700000000000;
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(
              lat: 36.7538,
              lon: 3.1856,
              eleM: 127.4,
              wallMillis: start,
            ),
            ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 60000),
          ]),
          sport: ImportSport.bike,
          startWallMillis: start,
        );
        final stored = await summaryOf(out.activityId);
        expect(stored.points[0].altitudeM, 127.4);
        expect(stored.points[1].altitudeM, isNull);
      },
    );

    test(
      'what the reader refused is reported to the caller, never written into '
      "the engine's own counter",
      () async {
        const start = 1700000000000;
        final out = await importer.importTrack(
          track(const [
            ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
            ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 60000),
          ], rejectedPoints: 4),
          sport: ImportSport.run,
          startWallMillis: start,
        );
        expect(out.rejectedPoints, 4);
        // `activities.rejected_count` answers "what did THIS app's engine
        // refuse while recording". A foreign file's refusals are not that
        // number, and storing them would make the column mean two things.
        expect((await rowOf(out.activityId)).rejectedCount, 0);
      },
    );

    test(
      'a file with no usable position is refused before anything is written',
      () async {
        await expectLater(
          importer.importTrack(
            track(const []),
            sport: ImportSport.run,
            startWallMillis: 1700000000000,
          ),
          throwsA(isA<ImportException>()),
        );
        final n = await db
            .customSelect('SELECT COUNT(*) AS n FROM activities')
            .getSingle();
        expect(n.read<int>('n'), 0);
      },
    );

    test(
      'a point write that fails rolls the whole import back: no half activity '
      'is left in the history',
      () async {
        const start = 1700000000000;
        final failing = _FailingRepository(db);
        final failingImporter = TrackImporter(db, failing);
        await expectLater(
          failingImporter.importTrack(
            track(const [
              ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
              ImportedPoint(
                lat: 36.7538,
                lon: 3.1876,
                wallMillis: start + 60000,
              ),
            ]),
            sport: ImportSport.run,
            startWallMillis: start,
          ),
          throwsStateError,
        );
        final counts = await db
            .customSelect('SELECT COUNT(*) AS n FROM activities')
            .getSingle();
        final points = await db
            .customSelect('SELECT COUNT(*) AS n FROM track_points')
            .getSingle();
        expect(counts.read<int>('n'), 0);
        expect(points.read<int>('n'), 0);
      },
    );

    test('timeNanos holds the file’s stated offsets, and an unstamped point is '
        'never given a later clock than we know', () async {
      const start = 1700000000000;
      final out = await importer.importTrack(
        track(const [
          ImportedPoint(lat: 36.7538, lon: 3.1856, wallMillis: start),
          ImportedPoint(lat: 36.7538, lon: 3.1866),
          ImportedPoint(lat: 36.7538, lon: 3.1876, wallMillis: start + 10000),
        ], droppedTimes: 1),
        sport: ImportSport.run,
        startWallMillis: start,
      );
      final stored = await summaryOf(out.activityId);
      expect(stored.points[0].timeNanos, 0);
      // The middle point states no instant: it may not be placed after the
      // third one, and it may not claim an instant the file never gave.
      expect(stored.points[1].timeNanos, 0);
      expect(stored.points[2].timeNanos, nanosOfSeconds(10));
    });
  });
}

/// A repository whose point write fails, the way a real disk or a killed
/// process makes it fail.
class _FailingRepository extends ActivityRepository {
  _FailingRepository(super.db);

  @override
  Future<void> appendPoints(int activityId, List<StoredPoint> points) {
    throw StateError('the disk died mid-write');
  }
}
