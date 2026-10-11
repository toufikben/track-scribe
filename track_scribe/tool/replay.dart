import 'dart:io';

import 'package:gpx/gpx.dart';
import 'package:track_scribe/engine/sport_config.dart';

import 'replay_core.dart';

/// Evidence harness CLI (plan Task 11 step 2):
///
///   dart run tool/replay.dart FILE.gpx --truth 1000 [--sport walk]
///   dart run tool/replay.dart --gen test/evidence/fixtures/synthetic/NAME.gpx
///       [--metres 1000] [--speed 1.4] [--jitter 10]
///
/// Both `--flag value` and `--flag=value` forms are accepted. The first form
/// prints one markdown table row — append it to
/// `docs/superpowers/evidence/2026-10-09-fidelity-baseline.md`. The second
/// writes a deterministic synthetic fixture into `fixtures/synthetic/`
/// (ground truth exact by construction; never cited as device evidence).
Future<void> main(List<String> args) async {
  try {
    final map = _parseArgs(args);
    if (map.containsKey('gen')) {
      await _generate(map);
    } else {
      await _replay(map);
    }
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 64;
  } on ArgumentError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 64;
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  final leftovers = <String>[];
  var i = 0;
  while (i < args.length) {
    final a = args[i];
    if (a.startsWith('--')) {
      final name = a.substring(2);
      if (name.contains('=')) {
        final parts = name.split('=');
        map[parts.first] = parts.last;
      } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        map[name] = args[++i];
      } else {
        map[name] = 'true';
      }
    } else {
      leftovers.add(a);
    }
    i++;
  }
  map['_file'] = leftovers.firstOrNull ?? '';
  return map;
}

Future<void> _replay(Map<String, String> map) async {
  final file = map['_file'];
  if (file == null || file.isEmpty) {
    throw const FormatException('missing <file.gpx>');
  }
  final truthStr = map['truth'];
  if (truthStr == null) throw const FormatException('missing --truth <metres>');

  final xml = File(file).readAsStringSync();
  final sport = switch (map['sport'] ?? 'walk') {
    'run' => Sport.run,
    'bike' => Sport.bike,
    _ => Sport.walk,
  };
  final accuracy = double.parse(map['accuracy'] ?? '5');
  final truth = double.parse(truthStr);
  final distance = engineDistanceFromGpx(xml, sport: sport, accuracyM: accuracy);
  final err = (distance - truth).abs() / truth * 100;
  stdout.writeln(
    '| ${file.split(RegExp(r'[\\/]')).last} | '
    '${distance.toStringAsFixed(1)} | ${truth.toStringAsFixed(1)} | '
    '${err.toStringAsFixed(2)} |',
  );
}

Future<void> _generate(Map<String, String> map) async {
  final path = map['gen'];
  if (path == null || path == 'true') {
    throw const FormatException('--gen needs an output path');
  }
  double opt(String name, double dflt) =>
      map[name] == null ? dflt : double.parse(map[name]!);

  final points = syntheticTrackPoints(
    metres: opt('metres', 1000),
    speedMps: opt('speed', 1.4),
    jitterM: opt('jitter', 10),
  );
  final gpx = Gpx()
    ..creator = 'track_scribe tool/replay.dart'
    ..trks.add(Trk(name: 'synthetic', trksegs: [Trkseg(trkpts: points)]));
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(GpxWriter().asString(gpx, pretty: true));
  stdout.writeln('wrote $path (${points.length} points, synthetic)');
}
