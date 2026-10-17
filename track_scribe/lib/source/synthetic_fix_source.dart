import 'dart:async';

import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/fix_source.dart';

/// Emits a straight-line walk at a constant [speedMps] with a fixed
/// [accuracyM], timestamped from a real [Stopwatch], so the whole recording
/// pipeline (engine gates, idle logic, distance accumulation) runs in tests
/// and on the emulator with no GPS hardware.
///
/// Every fix it emits carries `isMocked: true` (ر10). That is not decoration:
/// the engine counts mocked fixes and `recording_controller.dart` writes the
/// count into `activities.mock_detected`, so a session this source produced
/// is stamped as simulated wherever the row is read — on a debug phone driven
/// by `synthetic.mode` (borrow 1أ) just as in a unit test. A number nobody
/// measured is never allowed to look like a GPS measurement.
///
/// Note (ruling R21): [Stopwatch] is real time and is NOT faked by the test
/// framework's `pump` — only [Timer.periodic] is. Widget tests must therefore
/// never assert elapsed-time-derived values after fake pumps; the distance
/// assertion lives in a real-async controller test instead.
class SyntheticFixSource implements FixSource {
  SyntheticFixSource({
    this.everyMs = 100,
    this.speedMps = 1.4,
    this.accuracyM = 3.0,
  });

  final int everyMs;
  final double speedMps;
  final double accuracyM;

  StreamController<RawFix>? _c;
  Timer? _t;
  final _sw = Stopwatch();
  double _dLat = 0;

  /// The live controller, reopened only when it is absent or closed, so a
  /// listener that already holds the stream keeps receiving events.
  StreamController<RawFix> _stream() {
    final c = _c;
    if (c != null && !c.isClosed) return c;
    return _c = StreamController<RawFix>.broadcast();
  }

  @override
  Stream<RawFix> get fixes => _stream().stream;

  @override
  Future<void> start() async {
    // A closed controller cannot receive events, so a session that follows a
    // stop() gets a fresh one — that is the start → stop → start contract of
    // [FixSource]. Position and clock deliberately keep running: a restart that
    // teleported the walker back to the origin would be an impossible jump.
    final out = _stream();
    _sw.start();
    _t = Timer.periodic(Duration(milliseconds: everyMs), (_) {
      _dLat += speedMps * (everyMs / 1000.0);
      out.add(
        RawFix(
          lat: 36.7538 + _dLat / 111111.0,
          lon: 3.1856,
          timeNanos: _sw.elapsedMicroseconds * 1000,
          accuracyM: accuracyM,
          speedMps: speedMps,
          isMocked: true,
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    _t?.cancel();
    _t = null;
    _sw.stop();
    await _c?.close();
  }
}
