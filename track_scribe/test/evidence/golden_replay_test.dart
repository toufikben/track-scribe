import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/sport_config.dart';

import '../../tool/replay_core.dart';

/// Device golden replay (plan Task 11 step 3). Reads ONLY
/// `test/evidence/fixtures/real/` — one `.gpx` per measured course plus a
/// `.truth` sidecar (ground-truth metres on line 1, optional accuracy on line
/// 2). While the directory is empty this file registers a single skipped test
/// with the reason printed, never a fake verdict.
///
/// All sidecar reading happens INSIDE the test bodies: a malformed fixture has
/// to fail its own test, not crash `main()` and take the whole suite down with
/// it (which would look like a build failure, not a evidence failure).

/// The fixtures directory, resolved from the package root rather than from
/// whatever the runner's cwd happens to be.
Directory _realFixturesDir() {
  final relative = Directory('test/evidence/fixtures/real');
  if (File('pubspec.yaml').existsSync() || relative.existsSync()) {
    return relative;
  }
  // `Directory.parent` is non-nullable and returns the root itself at the top,
  // so the walk-up is bounded by "parent == self", not by null.
  for (
    var dir = Directory.current;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final pubspec = File(
      '${dir.path}${Platform.pathSeparator}pubspec.yaml',
    );
    final candidate = Directory(
      '${dir.path}${Platform.pathSeparator}test/evidence/fixtures/real',
    );
    if (pubspec.existsSync() && candidate.existsSync()) return candidate;
  }
  return relative;
}

Sport _sportOf(String fixtureName) => switch (fixtureName.split('-').first) {
  'bike' => Sport.bike,
  'run' => Sport.run,
  'walk' => Sport.walk,
  // No silent default: a fixture named `hike-1km.gpx` must not be graded
  // against the walk constants and then cited as device evidence.
  _ => throw FormatException(
    'fixture name must start with walk-/run-/bike-, got "$fixtureName"',
  ),
};

void main() {
  final realDir = _realFixturesDir();
  final fixtures = <File>[
    if (realDir.existsSync())
      ...realDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gpx')),
  ]..sort((a, b) => a.path.compareTo(b.path));

  if (fixtures.isEmpty) {
    const reason = 'SKIPPED — test/evidence/fixtures/real/ has no device '
        'fixture yet. Capture one on the phone per '
        'test/evidence/fixtures/README.md (never faked, never cited as '
        'device evidence).';
    // A skip is only honest if it means "no fixture", never "wrong directory".
    // ignore: avoid_print
    print(
      'golden_replay_test: $reason (searched ${realDir.absolute.path}; '
      'runner cwd ${Directory.current.path})',
    );
    test('device golden replay', () {}, skip: reason);
    return;
  }

  for (final file in fixtures) {
    final basename = file.path.split(RegExp(r'[\\/]')).last;
    final name = basename.substring(0, basename.length - '.gpx'.length);

    test('$name replays within 1 % of measured truth', () {
      final sidecar = File('${file.path}.truth');
      if (!sidecar.existsSync()) {
        fail('$name has no .truth sidecar — no ground truth, no verdict');
      }
      final truthLines = sidecar
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (truthLines.isEmpty) {
        fail('$name has an empty .truth sidecar');
      }
      final truthM = double.parse(truthLines.first.trim());
      final accuracyM = truthLines.length > 1
          ? double.parse(truthLines[1].trim())
          : 5.0;
      final engineM = engineDistanceFromGpx(
        file.readAsStringSync(),
        sport: _sportOf(name),
        accuracyM: accuracyM,
      );
      final err = (engineM - truthM).abs() / truthM;
      expect(
        err,
        lessThan(0.01),
        reason:
            'got ${engineM.toStringAsFixed(1)} m vs truth '
            '${truthM.toStringAsFixed(1)} m',
      );
    });
  }
}
