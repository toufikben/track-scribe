import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';
import 'package:track_scribe/state/recording_controller.dart';

void main() {
  // R21: the distance assertion lives here, in a pure-Dart run of the real
  // controller + real synthetic source — no tester pumps (pump fakes
  // Timer.periodic but NOT Stopwatch).
  test('synthetic source accumulates distance through the controller', () async {
    final container = ProviderContainer(
      overrides: [
        // everyMs pinned at 50 per R21. speed/accuracy are tuned so the run
        // store gate (max(3 m, 2·a)) is crossable: the default 1.4 m/s walk
        // would need ~4.3 s to clear a 6 m gate. 3.5 m/s at 20 Hz crosses the
        // 3 m gate at ~0.9 s.
        fixSourceProvider.overrideWithValue(
          SyntheticFixSource(everyMs: 50, speedMps: 3.5, accuracyM: 0.5),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    await _until(() => container.read(recordingProvider).phase == RecordingPhase.recording);
    expect(container.read(recordingProvider).phase, RecordingPhase.recording);

    // Asserted BEFORE stop(): stop() resets the panel state (engine dropped)
    // per the brief's verbatim controller design, so after stop() the live
    // counters are gone by design.
    await _until(() => container.read(recordingProvider).distanceM > 0);
    final state = container.read(recordingProvider);
    expect(state.distanceM, greaterThan(0));
    expect(state.fixCount, greaterThan(0));

    await controller.stop();
    expect(container.read(recordingProvider).phase, RecordingPhase.stopped);
  });

  test('a FixSource can be started and stopped cleanly', () async {
    final FixSource source = SyntheticFixSource(everyMs: 20);
    final received = <int>[];
    final sub = source.fixes.listen((f) => received.add(f.timeNanos));
    await source.start();
    await _until(() => received.length >= 3);
    await source.stop();
    await sub.cancel();
    expect(received.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < received.length; i++) {
      expect(
        received[i],
        greaterThan(received[i - 1]),
        reason: 'monotonic timestamps',
      );
    }
  });
}

/// Waits for [condition] instead of sleeping a fixed window: the source stamps
/// its fixes with a real [Stopwatch] and a wall-clock timer, so any deadline
/// tight enough to catch a broken source is also tight enough to lose to this
/// 2-core box under load (observed: a 2 s wait missing the gate crossing).
/// Returning without the condition lets the caller's own expectation fail with
/// its real message rather than a timing complaint.
Future<void> _until(bool Function() condition,
    {Duration budget = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(budget);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
