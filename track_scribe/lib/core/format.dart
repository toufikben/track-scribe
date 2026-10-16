/// Formatting primitives for the recording screen. The decimal separator is
/// always passed in as a token from the locale layer — never hard-coded.
class Format {
  const Format._();
  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Metres of accumulated distance as `km,ss` — `sep` is the locale's decimal
  /// separator token.
  ///
  /// Only ever fed a monotonic accumulation: `floor()` on a negative would
  /// borrow a whole kilometre (`-500 m` would print `-1,50`), so a delta-style
  /// caller fails loudly here instead of lying quietly.
  static String distance(double metres, {required String sep}) {
    assert(metres >= 0, 'distance is a monotonic accumulation, got $metres m');
    final km = metres / 1000.0;
    final whole = km.floor();
    final frac = ((km - whole) * 100).round();
    if (frac == 100) return '${whole + 1}${sep}00';
    return '$whole$sep${_pad(frac)}';
  }

  /// Seconds-per-kilometre as `m:ss`; out-of-range and NaN input render `--:--`.
  /// sep is accepted for locale-token symmetry; pace has no decimal part.
  static String pace(double secPerKm, {required String sep}) {
    if (secPerKm.isNaN || secPerKm <= 0 || secPerKm > 3600) return '--:--';
    final s = secPerKm.floor();
    return '${(s ~/ 60).toString()}:${_pad(s % 60)}';
  }

  /// Elapsed monotonic nanos as `mm:ss`, gaining `hh:` past an hour.
  ///
  /// Negative input is a bug, not a format: Dart's `%` is non-negative, so
  /// `-1e9` ns would otherwise print `59:59`.
  static String duration(int nanos) {
    assert(nanos >= 0, 'duration is a monotonic accumulation, got $nanos ns');
    final s = (nanos / 1e9).floor();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h == 0 ? '${_pad(m)}:${_pad(sec)}' : '${_pad(h)}:${_pad(m)}:${_pad(sec)}';
  }

  /// The Arabic month names in calendar order (ر118). Hand-rolled because the
  /// app has no locale package — R23 already rejects `flutter_localizations`
  /// for the same reason, and adding `intl` for one label would put locale
  /// data into an app whose whole promise is that nothing is fetched.
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// A start stamp as `15 أكتوبر 2026 · 21:33`, or `اليوم` / `أمس` for the two
  /// most recent CALENDAR days.
  ///
  /// ر1/R21 applies to this function in full: the wall clock is read to label
  /// and order a row, never to produce a duration — the day count below chooses
  /// which WORD to print and nothing else. A calendar day is what «اليوم»/«أمس»
  /// mean, so the stamps are reduced to their local `year/month/day` fields
  /// rather than subtracted as instants: 23:50 recorded, 00:10 read is one day
  /// ago, not twenty minutes ago. That subtraction runs in UTC — see the body —
  /// because a local midnight-to-midnight gap is not always 24 h.
  ///
  /// `now` is injectable so the test does not depend on when it runs.
  static String activityDate(int startWallMillis, {DateTime? now}) {
    final start = DateTime.fromMillisecondsSinceEpoch(startWallMillis);
    final reference = now ?? DateTime.now();
    // Whole CALENDAR days, counted in UTC so a daylight step that lands on local midnight
    // (Asia/Beirut, Asia/Amman, America/Santiago, America/Asuncion, America/Havana: 23 h or
    // 25 h between two local midnights) can never truncate to the wrong day number. The
    // operands are the local `year/month/day` fields, so «أي يوم» is still the user's local
    // calendar day; only the subtraction is zone-free. This value chooses which WORD to
    // print and nothing else — ر1/R21 is untouched: no duration is derived from the wall
    // clock anywhere in this file.
    final calendarDayGap = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
    ).difference(DateTime.utc(start.year, start.month, start.day));
    final days = calendarDayGap.inDays;
    final when = days == 0
        ? 'اليوم'
        : days == 1
        ? 'أمس'
        : '${start.day} ${_monthsAr[start.month - 1]} ${start.year}';
    return '$when · ${_pad(start.hour)}:${_pad(start.minute)}';
  }
}
