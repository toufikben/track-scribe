/// `activities.source` (R125) and the one rule derived from it.
///
/// This file exists so the fact has a single spelling. The importer writes
/// [kSourceGpx], the schema default is [kSourceRecorded], and the reads turn
/// the column into [isUnstatedElapsed] for the views — three places that must
/// agree. Living in `database.dart` instead would drag drift (and the whole
/// generated table file) into every type that only needs to know whether a
/// duration was measured.
const kSourceRecorded = 'recorded';
const kSourceGpx = 'gpx';

/// True when the stored `elapsedNanos == 0` means *the source stated no clock*
/// rather than *this activity took no time* — the distinction ر99 turns into
/// «لا نطبع رقمًا لم يُقس», since `Format.duration(0)` prints «00:00».
///
/// A recording that stopped the instant it started really did measure zero
/// seconds, so the gate keys on the provenance and never on the number alone
/// (that is why the column exists at all). The one case this labels generously
/// is a file whose every `<time>` is the same instant: it states a span, that
/// span is zero, and the list shows «غير معروف» instead of claiming a
/// zero-length activity — an absence read as an absence, never the reverse.
bool isUnstatedElapsed({required String source, required int elapsedNanos}) =>
    source == kSourceGpx && elapsedNanos == 0;
