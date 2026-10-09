import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/core/monotonic.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';

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
/// stored, accumulates distance from the LAST STORED point (ر2), rejects
/// impossible jumps without deleting them (ر4/ر9), and marks standing-still
/// as IDLE while time keeps flowing (ر6). Imports no Flutter, dart:io, or
/// plugin — testable on the desktop with `flutter test` alone.
class RecorderEngine {
  /// Deliberately does NOT pre-accept [startNanos] into the ticker: a first
  /// fix stamped exactly `startNanos` is legitimate (elapsed 0), and the
  /// ticker's strict `>` gate would silently drop it. The ticker remains the
  /// single source of truth for ordering (ر1) and for every duration below.
  RecorderEngine(this.config, {required int startNanos})
      : _sessionStartNanos = startNanos,
        _ticker = MonotonicTicker();

  final SportConfig config;
  final MonotonicTicker _ticker;
  final int _sessionStartNanos;
  final List<StoredPoint> _points = [];

  StoredPoint? _lastStored;
  int? _idleSinceNanos;
  bool _idle = false;
  bool _hasAcceptedFix = false;
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
    // earlier timestamps are dropped, never averaged.
    if (!_ticker.accept(fix.timeNanos)) {
      _dropped++;
      return;
    }
    _hasAcceptedFix = true;
    _fixCount++;
    if (fix.isMocked) _mocks++;                       // ر10

    final last = _lastStored;
    if (last == null) { _store(fix, WaypointType.normal, addDistance: false); return; }

    final dt = _ticker.secondsSince(last.timeNanos);
    final d = haversineMeters(last.lat, last.lon, fix.lat, fix.lon);
    final impliedSpeed = dt > 0 ? d / dt : null;
    final speed = fix.speedMps ?? impliedSpeed;        // Doppler wins over differencing

    // ر4 — impossible jump: keep the raw point, add nothing to distance.
    // Spec ر4/ر5 threshold is v_max itself; the brief's draft used 2× v_max,
    // a silent relaxation the spec does not authorise — spec wins.
    if (d > config.maxJumpM ||
        (impliedSpeed != null && impliedSpeed > config.maxSpeedMps)) {
      _rejected++;
      _store(fix, WaypointType.rejected, addDistance: false);
      return;
    }

    _updateIdle(fix, speed ?? 0.0);

    final heartbeatDue =
        _ticker.secondsSince(last.timeNanos) >= config.forceStoreAfterS;
    if (_idle) {
      // ر6 — time flows, distance does not.
      if (heartbeatDue && !_lastWasIdleMarker) _store(fix, WaypointType.idle, addDistance: false);
      return;
    }
    if (d >= config.gateFor(fix.accuracyM) || heartbeatDue) {
      _store(fix, WaypointType.normal, addDistance: true); // ر2 — from last STORED
    }
  }

  bool get _lastWasIdleMarker =>
      _lastStored != null && _lastStored!.type == WaypointType.idle;

  void _updateIdle(RawFix fix, double speed) {
    if (speed < config.idleSpeedMps) {
      _idleSinceNanos ??= fix.timeNanos;
      if (!_idle && _ticker.secondsSince(_idleSinceNanos!) >= config.idleAfterS) {
        _idle = true;
        _store(fix, WaypointType.idle, addDistance: false);
      }
    } else {
      _idleSinceNanos = null;
      if (_idle) { _idle = false; _store(fix, WaypointType.normal, addDistance: false); }
    }
  }

  void _store(RawFix fix, WaypointType type, {required bool addDistance}) {
    final last = _lastStored;
    if (addDistance && last != null) {
      _distanceM += haversineMeters(last.lat, last.lon, fix.lat, fix.lon);
    }
    final p = StoredPoint(
      lat: fix.lat, lon: fix.lon, timeNanos: fix.timeNanos, accuracyM: fix.accuracyM,
      type: type, altitudeM: fix.altitudeM, speedMps: fix.speedMps, bearingDeg: fix.bearingDeg,
    );
    _points.add(p);
    _lastStored = p;
  }
}
