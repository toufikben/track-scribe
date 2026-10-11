import 'dart:async';

import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/fix_source.dart';

/// A [FixSource] the test drives by hand: nothing is emitted until [emit], so
/// ر7's gate, the `starting` phase and the cancel path are reproducible with no
/// phone, no stopwatch and no wall-clock waiting.
///
/// Timestamps are 1 s apart by default and strictly increasing, which the
/// engine's monotonic ticker requires.
class ControlledFixSource implements FixSource {
  StreamController<RawFix>? _c;
  Timer? _auto;

  int startCalls = 0;
  int stopCalls = 0;

  /// Makes [start] fail the way the production source does when the user has
  /// not granted location access.
  Object? startFailure;

  /// The first emitted fix carries this timestamp; each later one is
  /// [stepNanos] further.
  int _nextTimeNanos = 0;
  int stepNanos = 1000000000;

  StreamController<RawFix> get _out =>
      _c ??= StreamController<RawFix>.broadcast();

  @override
  Stream<RawFix> get fixes => _out.stream;

  @override
  Future<void> start() async {
    startCalls++;
    final failure = startFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _auto?.cancel();
    _auto = null;
  }

  /// Feeds one fix into the stream the controller subscribed to.
  void emit({double accuracyM = 3.0, double lat = 36.7538, double lon = 3.1856, double? speedMps}) {
    _out.add(
      RawFix(
        lat: lat,
        lon: lon,
        timeNanos: _nextTimeNanos,
        accuracyM: accuracyM,
        speedMps: speedMps,
      ),
    );
    _nextTimeNanos += stepNanos;
  }

  void emitMany(int count, {double accuracyM = 3.0}) {
    for (var i = 0; i < count; i++) {
      emit(accuracyM: accuracyM);
    }
  }

  /// Injects a stream error, the way a dying platform GNSS provider does: the
  /// consumer must survive it (`cancelOnError: false`) without ending the feed.
  void addError(Object error, [StackTrace? stackTrace]) {
    _out.addError(error, stackTrace ?? StackTrace.current);
  }

  /// Lets a widget test hand control back to the fake-async clock: `pump` can
  /// only drive timers, so fixes that must arrive "later" go through a Timer.
  void emitLater({double accuracyM = 3.0}) {
    _auto = Timer(Duration.zero, () => emit(accuracyM: accuracyM));
  }

  Future<void> dispose() async {
    _auto?.cancel();
    await _c?.close();
    _c = null;
  }
}
