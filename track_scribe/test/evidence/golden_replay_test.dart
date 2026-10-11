import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/sport_config.dart';

import '../../tool/replay_core.dart';

/// Device golden replay (plan Task 11 step 3). Reads ONLY
/// `test/evidence/fixtures/real/` — one `.gpx` per measured course plus a
/// `.truth` sidecar (ground-truth metres on line 1, optional accuracy on
/// line 2). While the directory is empty this file registers a single
/// skipped test with the reason printed, never a fake verdict.
void main() {
  final realDir = Directory('test/evidence/fixtures/real');
  final fixtures = <File>[];
  if (realDir.existsSync()) {
    fixtures.addAll(realDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gpx')));
  }
  fixtures.sort((a, b) => a.path.compareTo(b.path));

  if (fixtures.isEmpty) {
    const reason = 'SKIPPED — test/evidence/fixtures/real/ has no device '
        'fixture yet. Capture one on the phone per '
        'test/evidence/fixtures/README.md (never faked, never cited as '
        'device evidence).';
    // ignore: avoid_print
    print('golden_replay_test: $reason');
    test('device golden replay', () {}, skip: reason);
    return;
  }

  for (final file in fixtures) {
    final basename = file.path.split(RegExp(r'[\\/]')).last;
    final name = basename.substring(0, basename.length - '.gpx'.length);
    final truthLines =
        File('${file.path}.truth').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    if (truthLines.isEmpty) {
      fail('$name has an empty .truth sidecar');
    }
    final truthM = double.parse(truthLines.first.trim());
    final accuracyM = truthLines.length > 1 ? double.parse(truthLines[1].trim()) : 5.0;
    final sport = switch (name.split('-').first) {
      'bike' => Sport.bike,
      'run' => Sport.run,
      _ => Sport.walk,
    };

    test('$name replays within 1 % of measured truth', () {
      final engineM = engineDistanceFromGpx(file.readAsStringSync(),
          sport: sport, accuracyM: accuracyM);
      final err = (engineM - truthM).abs() / truthM;
      expect(err, lessThan(0.01),
          reason: 'got ${engineM.toStringAsFixed(1)} m vs truth '
              '${truthM.toStringAsFixed(1)} m');
    });
  }
}
