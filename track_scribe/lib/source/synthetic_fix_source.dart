import 'dart:async';

import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/fix_source.dart';

/// Emits a straight-line walk at a constant [speedMps] with a fixed
/// [accuracyM], timestamped from a real [Stopwatch], so the whole recording
/// pipeline (engine gates, idle logic, distance accumulation) runs in tests
/// and on the emulator with no GPS hardware.
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

  final _c = StreamController<RawFix>.broadcast();
  Timer? _t;
  final _sw = Stopwatch();
  double _dLat = 0;

  @override
  Stream<RawFix> get fixes => _c.stream;

  @override
  Future<void> start() async {
    _sw.start();
    _t = Timer.periodic(Duration(milliseconds: everyMs), (_) {
      _dLat += speedMps * (everyMs / 1000.0);
      _c.add(
        RawFix(
          lat: 36.7538 + _dLat / 111111.0,
          lon: 3.1856,
          timeNanos: _sw.elapsedMicroseconds * 1000,
          accuracyM: accuracyM,
          speedMps: speedMps,
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    _t?.cancel();
    _sw.stop();
    await _c.close();
  }
}
