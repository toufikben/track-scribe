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
    required this.isOpen,
  });

  final int id;
  final String sport;

  /// Display metadata only — the same contract as `ActivitySummary`'s field
  /// (ر1/R21): it orders and labels the list, and never becomes a duration.
  final int startWallMillis;
  final double distanceM;
  final int elapsedNanos;

  /// True while a `resume` checkpoint still names this activity AND
  /// `activities.updated_at` is still null, i.e. the recording was paused or
  /// killed rather than stopped (ر12/R79). Review I-1 added the second half:
  /// `ActivityRepository.finishActivity` stamps that column, so "finished" is a
  /// stored fact and a checkpoint that survived the kill that followed the stop
  /// can no longer relabel a real activity «قيد التسجيل» (which used also to
  /// cost it its tap target, `history_screen.dart`). For a genuinely open row
  /// `distanceM`/`elapsedNanos` are the CHECKPOINT's measured totals (ر123): the
  /// `activities` row itself still holds the schema defaults
  /// 0 m / 0 ns — unmeasured numbers no view may print («لا نطبع رقمًا لم
  /// يُقس») — so the list marks the row «قيد التسجيل» instead of presenting
  /// it as finished (ر121).
  ///
  /// Review I-2: this type deliberately has NO per-fix columns. `fixCount`,
  /// `rejectedCount` and `mockDetected` used to be carried here, nothing in
  /// `lib/` ever rendered them, and for an open row they were the unfinalized
  /// row's zeros — the exact family ر99–ر102 legislate against, guarded until
  /// then by two doc comments. Deleting the fields makes that unprintable by
  /// construction; the columns are final and rendered on the detail screen,
  /// which reads them through `ActivitySummary`.
  final bool isOpen;
}
