import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/core/monotonic.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';

/// Sink for EVERY accepted raw fix (ر9/R41): invoked synchronously, once per
/// fix, before `RecorderEngine.onFix` returns. The verdict is the engine's
/// classification of that fix (normal store / idle marker / rejected jump /
/// gate-skipped); the engine itself keeps no raw list — a later task pipes
/// this into the persistence layer.
typedef RawFixSink = void Function(RawFix fix, WaypointType verdict);

/// Counters exposed to the UI/persistence layers (ر10 mock detection feeds the
/// activity-level flag; ر4/ر1 diagnostics).
class EngineStats {
  const EngineStats({
    this.fixCount = 0, this.rejectedCount = 0, this.droppedOutOfOrder = 0,
    this.mockFixCount = 0,
  });
  final int fixCount, rejectedCount, droppedOutOfOrder, mockFixCount;
}

/// Pure-Dart recorder core. Consumes RawFixes, decides which points are
/// stored, accumulates distance from the anchor — the last point that PASSED
/// the jump test (ر2/R39) — rejects impossible jumps without deleting them
/// (ر4/ر9), re-acquires the anchor after genuine transport (R40), and marks
/// standing-still as IDLE while time keeps flowing (ر6). Imports no Flutter,
/// dart:io, or plugin — testable on the desktop with `flutter test` alone.
class RecorderEngine {
  /// Deliberately does NOT pre-accept [startNanos] into the ticker: a first
  /// fix stamped exactly `startNanos` is legitimate (elapsed 0), and the
  /// ticker's strict `>` gate would silently drop it. The ticker remains the
  /// single source of truth for ordering (ر1) and for every duration below.
  RecorderEngine(this.config,
      {required int startNanos, this.rawSink})
      : _sessionStartNanos = startNanos,
        _ticker = MonotonicTicker();

  /// R40: rejected fixes must be mutually consistent across this many
  /// consecutive pairs (each d/dt <= v_max) before the anchor may move.
  /// GPS noise cannot fabricate three such pairs, so the transport rescue
  /// never bills the teleport gap itself.
  static const int _reanchorAfterPairs = 3;

  final SportConfig config;
  final RawFixSink? rawSink;
  final MonotonicTicker _ticker;
  final int _sessionStartNanos;
  final List<StoredPoint> _points = [];

  /// R39: the yardstick for distance accumulation and for the next
  /// gate/jump/heartbeat comparison (ر2). It moves only with points that
  /// PASSED the jump test — a rejected point never moves it, otherwise the
  /// first noise spike becomes the reference and freezes accumulation.
  StoredPoint? _anchor;

  /// R40 re-acquisition state: while fixes disagree with the anchor, track
  /// the chain of consecutive fixes that are mutually consistent, its length
  /// in completed pairs and its internal movement.
  StoredPoint? _chainPrev;
  int _consistentPairs = 0;
  double _chainDistanceM = 0;

  int? _idleSinceNanos;
  bool _idle = false;
  bool _hasAcceptedFix = false;

  /// Fix round 2 (ر3): monotonic time of the LAST append to `_points` — any
  /// type, including idle markers and rejected keeps. The heartbeat is
  /// "15 s without a point", so it must be measured against the point stream,
  /// never against the anchor: during idle the anchor only moves via idle
  /// appends, and an anchor-based comparison (plus the old `_lastWasIdleMarker`
  /// guard) made the idle heartbeat permanently unreachable. -1 until the
  /// first append; the heartbeat check is only reachable after one.
  int _lastAppendNanos = -1;
  int _fixCount = 0, _rejected = 0, _dropped = 0, _mocks = 0;
  double _distanceM = 0;

  List<StoredPoint> get storedPoints => List.unmodifiable(_points);
  double get distanceMeters => _distanceM;

  /// Display/accumulation-safe elapsed: 0 until the first fix is accepted,
  /// then ticker-last minus start, never negative.
  int get elapsedNanos {
    if (!_hasAcceptedFix) return 0;
    final e = _ticker.lastNanos - _sessionStartNanos;
    return e < 0 ? 0 : e;
  }

  bool get isIdle => _idle;
  EngineStats get stats => EngineStats(
      fixCount: _fixCount, rejectedCount: _rejected,
      droppedOutOfOrder: _dropped, mockFixCount: _mocks);

  void onFix(RawFix fix) {
    // ر1 — the ticker is the enforcement point for monotonicity; equal or
    // earlier timestamps are dropped, never averaged. A dropped fix was
    // never accepted, so it must not reach the sink (R41).
    if (!_ticker.accept(fix.timeNanos)) {
      _dropped++;
      return;
    }
    _hasAcceptedFix = true;
    _fixCount++;
    if (fix.isMocked) _mocks++;                       // ر10
    final verdict = _process(fix);
    rawSink?.call(fix, verdict); // R41 — synchronous, before onFix returns
  }

