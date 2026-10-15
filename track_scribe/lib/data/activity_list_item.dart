/// One row of the history list (خطة 3 §1) — the activity's stored TOTALS and
/// nothing else.
///
/// ر117: this type exists to make the list's cost visible in the code. The
/// detail screen's `ActivitySummary` carries every `StoredPoint` of one
/// activity, which is correct there (one activity at a time, released with the
/// screen per ر116) and wrong here: a list read that returned summaries would
/// hold every track the user ever recorded alive at once, on a 4 GB target
/// whose tile raster cache wants the same memory.
class ActivityListItem {
  const ActivityListItem({
    required this.id,
    required this.sport,
    required this.startWallMillis,
    required this.distanceM,
    required this.elapsedNanos,
    required this.fixCount,
    required this.rejectedCount,
    required this.mockDetected,
    required this.isOpen,
  });

  final int id;
  final String sport;

  /// Display metadata only — the same contract as `ActivitySummary`'s field
  /// (ر1/R21): it orders and labels the list, and never becomes a duration.
  final int startWallMillis;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;
  final int rejectedCount;
  final bool mockDetected;

  /// True while a `resume` checkpoint still names this activity, i.e. the
  /// recording was paused or killed rather than stopped (ر12/R79). For such a
  /// row `distanceM`/`elapsedNanos` are the CHECKPOINT's measured totals
  /// (ر123): the `activities` row itself still holds the schema defaults
  /// 0 m / 0 ns — unmeasured numbers no view may print («لا نطبع رقمًا لم
  /// يُقس») — so the list marks the row «قيد التسجيل» instead of presenting
  /// it as finished (ر121). The checkpoint table carries no per-fix columns
  /// (database.dart:44-68), so `fixCount`/`rejectedCount`/`mockDetected` stay
  /// the unfinalized row's defaults — that is exactly why a list screen must
  /// not render them for an open row.
  final bool isOpen;
}
