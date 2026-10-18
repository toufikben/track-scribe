import 'package:track_scribe/data/activity_source.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// One finished activity as the detail screen reads it: the row's totals
/// plus every stored point in engine order (rowid order = write order, R78).
class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.sport,
    required this.startWallMillis,
    required this.distanceM,
    required this.elapsedNanos,
    required this.source,
    required this.fixCount,
    required this.rejectedCount,
    required this.mockDetected,
    required this.points,
  });

  final int id;
  final String sport;

  /// Display metadata only — a wall-clock stamp written at insert time and
  /// never a duration source (ر1/R21). The elapsed beside it is measured
  /// monotonic nanoseconds, so the two must never be subtracted from each
  /// other to invent a missing total.
  final int startWallMillis;
  final double distanceM;
  final int elapsedNanos;

  /// R125 — `activities.source`. The detail screen renders the same stats as a
  /// history row through the shared stat panel, so it needs the provenance for
  /// the same reason: [elapsedUnstated] decides whether «الوقت» is a measured
  /// duration or «غير معروف».
  final String source;

  /// See [isUnstatedElapsed]: an imported file that stated no clock stores 0,
  /// and 0 here is an absence no view may print as a duration (ر99).
  bool get elapsedUnstated =>
      isUnstatedElapsed(source: source, elapsedNanos: elapsedNanos);

  final int fixCount;
  final int rejectedCount;
  final bool mockDetected;
  final List<StoredPoint> points;
}