  WaypointType _process(RawFix fix) {
    final anchor = _anchor;
    if (anchor == null) {
      _store(fix, WaypointType.normal, addDistance: false);
      return WaypointType.normal;
    }

    final dt = _ticker.secondsSince(anchor.timeNanos);
    final d = haversineMeters(anchor.lat, anchor.lon, fix.lat, fix.lon);
    final impliedSpeed = dt > 0 ? d / dt : null;
    final speed = fix.speedMps ?? impliedSpeed;        // Doppler wins over differencing

    // ر4 — impossible jump: keep the raw point, add nothing to distance.
    // Spec ر4/ر5 threshold is v_max itself; the brief's draft used 2× v_max,
    // a silent relaxation the spec does not authorise — spec wins.
    // R39: _store() below keeps _anchor where it is; R40 then watches for a
    // locally consistent chain among the rejected fixes.
    if (d > config.maxJumpM ||
        (impliedSpeed != null && impliedSpeed > config.maxSpeedMps)) {
      _rejected++;
      _trackReacquisition(_store(fix, WaypointType.rejected, addDistance: false));
      return WaypointType.rejected;
    }
    _resetChain(); // a fix agreeing with the anchor invalidates the chain

    final idleEvent = _updateIdle(fix, speed ?? 0.0);

    // ر3 heartbeat — "15 s without a point": measured from the last APPEND
    // (_lastAppendNanos), not from the anchor (fix round 2, Important 2).
    final heartbeatDue = _lastAppendNanos >= 0 &&
        _ticker.secondsSince(_lastAppendNanos) >= config.forceStoreAfterS;

    // Fix round 2, Important 1: every path below performs AT MOST one _store
    // for this fix — `_updateIdle` no longer stores, it only reports the
    // transition — so a double append is structurally impossible and the
    // returned verdict always matches the append it made.
    if (idleEvent == _IdleTransition.resumed) {
      // Idle→resume: append exactly once and bill the pending `d` measured
      // from the pre-idle anchor — this is real movement that ended the idle,
      // never standing-still, so ر6's zero-distance rule does not cover it.
      _store(fix, WaypointType.normal, addDistance: true);
      return WaypointType.normal;
    }

    if (_idle) {
      // ر6 — time flows, distance does not. Entering idle and the heartbeat
      // share this single store: at most one append per fix.
      if (heartbeatDue || idleEvent == _IdleTransition.entered) {
        _store(fix, WaypointType.idle, addDistance: false);
      }
      return WaypointType.idle;
    }
    if (d >= config.gateFor(fix.accuracyM) || heartbeatDue) {
      _store(fix, WaypointType.normal, addDistance: true); // ر2 — from the anchor
      return WaypointType.normal;
    }
    return WaypointType.skipped;
  }

  /// Idle state machine (ر6) with NO store side effects: `_process` owns every
  /// append, guaranteeing exactly one store decision per fix (fix round 2).
  _IdleTransition _updateIdle(RawFix fix, double speed) {
    if (speed < config.idleSpeedMps) {
      _idleSinceNanos ??= fix.timeNanos;
      if (!_idle && _ticker.secondsSince(_idleSinceNanos!) >= config.idleAfterS) {
        _idle = true;
        return _IdleTransition.entered;
      }
    } else {
      _idleSinceNanos = null;
      if (_idle) {
        _idle = false;
        return _IdleTransition.resumed;
      }
    }
    return _IdleTransition.none;
  }

  /// R40: genuine transport (walk → car → walk) keeps every post-transport
  /// fix disagreeing with the stale anchor, so the anchor must be allowed to
  /// move again — but only after 3 consecutive pairs among the rejected
  /// fixes are mutually consistent at <= v_max, and only the chain's
  /// INTERNAL movement is billed; the teleport gap is never added.
  void _trackReacquisition(StoredPoint p) {
    final prev = _chainPrev;
    if (prev != null) {
      final dt = _ticker.secondsSince(prev.timeNanos);
      final d = haversineMeters(prev.lat, prev.lon, p.lat, p.lon);
      if (dt > 0 && d / dt <= config.maxSpeedMps) {
        _consistentPairs++;
        _chainDistanceM += d;
        if (_consistentPairs >= _reanchorAfterPairs) {
          _anchor = p;
          _distanceM += _chainDistanceM;
          _resetChain();
          return;
        }
        _chainPrev = p;
        return;
      }
    }
    // Chain start, or this fix is inconsistent with the previous one:
    // the chain restarts here.
    _chainPrev = p;
    _consistentPairs = 0;
    _chainDistanceM = 0;
  }

  void _resetChain() {
    _chainPrev = null;
    _consistentPairs = 0;
    _chainDistanceM = 0;
  }

  /// Appends to the polyline (`storedPoints`: map, distance, resume
  /// checkpoint), stamps the ر3 heartbeat clock (_lastAppendNanos), and moves
  /// the anchor only when the point passed the jump test — rejected points
  /// are kept (ر9) but must never become the yardstick (R39).
  StoredPoint _store(RawFix fix, WaypointType type, {required bool addDistance}) {
    final anchor = _anchor;
    if (addDistance && anchor != null) {
      _distanceM += haversineMeters(anchor.lat, anchor.lon, fix.lat, fix.lon);
    }
    final p = StoredPoint(
      lat: fix.lat, lon: fix.lon, timeNanos: fix.timeNanos, accuracyM: fix.accuracyM,
      type: type, altitudeM: fix.altitudeM, speedMps: fix.speedMps, bearingDeg: fix.bearingDeg,
    );
    _points.add(p);
    _lastAppendNanos = fix.timeNanos;
    if (type != WaypointType.rejected) _anchor = p;
    return p;
  }
}

/// Outcome of the ر6 idle state machine for the fix just processed. Exposes no
/// store side effects — the caller in `_process` makes the single append
/// decision (fix round 2, Important 1).
enum _IdleTransition { none, entered, resumed }
