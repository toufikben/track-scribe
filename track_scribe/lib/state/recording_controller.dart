import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/gps_quality.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';

class RecordingState {
  const RecordingState({
    required this.sport,
    required this.phase,
    this.engine,
    this.distanceM = 0,
    this.elapsedNanos = 0,
    this.fixCount = 0,
    this.quality = GpsQuality.none,
  });

  final Sport sport;
  final RecordingPhase phase;
  final RecorderEngine? engine;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;

  /// ر7/ر8 signal state, the single source the GPS banner renders from.
  final GpsQuality quality;

  RecordingState copyWith({
    Sport? sport,
    RecordingPhase? phase,
    RecorderEngine? engine,
    GpsQuality? quality,
  }) => RecordingState(
    sport: sport ?? this.sport,
    phase: phase ?? this.phase,
    engine: engine ?? this.engine,
    quality: quality ?? this.quality,
    distanceM: distanceM,
    elapsedNanos: elapsedNanos,
    fixCount: fixCount,
  );
}

enum RecordingPhase { stopped, starting, recording }

final fixSourceProvider = Provider<FixSource>((_) => SyntheticFixSource());

/// Monotonic nanosecond source feeding the ر8 "20 s without a fix" rule.
///
/// Injectable on purpose: ر8 is a rule about the ABSENCE of input, so it cannot
/// be proven by a test that waits 20 real seconds. Tests override it with a
/// counter they advance; production keeps the default — a [Stopwatch], never
/// `DateTime.now()` (the project's monotonic-time rule).
final gateClockProvider = Provider<int Function()>((_) {
  final sw = Stopwatch()..start();
  return () => sw.elapsedMicroseconds * 1000;
});

class RecordingController extends Notifier<RecordingState> {
  @override
  RecordingState build() {
    // A container disposed mid-session (test teardown, app exit) must not leave
    // the quality tick running: a pending Timer fails the widget test that owns
    // it.
    ref.onDispose(_release);
    return RecordingState(
      sport: Sport.run,
      phase: RecordingPhase.stopped,
      engine: null,
    );
  }

  /// ر8 is measured against the wall of the session, not against the last fix
  /// the UI happened to see, so the gate lives here for the duration of one
  /// recording and nothing else keeps signal state.
  FixQualityGate? _gate;
  StreamSubscription<RawFix>? _sub;
  Timer? _qualityTick;

  void setSport(Sport s) {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(sport: s);
  }

  Future<void> start() async {
    if (state.phase != RecordingPhase.stopped) return;
    _gate = FixQualityGate(nowNanos: ref.read(gateClockProvider));
    state = state.copyWith(
      phase: RecordingPhase.starting,
      quality: GpsQuality.none,
    );
    final src = ref.read(fixSourceProvider);
    try {
      await src.start();
    } on Object {
      // A source that refuses to start (a denied location permission in
      // production, or a test double) must not strand the UI in `starting`:
      // back to a stopped, fully usable button. Task 9b's onboarding turns this
      // into the user-facing permission request.
      _release();
      await _stopSourceQuietly(src);
      state = RecordingState(
        sport: state.sport,
        phase: RecordingPhase.stopped,
        engine: null,
      );
      return;
    }
    _sub = src.fixes.listen(
      _onFix,
      // A stream error is a gap in the signal, not a fatal crash: ر8 already
      // describes it to the user.
      onError: (Object _) => _recomputeQuality(),
      cancelOnError: false,
    );
    // ر8 needs a clock, not a fix: without this the banner would only notice a
    // dead signal the moment the next fix arrived, i.e. never.
    _qualityTick = Timer.periodic(const Duration(seconds: 1), (
      _) => _recomputeQuality(),
    );
  }

  void _onFix(RawFix fix) {
    final gate = _gate;
    if (gate == null) return; // a stray fix after stop/cancel
    final ready = gate.add(fix);

    var e = state.engine;
    if (e == null) {
      if (!ready) {
        // ر7 — the signal is not good enough yet, so nothing is recorded
        // against it: no engine, no distance, no stored point.
        state = state.copyWith(quality: gate.quality);
        return;
      }
      e = RecorderEngine(
        SportConfig.forSport(state.sport),
        startNanos: fix.timeNanos,
      );
    }
    e.onFix(fix);
    // mutate through a fresh state object so Riverpod notifies listeners
    state = RecordingState(
      sport: state.sport,
      phase: RecordingPhase.recording,
      engine: e,
      distanceM: e.distanceMeters,
      elapsedNanos: e.elapsedNanos,
      fixCount: e.stats.fixCount,
      quality: gate.quality,
    );
  }

  /// Re-reads the gate so ر8's `lost` can appear with no fix arriving.
  void _recomputeQuality() {
    final gate = _gate;
    if (gate == null) return;
    final q = gate.quality;
    if (q == state.quality) return;
    state = state.copyWith(quality: q);
  }

  /// Stop is also the cancel gesture from `starting` (ruling on the Task 7
  /// dead-end): both paths release the source and return to `stopped`.
  Future<void> stop() async {
    final src = ref.read(fixSourceProvider);
    _release();
    await src.stop();
    state = RecordingState(
      sport: state.sport,
      phase: RecordingPhase.stopped,
      engine: null,
    );
  }

  void _release() {
    _qualityTick?.cancel();
    _qualityTick = null;
    _sub?.cancel();
    _sub = null;
    _gate = null;
  }

  Future<void> _stopSourceQuietly(FixSource src) async {
    try {
      await src.stop();
    } on Object {
      // Nothing to report: the session never started.
    }
  }
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState>(
  RecordingController.new,
);
