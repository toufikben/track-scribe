import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/import/gpx_file_source.dart';
import 'package:track_scribe/import/gpx_track.dart';

/// A three-point document, the shortest shape a real GPX file from another app
/// carries. Its content is irrelevant to these tests — only its arrival does.
const _gpx =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<gpx version="1.1" creator="other-app" '
    'xmlns="http://www.topografix.com/GPX/1/1">'
    '<trk><trkseg>'
    '<trkpt lat="36.75" lon="3.04"><time>2023-11-14T22:13:20Z</time></trkpt>'
    '<trkpt lat="36.76" lon="3.05"><time>2023-11-14T22:14:20Z</time></trkpt>'
    '</trkseg></trk></gpx>';

/// Records what the Dart side asked the platform, and replies with whatever a
/// test needs it to — a document, a cancellation, a failure.
class _FakePlatform {
  _FakePlatform(this.reply);

  /// What `open` answers: the file's text, or null when the user backed out.
  Object? reply;

  final List<MethodCall> calls = [];

  /// Thrown instead of replying, to stand in for a platform-side failure.
  bool fails = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kImportChannel, (call) async {
          calls.add(call);
          if (fails) throw PlatformException(code: 'read_failed');
          return reply;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kImportChannel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  const source = SafGpxFileSource();

  setUp(() {
    platform = _FakePlatform(_gpx)..install();
  });
  tearDown(() => platform.uninstall());

  group('the picker channel', () {
    test('one press asks the platform for exactly one document', () async {
      final text = await source.readDocument();
      expect(text, _gpx);
      expect(platform.calls, hasLength(1));
      expect(platform.calls.single.method, 'open');
    });

    test('a cancelled picker answers null — an absence, not an empty file', () async {
      platform.reply = null;
      expect(await source.readDocument(), isNull, reason: '''
A document is allowed to be empty (the reader then says «الملف ليس مستند GPX»),
but a cancellation is not a document at all. If both arrive as "" the UI must
apologise for a file the user never picked — ر99 in its UI form: no surface
states a thing that was not measured, including a refusal.''');
    });

    test('a platform failure is not swallowed on the way to the caller', () async {
      platform.fails = true;
      await expectLater(source.readDocument(), throwsA(isA<PlatformException>()));
    });

    test('a too-large document is passed through untouched for the reader to refuse', () async {
      // The size cap is the reader's ruling, in characters, and the platform
      // guard is the same number in bytes. Neither one truncates silently:
      // a clipped file would parse as a shorter route than the user picked.
      final huge = _oneTrack() + ' ' * kMaxGpxSourceChars;
      platform.reply = huge;
      final text = await source.readDocument();
      expect(text, hasLength(huge.length));
      expect(() => parseGpxTrack(text!), throwsA(isA<GpxParseException>()));
    });
  });
}

String _oneTrack() =>
    '<trk><trkseg><trkpt lat="36.75" lon="3.04"/></trkseg></trk>';
