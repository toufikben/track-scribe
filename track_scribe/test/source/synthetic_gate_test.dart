import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';
import 'package:track_scribe/source/synthetic_gate.dart';

// Borrow 1أ (docs/BORROW-FROM-TRAILMARK.md §1أ), ported behaviour from
// trailmark's `app/gps/SyntheticFixSource.kt`, which is switched on by an
// adb-supplied intent extra. This device rejects mock location
// (`cmd location … add-test-provider`), so an in-app source is the only way
// to measure ر105/ر106/§2/§3 on a table.
//
// The rule is split so the whole of it is testable with no platform channel:
// a pure decision (`chooseFixSource`) and one file probe
// (`syntheticMarkerPresent`) whose only untestable part is path_provider.
void main() {
  group('chooseFixSource — the entire rule, no filesystem, no platform', () {
    test('debug + marker: the synthetic walk', () {
      expect(
        chooseFixSource(debugMode: true, markerPresent: true),
        isA<SyntheticFixSource>(),
      );
    });

    test('release ignores the marker: a store build can never fake a walk', () {
      // The load-bearing half. If this ever returns SyntheticFixSource, a
      // leftover synthetic.mode on a user's phone becomes a fake GPS.
      expect(
        chooseFixSource(debugMode: false, markerPresent: true),
        isA<GeolocatorFixSource>(),
      );
    });

    test('debug with no marker stays on the real GNSS', () {
      expect(
        chooseFixSource(debugMode: true, markerPresent: false),
        isA<GeolocatorFixSource>(),
      );
    });
  });

  group('syntheticMarkerPresent — the file probe', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('synthetic-gate');
    });
    tearDown(() => dir.delete(recursive: true));

    test('a file named synthetic.mode in the documents dir is the only key', () async {
      Future<bool> probe() =>
          syntheticMarkerPresent(documentsDirectory: () async => dir);
      expect(await probe(), isFalse);
      File(p.join(dir.path, kSyntheticMarkerName)).createSync();
      expect(await probe(), isTrue);
    });

    test('a marker elsewhere is not the key', () async {
      File(p.join(dir.path, 'other.mode')).createSync();
      expect(
        await syntheticMarkerPresent(documentsDirectory: () async => dir),
        isFalse,
      );
    });

    test('a failing probe answers false: boot never crashes over a switch', () async {
      expect(
        await syntheticMarkerPresent(
          documentsDirectory: () async =>
              throw const FileSystemException('path_provider has no platform'),
        ),
        isFalse,
      );
    });
  });

  test('resolveFixSource() with no platform falls through to the real GNSS', () async {
    // main() calls this. Under `flutter test` kDebugMode is true, so the
    // probe does run — and getApplicationDocumentsDirectory() has no platform
    // channel here. The contract is that it degrades to GeolocatorFixSource
    // instead of throwing at startup.
    expect(await resolveFixSource(), isA<GeolocatorFixSource>());
  });

  group('honesty: a synthetic fix is never narrated as a GPS measurement', () {
    const cfg = SportConfig(sport: Sport.walk, maxSpeedMps: 2.0);

    test('the source stamps its own fixes as mocked (ر10)', () async {
      final src = SyntheticFixSource(everyMs: 10);
      final first = src.fixes.first;
      await src.start();
      final fix = await first;
      await src.stop();
      expect(fix.isMocked, isTrue);
    });

    test('and the engine counts it, which is what writes mock_detected', () async {
      final src = SyntheticFixSource(everyMs: 10);
      final first = src.fixes.first;
      await src.start();
      final fix = await first;
      await src.stop();
      final engine = RecorderEngine(cfg, startNanos: 0);
      engine.onFix(fix);
      // recording_controller.dart maps `stats.mockFixCount > 0` onto the
      // activities.mock_detected column, so a table run is stamped as one.
      expect(engine.stats.mockFixCount, 1);
    });
  });
}
