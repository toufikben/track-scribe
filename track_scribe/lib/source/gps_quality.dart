import 'package:track_scribe/engine/raw_fix.dart';

/// GNSS signal states the recording UI reports (spec §5, rules ر7/ر8).
///
/// `none` is the state before this session ever saw a fix; `ok`/`degraded`/
/// `searching` are ر7's accuracy tiers OF THE CURRENT FIX (> 35 m → searching:
/// too coarse to record against). While ر7 has not yet promoted the session
/// the UI shows the searching label regardless of tier — that is the recording
/// phase's statement, not the tier's; `lost` is ر8's 20 s of silence.
enum GpsQuality { none, searching, ok, degraded, lost }

/// ر7's accuracy tiers as a pure rule, so the banner chip and the start gate
/// cannot drift apart. Thresholds are laws, not taste:
/// > 35 m → searching, 20–35 m → degraded, ≤ 20 m → ok.
class GpsQualityX {
  const GpsQualityX._();

  /// ر7: at or below this 1σ radius a fix may open the start gate.
  static const double goodEnoughM = 35;

  /// Above this the live signal is only `degraded`, never `ok`.
  static const double okOrDegradedM = 20;

  static GpsQuality fromAccuracy(double a) =>
      a > goodEnoughM
      ? GpsQuality.searching
      : (a > okOrDegradedM ? GpsQuality.degraded : GpsQuality.ok);
}

/// ر7 in one place: the accuracy a fix must reach before it may be recorded
/// against at all.
bool isFixGoodEnough(RawFix fix) =>
    fix.accuracyM <= GpsQualityX.goodEnoughM;

/// ر8's window: this long without any fix and the signal counts as lost.
const Duration gpsLostAfter = Duration(seconds: 20);

/// The "no recording until the signal is good enough" rule, as data.
///
/// [ready] (ر7) becomes true on the first pair of *consecutive* fixes at
/// ≤ 35 m and then stays true: it is a start gate, not a continuous licence —
/// losing the signal afterwards is a display state (`lost`/`degraded`), never a
/// silent reason to keep recording against a stale anchor.
///
/// [quality] is the ر7/ر8 state machine. Because ر8 is a rule about the
/// *absence* of input, it cannot be evaluated at fix time only, so it is a
/// getter over an injectable monotonic clock: [FixQualityGate] with no
/// `nowNanos` reads a private [Stopwatch] (wall-clock independent, per the
/// project's monotonic-time rule), while tests inject a counter and advance
/// it deterministically instead of sleeping 20 s.
class FixQualityGate {
  FixQualityGate({this.nowNanos});

  /// Injectable monotonic clock in nanoseconds (see the class comment).
  final int Function()? nowNanos;
  final Stopwatch _stopwatch = Stopwatch();

  bool _ready = false;
  int _goodStreak = 0;
  double? _lastAccuracyM;
  int? _lastFixAtNanos;

  bool get ready => _ready;

  /// Feeds one fix. Returns [ready] after it, i.e. whether the caller may start
  /// recording — the return value is what promotes the phase, so the rule lives
  /// here and nowhere else.
  bool add(RawFix fix) {
    _lastAccuracyM = fix.accuracyM;
    _lastFixAtNanos = _now();
    if (isFixGoodEnough(fix)) {
      _goodStreak++;
      if (_goodStreak >= 2) _ready = true; // ر7: two consecutive good fixes
    } else {
      _goodStreak = 0;
    }
    return _ready;
  }

  GpsQuality get quality {
    final last = _lastFixAtNanos;
    if (last == null) return GpsQuality.none;
    // Duration has no nanosecond resolution on Dart (microseconds is the fine
    // unit), hence the conversion instead of `inNanoseconds`.
    if (_now() - last >= gpsLostAfter.inMicroseconds * 1000) {
      return GpsQuality.lost; // ر8
    }
    // ر7's tiers applied to the CURRENT fix, verbatim and nothing else: the
    // gate's readiness is a separate truth (it opens once and stays open), and
    // "still searching until ر7 promotes the session" is the UI phase's
    // statement, rendered in gps_status_banner.dart — not a doctored tier here.
    return GpsQualityX.fromAccuracy(_lastAccuracyM!);
  }

  int _now() {
    final injected = nowNanos;
    if (injected != null) return injected();
    if (!_stopwatch.isRunning) _stopwatch.start();
    return _stopwatch.elapsedMicroseconds * 1000;
  }
}
