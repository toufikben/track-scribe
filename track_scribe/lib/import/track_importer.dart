import 'dart:math';

import '../core/geo.dart';
import '../data/activity_repository.dart';
import '../data/database.dart';
import '../engine/raw_fix.dart';
import '../source/gps_quality.dart';
import 'gpx_track.dart';

/// A GPX `<time>` is a millisecond instant, while the columns it lands in
/// (`track_points.time_nanos`, `activities.elapsed_nanos`) count nanoseconds,
/// because the recorder reads them from a Stopwatch. dart:core has no
/// nanosecond unit — `Duration` stops at microseconds — so the factor is named
/// once here instead of appearing as a bare `* 1000000` twice.
const _nanosPerMillis = Duration.microsecondsPerMillisecond * 1000;

/// Why an import stopped. The message is user-facing Arabic, the same style as
/// [GpxParseException]: a refused file must say what was refused.
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;
}

/// What one import wrote — and, just as important, what it could not know.
class ImportOutcome {
  const ImportOutcome({
    required this.activityId,
    required this.pointCount,
    required this.distanceM,
    required this.elapsedNanos,
    required this.elapsedKnown,
    required this.rejectedPoints,
    required this.droppedTimes,
  });

  final int activityId;
  final int pointCount;

  /// The polyline of the positions the file kept (ر3/ر6 cannot run here: a
  /// foreign file states no 1σ, so there is no accuracy to gate a jump with).
  final double distanceM;

  final int elapsedNanos;

  /// false means the stored elapsed is 0 because the file's clock did not
  /// survive reading — NOT that the activity took no time. A view must say
  /// «زمن غير معروف» rather than print 0:00 (ر99: no surface prints a number
  /// nobody measured).
  final bool elapsedKnown;

  /// Points the reader refused (bad coordinates). Reported to the caller, who
  /// can tell the user; never stored in `activities.rejectedCount`, which
  /// answers a different question: what THIS app's engine refused live.
  final int rejectedPoints;

  /// Stamps the reader dropped for the same reason as [elapsedKnown]'s gate.
  final int droppedTimes;
}

/// §2أ: the write half of importing a GPX file from another app.
///
/// Everything here is one transaction: a half-imported activity is worse than a
/// refused file, because the history list would show a ride nobody rode.
class TrackImporter {
  TrackImporter(this._db, this._repo);

  final AppDatabase _db;
  final ActivityRepository _repo;

  Future<ImportOutcome> importTrack(
    ImportedTrack track, {
    required ImportSport sport,
    required int startWallMillis,
  }) async {
    if (track.points.isEmpty) {
      throw const ImportException('الملف لا يحمل أي نقطة صالحة');
    }

    // The elapsed a file states is the span of its own stamps — and only when
    // that span really brackets the track:
    //   * `droppedTimes == 0`: the reader lost no stamp, so nothing the file
    //     wrote as a clock was thrown away;
    //   * the FIRST and LAST kept points both carry one. A file whose opening
    //     point has no `<time>` states a span shorter than the activity it is
    //     supposed to describe, and a shorter number printed as if it were the
    //     whole one is exactly the kind of claim ر99 forbids.
    // (ر1 forbids OUR wall clock from becoming a duration while recording; here
    // nothing is measured — the span is copied from the file, and `source`
    // says so.)
    var elapsedNanos = 0;
    var elapsedKnown = false;
    final bracketed =
        track.droppedTimes == 0 &&
        track.points.first.wallMillis != null &&
        track.points.last.wallMillis != null;
    if (bracketed) {
      final stated = <int>[
        for (final p in track.points)
          if (p.wallMillis != null) p.wallMillis!,
      ];
      if (stated.length >= 2) {
        elapsedNanos = (stated.last - stated.first) * _nanosPerMillis;
        elapsedKnown = true;
      }
    }

    var distanceM = 0.0;
    for (var i = 1; i < track.points.length; i++) {
      distanceM += haversineMeters(
        track.points[i - 1].lat,
        track.points[i - 1].lon,
        track.points[i].lat,
        track.points[i].lon,
      );
    }

    // The instant a point is placed at, as an offset from the row's start. A
    // kept stamp gives it; a dropped one keeps the LAST instant the file
    // stated, so an unstamped point never lands after a later point and never
    // gets a time the file did not give it.
    final firstStamp = track.startWallMillis;
    var carriedNanos = 0;
    final points = <StoredPoint>[];
    for (final p in track.points) {
      final wall = p.wallMillis;
      if (wall != null && firstStamp != null) {
        // The reader guarantees kept stamps increase, so this only moves
        // forward.
        carriedNanos = (wall - firstStamp) * _nanosPerMillis;
      }
      points.add(
        StoredPoint(
          lat: p.lat,
          lon: p.lon,
          timeNanos: carriedNanos,
          // R76: a foreign file states no 1σ, so accuracy is unmeasured —
          // stored as SQL NULL by the repository, never as a number.
          accuracyM: unmeasuredAccuracyM,
          type: WaypointType.normal,
          altitudeM: p.eleM,
        ),
      );
    }

    final uuid = _newImportUuid();
    return _db.transaction(() async {
      final activityId = await _repo.insertImportedActivity(
        uuid: uuid,
        sport: sport.name,
        startWallMillis: startWallMillis,
        distanceM: distanceM,
        elapsedNanos: elapsedNanos,
        fixCount: points.length,
      );
      await _repo.appendPoints(activityId, points);
      return ImportOutcome(
        activityId: activityId,
        pointCount: points.length,
        distanceM: distanceM,
        elapsedNanos: elapsedNanos,
        elapsedKnown: elapsedKnown,
        rejectedPoints: track.rejectedPoints,
        droppedTimes: track.droppedTimes,
      );
    });
  }

  static String _newImportUuid() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random.secure().nextInt(1 << 32).toRadixString(36);
    return 'imp-$micros-$entropy';
  }
}
