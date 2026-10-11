import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';
import 'package:track_scribe/state/recording_controller.dart';
import '../support/controlled_fix_source.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

// R80: recording sessions now touch sqlite (resume checkpoint + per-point
// writes). Every test in this file overrides the database with an in-memory
// one — `flutter test` must never reach getApplicationDocumentsDirectory().
final _dbOverrides = <Override>[
  appDatabaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
];

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
        ..._dbOverrides,
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

  // Task 9: the promotion rule is ر7 (two consecutive fixes ≤ 35 m), not
  // "a fix arrived". A hand-driven source makes both halves of that provable
  // without a phone.

  test('ر7: the session stays in starting until two consecutive good fixes', () async {
    final src = ControlledFixSource();
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    expect(src.startCalls, 1);

    src.emit(accuracyM: 3.0); // one good fix: ر7 is not satisfied yet
    await _settle();
    var s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.starting);
    expect(s.engine, isNull, reason: 'nothing is recorded before ر7 opens');
    expect(
      s.quality,
      GpsQuality.ok,
      reason: 'D3: the live tier follows the current fix\'s accuracy; the '
          'withholding of `recording` is the phase, not a doctored tier',
    );

    src.emit(accuracyM: 3.0); // the second consecutive good fix
    await _settle();
    s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.recording);
    expect(s.quality, GpsQuality.ok);
    expect(
      s.fixCount,
      1,
      reason: 'the promoting fix is the first the engine ever saw — the '
          'pre-gate fixes must not reach the recorder',
    );

    await controller.stop();
    expect(src.stopCalls, 1);
    expect(container.read(recordingProvider).phase, RecordingPhase.stopped);
    await src.dispose();
  });

  test('a signal that never gets good enough is cancellable, not a dead end', () async {
    // The ruling carried over from Task 7: with a real GNSS source that never
    // becomes good enough, a button disabled in `starting` would strand the
    // user forever.
    final src = ControlledFixSource();
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    src.emitMany(5, accuracyM: 90); // five fixes, none ≤ 35 m
    await _settle();
    final s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.starting);
    expect(s.engine, isNull);

    await controller.stop(); // the cancel gesture
    expect(container.read(recordingProvider).phase, RecordingPhase.stopped);
    expect(src.stopCalls, 1, reason: 'the sensors are released on cancel too');
    await src.dispose();
  });

  test('the quality tier keeps reporting once ر7 has opened', () async {
    final src = ControlledFixSource();
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    src.emitMany(2, accuracyM: 4.0);
    await _settle();
    expect(container.read(recordingProvider).quality, GpsQuality.ok);

    src.emit(accuracyM: 25.0); // 20–35 tier, gate stays open
    await _settle();
    var s = container.read(recordingProvider);
    expect(s.quality, GpsQuality.degraded);
    expect(s.phase, RecordingPhase.recording);

    src.emit(accuracyM: 90.0); // > 35: the current fix is `searching` (D3 —
    // the tier table is the authority), while ر7, a start gate, stays open.
    await _settle();
    s = container.read(recordingProvider);
    expect(s.quality, GpsQuality.searching);
    expect(s.phase, RecordingPhase.recording);

    await controller.stop();
    await src.dispose();
  });

  test('a source that cannot start does not strand the UI in starting', () async {
    final src = ControlledFixSource()
      ..startFailure = const LocationPermissionDenied();
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.stopped,
      reason: 'the permission screen (Task 9c) owns this case; the recorder '
          'must leave the user a working button, not a spinner',
    );
    expect(
      container.read(recordingProvider).permissionDenied,
      isTrue,
      reason: 'R86: a denied permission is distinguished from a generic start '
          'failure so AppGate can route to the instructions screen',
    );
    await src.dispose();
  });

  test('a generic start failure returns to stopped without a permission claim',
      () async {
    // The other half of the R86 split: only LocationPermissionDenied sets
    // permissionDenied; any other throw must leave it false so a dead sensor
    // never masquerades as a permission problem.
    final src = ControlledFixSource()..startFailure = StateError('sensor dead');
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    final s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.stopped);
    expect(s.permissionDenied, isFalse);
    await src.dispose();
  });

  test('a stream error mid-recording is a gap in the signal, not the end of it', () async {
    // The controller subscribes with cancelOnError: false so one platform
    // error cannot silently unsubscribe the session mid-walk; the fixes after
    // the error must still reach the engine and stop() must still work.
    final src = ControlledFixSource()..stepNanos = 2000000000; // 2 s cadence
    final container = ProviderContainer(
      overrides: [fixSourceProvider.overrideWithValue(src), ..._dbOverrides],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    src.emitMany(2, accuracyM: 3.0); // ر7 opens
    await _settle();
    expect(container.read(recordingProvider).phase, RecordingPhase.recording);

    src.addError(Exception('GNSS provider died'));
    await _settle();
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.recording,
      reason: 'the error alone must not change the session state',
    );

    // Keep the walker moving: 0.0001° latitude ≈ 11.1 m every 2 s ≈ 5.6 m/s,
    // inside ر5 for a run and over the 6 m store gate, so real distance.
    var lat = 36.7538;
    for (var i = 0; i < 3; i++) {
      lat += 0.0001;
      src.emit(lat: lat);
    }
    await _settle();
    final s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.recording);
    expect(s.distanceM, greaterThan(0),
        reason: 'fixes after the error must still advance the distance');

    await controller.stop();
    expect(container.read(recordingProvider).phase, RecordingPhase.stopped);
    await src.dispose();
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
