/// Formatting primitives for the recording screen. The decimal separator is
/// always passed in as a token from the locale layer — never hard-coded.
class Format {
  const Format._();
  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String distance(double metres, {required String sep}) {
    final km = metres / 1000.0;
    final whole = km.floor();
    final frac = ((km - whole) * 100).round();
    if (frac == 100) return '${whole + 1}${sep}00';
    return '$whole$sep${_pad(frac)}';
  }

  static String pace(double secPerKm, {required String sep}) {
    if (secPerKm.isNaN || secPerKm <= 0 || secPerKm > 3600) return '--:--';
    final s = secPerKm.floor();
    return '${(s ~/ 60).toString()}:${_pad(s % 60)}';
  }

  static String duration(int nanos) {
    final s = (nanos / 1e9).floor();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h == 0 ? '${_pad(m)}:${_pad(sec)}' : '${_pad(h)}:${_pad(m)}:${_pad(sec)}';
  }
}
