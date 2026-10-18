import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_source.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/export/export_format.dart';
import 'package:track_scribe/export/gpx_document.dart';
import 'package:track_scribe/export/tcx_document.dart';
import 'package:track_scribe/export/track_exporter.dart';

/// `startWallMillis` of every fixture below: 2023-11-14T22:13:20Z. The same
/// instant the exported document stamps as its own start, which is why the
/// file name is asserted as a literal rather than recomputed.
const _startMillis = 1700000000000;

ActivitySummary _summary({String sport = 'run', required List<StoredPoint> points}) =>
    ActivitySummary(
      id: 7,
      sport: sport,
      startWallMillis: _startMillis,
      distanceM: 6400,
      elapsedNanos: 2_000_000_000_000,
      source: kSourceRecorded,
      fixCount: points.length,
      rejectedCount: 0,
      mockDetected: false,
      points: points,
    );

StoredPoint _fix(double lat, int t) => StoredPoint(
  lat: lat,
  lon: 3.04,
  timeNanos: t,
  accuracyM: 5,
  type: WaypointType.normal,
);

/// Two increasing fixes — the case the writers DO put times in, so the bytes
/// on disk are the full document, not a degenerate one.
final _route = [_fix(36.7538, 0), _fix(36.7540, 5_000_000_000)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late TrackExporter exporter;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('track_scribe_exports');
    exporter = TrackExporter(baseDirectory: () async => base);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  group('the file name (§2أ)', () {
    test('carries the activity start stamp, the sport and the extension', () {
      expect(
        exportFileName(_summary(points: _route), ExportFormat.gpx),
        'track-scribe-20231114T221320Z-run.gpx',
      );
      expect(
        exportFileName(_summary(sport: 'bike', points: _route), ExportFormat.tcx),
        'track-scribe-20231114T221320Z-bike.tcx',
      );
    });

    test('is ASCII-only, because it crosses into other apps\' file systems', () {
      final name = exportFileName(_summary(points: _route), ExportFormat.gpx);
      expect(name.codeUnits.every((u) => u < 128), isTrue);
      expect(name, isNot(contains(' ')));
    });

    test('the two formats never collide on the same activity', () {
      final s = _summary(points: _route);
      expect(
        exportFileName(s, ExportFormat.gpx) == exportFileName(s, ExportFormat.tcx),
        isFalse,
      );
    });
  });

  group('writing the document out', () {
    test('the bytes on disk are exactly what the GPX writer returned', () async {
      final summary = _summary(points: _route);
      final file = await exporter.export(summary, ExportFormat.gpx);
      expect(await file.readAsString(), buildGpxDocument(summary));
    });

    test('the bytes on disk are exactly what the TCX writer returned', () async {
      final summary = _summary(points: _route);
      final file = await exporter.export(summary, ExportFormat.tcx);
      expect(await file.readAsString(), buildTcxDocument(summary));
    });

    test('exports go to their own directory under the app support dir', () async {
      final file = await exporter.export(
        _summary(points: _route),
        ExportFormat.gpx,
      );
      expect(p.equals(file.parent.path, p.join(base.path, 'exports')), isTrue);
      expect(await file.parent.exists(), isTrue);
    });

    test('re-exporting one activity replaces its file instead of piling up', () async {
      final summary = _summary(points: _route);
      await exporter.export(summary, ExportFormat.gpx);
      await exporter.export(summary, ExportFormat.gpx);
      expect(base.listSync(recursive: true).whereType<File>(), hasLength(1));
    });

    test('an activity whose only fix was rejected still writes a valid file', () async {
      final summary = _summary(
        points: [
          StoredPoint(
            lat: 36.7,
            lon: 3.04,
            timeNanos: 0,
            accuracyM: 40,
            type: WaypointType.rejected,
          ),
        ],
      );
      final file = await exporter.export(summary, ExportFormat.gpx);
      final text = await file.readAsString();
      // ر115 as a FILE-level fact: the writer filtered the rejected fix, so
      // nothing in the bytes may claim that coordinate exists.
      expect(text, isNot(contains('36.700000')));
      expect(text, startsWith('<?xml'));
    });
  });

  group('handing the file to Android', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kShareChannel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kShareChannel, null);
    });

    test('one export writes, then shares the path it just wrote', () async {
      final file = await exporter.exportAndShare(
        _summary(points: _route),
        ExportFormat.gpx,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      expect(file.existsSync(), isTrue);
      expect(
        (calls.single.arguments! as Map)['path'],
        p.join(base.path, 'exports', 'track-scribe-20231114T221320Z-run.gpx'),
      );
    });

    test('the MIME type is the one the format claims, not text/plain', () async {
      await exporter.exportAndShare(_summary(points: _route), ExportFormat.gpx);
      await exporter.exportAndShare(_summary(points: _route), ExportFormat.tcx);
      expect(
        calls.map((c) => (c.arguments! as Map)['mimeType']),
        ['application/gpx+xml', 'application/vnd.garmin.tcx+xml'],
      );
    });

    test('a share failure is not swallowed: the caller must be able to say so', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kShareChannel, (call) async {
            throw PlatformException(code: 'no_activity');
          });
      expect(
        () => exporter.exportAndShare(_summary(points: _route), ExportFormat.gpx),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
