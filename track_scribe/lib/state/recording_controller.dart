import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart'
    show LocationPermissionDenied;
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
    this.storageError,
    this.permissionDenied = false,
  });

  final Sport sport;
  final RecordingPhase phase;
  final RecorderEngine? engine;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;

  /// ر7/ر8 signal state, the single source the GPS banner renders from.
  final GpsQuality quality;

  /// R78 §4: set once a storage write fails — the session keeps recording,
  /// but the UI must stop claiming durability while this is non-null.
  final String? storageError;

  /// Spec §7 / R86: true only when the most recent start attempt was refused by
  /// a denied location permission. [AppGate] routes on it so a revoked
  /// permission shows the instructions screen, never a dead button. A
  /// successful start or a stop clears it.
  final bool permissionDenied;

  RecordingState copyWith({
    Sport? sport,
    RecordingPhase? phase,
    RecorderEngine? engine,
    GpsQuality? quality,
    bool? permissionDenied,
  }) => RecordingState(
    sport: sport ?? this.sport,
    phase: phase ?? this.phase,
    engine: engine ?? this.engine,
    quality: quality ?? this.quality,
    distanceM: distanceM,
    elapsedNanos: elapsedNanos,
    fixCount: fixCount,
    storageError: storageError,
    permissionDenied: permissionDenied ?? this.permissionDenied,
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

  // ---- R78/R79 persistence state (one session's worth; reset in start()) ----
  ActivityRepository? _repo;
  int? _activityId;
  int _pointsWritten = 0;
  Future<void> _writes = Future<void>.value();
  bool _sessionActive = false;
  ResumeRow? _resume;
  bool _awaitingResume = false;
  List<RawFix> _fixesBeforeResume = [];

  /// R81: the elapsed an earlier session of THIS activity had already measured
  /// when its checkpoint was written (0 for a fresh activity). Every duration
  /// persisted from this session — each checkpoint and the final
  /// `Activities` row — is `_resumeElapsedNanos + engine.elapsedNanos`, so the
  /// stored time and the stored distance are totals of the same sessions.
  /// Summing measured monotonic durations is not a ر1 violation; only deriving
  /// a duration from the wall clock would be. The on-screen الوقت stays
  /// session-only (R79), which is what the user actually watches.
  int _resumeElapsedNanos = 0;

  void setSport(Sport s) {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(sport: s);
  }

  /// R86: called by [AppGate] when the user completes the permission screen,
  /// so the gate hands them back to the recorder instead of routing on a
  /// stale denial.
  void acknowledgePermission() {
    state = state.copyWith(permissionDenied: false);
  }

  Future<void> start() async {
    if (state.phase != RecordingPhase.stopped) return;
    _gate = FixQualityGate(nowNanos: ref.read(gateClockProvider));
    state = state.copyWith(
      phase: RecordingPhase.starting,
      quality: GpsQuality.none,
      permissionDenied: false,
    );
    final src = ref.read(fixSourceProvider);
    try {
      await src.start();
    } on LocationPermissionDenied {
      // Spec §7 / R86: a denied permission is NOT a generic start failure — it
      // is the case the instructions screen exists for. `AppGate` reads this
      // flag and shows it instead of a silently dead button.
      _release();
      await _stopSourceQuietly(src);
      state = RecordingState(
        sport: state.sport,
        phase: RecordingPhase.stopped,
        engine: null,
        permissionDenied: true,
      );
      return;
    } on Object {
      // Any other source that refuses to start (a test double, a dead sensor)
      // must not strand the UI in `starting`: back to a stopped, fully usable
      // button, with no permission claim.
      _release();
      await _stopSourceQuietly(src);
      state = RecordingState(
        sport: state.sport,
        phase: RecordingPhase.stopped,
        engine: null,
        permissionDenied: false,
      );
      return;
    }
    _preparePersistence();
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

  /// R79: the checkpoint is loaded ONCE per session, before any fix can build
  /// an engine — fixes that arrive while it is in flight are queued and
  /// re-dispatched in order, so the engine is never created un-seeded and
  /// `_onFix` itself stays synchronous (R78: no fire-and-forget writes).
  void _preparePersistence() {
    _writes = Future<void>.value();
    _pointsWritten = 0;
    _activityId = null;
    _resume = null;
    _resumeElapsedNanos = 0;
    _fixesBeforeResume = [];
    _sessionActive = true;
    ActivityRepository? repo;
    try {
      repo = ref.read(activityRepositoryProvider);
    } on Object catch (e) {
      _noteStorageFailure(e);
    }
    _repo = repo;
    if (repo == null) {
      _awaitingResume = false;
      return;
    }
    _awaitingResume = true;
    unawaited(_loadResume(repo));
  }

  Future<void> _loadResume(ActivityRepository repo) async {
    try {
      _resume = await repo.loadResume();
    } on Object catch (e) {
      // A checkpoint that cannot be read is no checkpoint; the write chain
      // reports the storage failure itself if there is one.
      _resume = null;
      _noteStorageFailure(e);
    }
    // R81: seed the carried total BEFORE any buffered fix can write a
    // checkpoint, or the first write of a resumed session would drop the
    // previous session's time.
    _resumeElapsedNanos = _resume?.elapsedNanos ?? 0;
    final buffered = _fixesBeforeResume;
    _fixesBeforeResume = [];
    _awaitingResume = false;
    for (final fix in buffered) {
      _processFix(fix);
    }
  }

  void _onFix(RawFix fix) {
    if (_awaitingResume) {
      _fixesBeforeResume.add(fix);
      return;
    }
    _processFix(fix);
  }

  void _processFix(RawFix fix) {
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
      final resume = _resume;
      // R79: distance continues from the checkpoint and the on-screen الوقت
      // restarts — the engine seeds only anchor + distance
      // (recorder_engine.dart). The elapsed a resumed activity must PERSIST is
      // not the engine's: it is `_resumeElapsedNanos` + this engine's, so the
      // engine stays free of any cross-process clock (R81).
      e = RecorderEngine(
        SportConfig.forSport(state.sport),
        startNanos: fix.timeNanos,
        resumeFrom: resume?.lastStored,
        resumeDistanceM: resume?.distanceM ?? 0,
      );
      if (resume != null) _activityId = resume.activityId; // keep the old row
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
      storageError: state.storageError,
    );
    // ر13: every point the engine just stored is enqueued for writing NOW —
    // before the next fix can add another one to the same batch.
    if (e.storedPoints.length > _pointsWritten) {
      _enqueueStoredPoints(e);
    }
  }

  /// R78: a single Future chain — appendPoints never overlaps appendPoints,
  /// so the DB row order equals the engine order. The cursor advances only
  /// once the points have actually committed, so a failed write is retried
  /// with its backlog instead of silently skipping a point. The slice is cut
  /// when the link RUNS, not when it is enqueued: several fixes can arrive
  /// while one appendPoints is in flight, and each of them queues a link —
  /// every link appends only what the committed cursor has not covered yet,
  /// so no point is ever written twice.
  void _enqueueStoredPoints(RecorderEngine engine) {
    final repo = _repo;
    if (repo == null) {
      _noteStorageFailure(StateError('no storage backend for this session'));
      return;
    }
    final sport = state.sport;
    _writes = _writes.then((_) async {
      final all = engine.storedPoints;
      final written = _pointsWritten;
      if (all.length <= written) return; // an earlier link already covered it
      final slice = all.sublist(written);
      // The checkpoint pair is read in the same synchronous frame as the
      // slice, so it is exactly the engine state at the moment the slice's
      // last point was stored — a resume between two writes can never mix an
      // old anchor with a new distance.
      final lastStored = slice.last;
      final distanceAtSlice = engine.distanceMeters;
      // R81: the persisted elapsed is this session's measured duration PLUS
      // what the checkpoint we resumed from already carried — the same total
      // `distanceAtSlice` has always been, so both halves describe the same
      // set of sessions.
      final elapsedAtSlice = _resumeElapsedNanos + engine.elapsedNanos;
      final id = _activityId ??= await repo.insertActivity(
        uuid: _newActivityUuid(),
        sport: sport.name,
        // startWallMillis is display metadata ONLY — never a duration source
        // (ر1/R21).
        startWallMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await repo.appendPoints(id, slice);
      _pointsWritten += slice.length;
      // R83, the accepted bound: the checkpoint is written AFTER the slice
      // commits, so if it throws the cursor has already advanced — no stored
      // point is ever re-written, and this slice's distance/elapsed are missing
      // from a checkpoint that is now stale by exactly one slice, behind the
      // storage error already reported. The reverse order is worse: a
      // checkpoint pointing at rows that never landed loses those rows forever
      // while the total counts them.
      await repo.saveResume(
        activityId: id,
        lastStored: lastStored,
        distanceM: distanceAtSlice,
        elapsedNanos: elapsedAtSlice,
      );
    }).catchError((Object error) {
      _noteStorageFailure(error);
    });
  }

  static String _newActivityUuid() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random.secure().nextInt(1 << 32).toRadixString(36);
    return 'act-$micros-$entropy';
  }

  /// R78 §4: a storage failure neither kills the session nor goes unnoticed —
  /// recording continues, `storageError` tells the UI durability is no longer
  /// claimed, and no async error escapes (the chain owns every throw).
  /// R82: a failure that arrives after [_release] (the stop drain) has no live
  /// session to attach it to — `stop()` resets the state one statement later,
  /// so a state field would be discarded immediately and the error would vanish
  /// in total silence. It goes to `dart:developer`'s log instead, the channel
  /// the device checks read with `adb logcat`; the surviving resume row is the
  /// recovery path, so nothing recorded is lost even though the run ends.
  void _noteStorageFailure(Object error) {
    if (!_sessionActive) {
      developer.log(
        'storage write failed after the session ended, durability was not '
        'claimed for it: $error',
        name: 'track_scribe/storage',
        error: error,
        level: 1000, // package:logging SEVERE — a data-loss risk, not chatter
      );
      return;
    }
    final s = state;
    // The banner is the user's signal; this is the developer's. A device
    // session that persisted nothing produced zero logcat output, which made
    // the failure indistinguishable from a healthy one while field-testing.
    developer.log(
      'storage write failed during the session, recording continues undurable: '
      '$error',
      name: 'track_scribe/storage',
      error: error,
      level: 1000, // package:logging SEVERE — a data-loss risk, not chatter
    );
    state = RecordingState(
      sport: s.sport,
      phase: s.phase,
      engine: s.engine,
      distanceM: s.distanceM,
      elapsedNanos: s.elapsedNanos,
      fixCount: s.fixCount,
      quality: s.quality,
      storageError: 'storage write failed, recording continues undurable: $error',
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
  /// dead-end): both paths release the source and return to `stopped`. A
  /// session where ر7 never opened created no activity row, and its resume
  /// checkpoint (if any) survives untouched (ر12).
  Future<void> stop() async {
    final src = ref.read(fixSourceProvider);
    _release();
    await src.stop();
    // points queued before the stop are committed before the row is closed
    await _writes;
    final engine = state.engine;
    final activityId = _activityId;
    final repo = _repo;
    if (engine != null && activityId != null && repo != null) {
      try {
        final stats = engine.stats;
        await repo.finishActivity(
          activityId: activityId,
          // R81: the carried total plus this session's own duration — the same
          // set of sessions `engine.distanceMeters` already accumulated.
          elapsedNanos: _resumeElapsedNanos + engine.elapsedNanos,
          distanceM: engine.distanceMeters,
          fixCount: stats.fixCount,
          rejectedCount: stats.rejectedCount,
          mockDetected: stats.mockFixCount > 0,
        );
        await repo.clearResume(activityId);
      } on Object {
        // The session is over and the state resets below; the resume row
        // survives, so the data stays recoverable on the next start.
      }
    }
    state = RecordingState(
      sport: state.sport,
      phase: RecordingPhase.stopped,
      engine: null,
    );
  }

  void _release() {
    _sessionActive = false;
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
