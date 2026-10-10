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
}
