import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/sport_config.dart';

import '../../tool/replay_core.dart';

/// Stationary device evidence (plan Task 11, ruling R102).
///
/// These four fixtures are the Realme C33 sitting on a desk with the screen on
/// and a run recording — captured 2026-10-11, pulled out of the activity DB
/// with `adb exec-out run-as … cat databases/track_scribe.sqlite | base64`.
/// Their ground truth is ZERO metres: the phone did not move, and nobody drove
/// it. That is the one course a phone can measure for itself, which is why it
/// is the first real fixture this project has.
///
/// They live in `fixtures/real/stationary/` and NOT in `fixtures/real/`
/// because `golden_replay_test.dart` grades a relative error
/// `|engine − truth| / truth`; with a truth of 0 m that quotient is undefined.
/// A stationary course needs an absolute budget in metres, which is what this
/// file asserts.
///
/// Measured on the build shipped before R99–R102 (replayed through the
/// production engine, so the CI number and the persisted `distance_m` agree):
///
///   run-0m-desk-1  123.3 m   (persisted 169.5 m over 115 s)
///   run-0m-desk-2  121.4 m   (persisted 167.4 m over 160 s)
///   run-0m-desk-3   25.2 m   (persisted  25.2 m over  45 s)
///   run-0m-desk-4  375.1 m   (persisted 375.1 m over 329 s)
///
/// The budget below is 5 m per session — about the width of the parked phone's
/// own noise circle at the best of the four accuracies, and small enough that
/// the shipped defect (375.1 m) fails it by two orders of magnitude.
Directory _stationaryDir() {
  final relative = Directory('test/evidence/fixtures/real/stationary');
  if (relative.existsSync()) return relative;
  for (
    var dir = Directory.current;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final candidate = Directory(
      '${dir.path}${Platform.pathSeparator}test/evidence/fixtures/real/stationary',
    );
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync() &&
        candidate.existsSync()) {
      return candidate;
    }
  }
  return relative;
}

Sport _sportOf(String fixtureName) => switch (fixtureName.split('-').first) {
  'bike' => Sport.bike,
  'run' => Sport.run,
  'walk' => Sport.walk,
  _ => throw FormatException(
    'fixture name must start with walk-/run-/bike-, got "$fixtureName"',
  ),
};

/// A stationary fixture is honest only if BOTH the engine replay and the
/// recorded elapsed time agree, so the phantom can never be hidden by a track
/// that stopped early.
void main() {
  final dir = _stationaryDir();
  final fixtures = <File>[
    if (dir.existsSync())
      ...dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gpx')),
  ]..sort((a, b) => a.path.compareTo(b.path));

  if (fixtures.isEmpty) {
    const reason = 'SKIPPED — test/evidence/fixtures/real/stationary/ has no '
        'device fixture. Capture one per fixtures/README.md; never fake it.';
    // ignore: avoid_print
    print('stationary_drift_test: $reason (searched ${dir.absolute.path}; '
        'runner cwd ${Directory.current.path})');
    test('stationary drift', () {}, skip: reason);
    return;
  }

  for (final file in fixtures) {
    final basename = file.path.split(RegExp(r'[\\/]')).last;
    final name = basename.substring(0, basename.length - '.gpx'.length);

    test('$name: a phone that never moved bills no distance', () {
      final sidecar = File('${file.path}.truth');
      if (!sidecar.existsSync()) {
        fail('$name has no .truth sidecar — no ground truth, no verdict');
      }
      final lines =
          sidecar.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) fail('$name has an empty .truth sidecar');
      final truthM = double.parse(lines.first.trim());
      // A truth other than 0 belongs to golden_replay_test.dart, not here:
      // an absolute budget is the wrong grade for a course that has length.
      expect(truthM, 0.0,
          reason: '$name is graded against zero metres, not a ratio');
      final accuracyM = lines.length > 1 ? double.parse(lines[1].trim()) : 5.0;
      final engineM = engineDistanceFromGpx(
        file.readAsStringSync(),
        sport: _sportOf(name),
        accuracyM: accuracyM,
      );
      // ignore: avoid_print
      print('$name: engine ${engineM.toStringAsFixed(1)} m billed while '
          'stationed (accuracy $accuracyM m)');
      expect(
        engineM,
        lessThan(5.0),
        reason: 'phantom distance: the phone was on a desk the whole time',
      );
    });
  }
}
