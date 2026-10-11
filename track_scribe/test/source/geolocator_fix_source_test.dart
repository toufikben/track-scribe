import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';

gl.Position pos({
  double accuracy = 4.0,
  double altitude = 92.5,
  double speed = 1.4,
  double heading = 42.0,
  bool isMocked = false,
  bool hasAccuracy = true,
  bool hasAltitude = true,
  bool hasSpeed = true,
  bool hasHeading = true,
  DateTime? timestamp,
}) => gl.Position(
  latitude: 36.7538,
  longitude: 3.1856,
  timestamp: timestamp ?? DateTime.utc(2026, 10, 9, 12, 30, 15),
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: 0.0,
  heading: heading,
  headingAccuracy: 0.0,
  speed: speed,
  speedAccuracy: 0.0,
  isMocked: isMocked,
  hasAccuracy: hasAccuracy,
  hasAltitude: hasAltitude,
  hasSpeed: hasSpeed,
  hasHeading: hasHeading,
);

/// The plugin call path is injected so the whole production source is verifiable
/// on the desktop: no phone, no MethodChannel, no fake platform channel.
GeolocatorFixSource source(
  Stream<gl.Position> Function(gl.LocationSettings s) positionStream, {
  gl.LocationPermission checkResult = gl.LocationPermission.whileInUse,
  gl.LocationPermission requestResult = gl.LocationPermission.whileInUse,
}) => GeolocatorFixSource(
  checkPermission: () async => checkResult,
  requestPermission: () async => requestResult,
  positionStream: positionStream,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('R67: the stream is asked for a 200 ms-interval, unfiltered LocationManager feed',
      () async {
    final asked = <gl.LocationSettings>[];
    final ctl = StreamController<gl.Position>();
    final src = source((s) {
      asked.add(s);
      return ctl.stream;
    });
    await src.start();
    await _settle();

    expect(asked, hasLength(1));
    final settings = asked.single as gl.AndroidSettings;
    expect(settings.accuracy, gl.LocationAccuracy.high);
    expect(settings.distanceFilter, 0);
    // The brief's LocationSettings() would have left intervalDuration null,
    // which geolocator_android turns into 5000 ms — a 0.2 Hz feed. The gate,
    // the jump test and the 15 s heartbeat all need a real fix rate.
    expect(settings.intervalDuration, const Duration(milliseconds: 200));
    // No FusedLocationProvider smoothing/batching of stored data, and no
    // runtime dependence on Google Play Services.
    expect(settings.forceLocationManager, isTrue);
    expect(settings.useMSLAltitude, isFalse, reason: 'geoid alignment is Plan 2');

    await src.stop();
    await ctl.close();
  });

  test('R69: screen-off recording is protected by a wake lock and an ongoing notification', () async {
    gl.AndroidSettings? asked;
    final ctl = StreamController<gl.Position>();
    final src = source((s) {
      asked = s as gl.AndroidSettings;
      return ctl.stream;
    });
    await src.start();
    await _settle();

    final n = asked!.foregroundNotificationConfig;
    expect(n, isNotNull, reason: 'a foreground notification is what keeps the '
        'location stream alive when the activity is not in the foreground');
    // Without the wake lock the CPU sleeps and a screen-off walk records a
    // straight line — the spec's own field test.
    expect(n!.enableWakeLock, isTrue);
    expect(n.setOngoing, isTrue);
    expect(n.notificationTitle, 'تسجيل المسار');
    expect(n.notificationText, isNotEmpty);
    expect(n.notificationChannelName, 'تسجيل المسار');

    await src.stop();
    await ctl.close();
  });

  test('Position → RawFix carries the GNSS measurements through (R70)', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    ctl.add(pos(accuracy: 7.5, altitude: 111.25, speed: 2.2, heading: 270.0));
    await _settle();

    expect(got, hasLength(1));
    final fix = got.single;
    expect(fix.lat, 36.7538);
    expect(fix.lon, 3.1856);
    expect(fix.accuracyM, 7.5);
    expect(fix.altitudeM, 111.25);
    expect(fix.speedMps, 2.2);
    expect(fix.bearingDeg, 270.0);
    expect(fix.isMocked, isFalse);
    expect(
      fix.wallMillis,
      DateTime.utc(2026, 10, 9, 12, 30, 15).millisecondsSinceEpoch,
    );
    // ر10 needs the mock flag; it is a non-nullable bool in the plugin, so it
    // is read directly (the brief's `?? false` does not analyze clean).
    ctl.add(pos(isMocked: true));
    await _settle();
    expect(got[1].isMocked, isTrue);

    await src.stop();
    await ctl.close();
  });

  test('a placeholder measurement is null, never a convincing 0.0', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    // LocationMapper only sends fields the platform reports (Location.hasX()),
    // so hasSpeed == false means speed carries NO measurement. Feeding the
    // engine 0.0 there would make ر6 declare a walking user idle.
    ctl.add(pos(hasSpeed: false, speed: 0.0, hasAltitude: false, altitude: 0.0));
    await _settle();

    expect(got.single.speedMps, isNull);
    expect(got.single.altitudeM, isNull);
    expect(got.single.accuracyM, isNot(0.0));

    await src.stop();
    await ctl.close();
  });

  test('timestamps are monotonic across the plugin boundary', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    ctl.add(pos());
    await _settle();
    ctl.add(pos());
    await _settle();

    expect(got[1].timeNanos, greaterThan(got[0].timeNanos));

    await src.stop();
    await ctl.close();
  });

  test('a denied permission throws and never opens the stream', () async {
    var opened = 0;
    final src = source(
      (_) {
        opened++;
        return const Stream<gl.Position>.empty();
      },
      checkResult: gl.LocationPermission.denied,
      requestResult: gl.LocationPermission.denied,
    );

    await expectLater(src.start(), throwsA(isA<LocationPermissionDenied>()));
    expect(opened, 0, reason: 'no sensors started without permission');
  });

  test('a permanently denied permission throws too', () async {
    final src = source(
      (_) => const Stream<gl.Position>.empty(),
      checkResult: gl.LocationPermission.deniedForever,
      requestResult: gl.LocationPermission.deniedForever,
    );
    await expectLater(src.start(), throwsA(isA<LocationPermissionDenied>()));
  });

  test('permission is requested only when it is missing, and a grant opens the stream', () async {
    var opened = 0;
    final ctl = StreamController<gl.Position>();
    final src = source(
      (_) {
        opened++;
        return ctl.stream;
      },
      checkResult: gl.LocationPermission.denied,
      requestResult: gl.LocationPermission.whileInUse,
    );

    await src.start();
    expect(opened, 1, reason: 'the user granted it in the dialog, so the feed opens');

    await src.stop();
    await ctl.close();
  });

  test('start → stop → start emits again on the stream a listener already holds', () async {
    // The FixSource restart contract (lib/source/fix_source.dart): recording
    // twice in one app session is an ordinary gesture. stop() cancels the
    // plugin subscription and must NOT close the output controller.
    final first = StreamController<gl.Position>();
    final second = StreamController<gl.Position>();
    final pluginStreams = [first.stream, second.stream];
    var calls = 0;
    final src = source((_) => pluginStreams[calls++]);

    final got = <RawFix>[];
    final sub = src.fixes.listen(got.add); // subscribed before the first start

    await src.start();
    first.add(pos());
    await _settle();
    expect(got, hasLength(1));

    await src.stop();
    first.add(pos());
    await _settle();
    expect(got, hasLength(1), reason: 'stop() really cancelled the plugin stream');

    await src.start();
    second.add(pos());
    await _settle();
    expect(got, hasLength(2), reason: 'the pre-stop listener still receives');
    expect(calls, 2, reason: 'start() re-subscribed to the plugin');

    await src.stop();
    await sub.cancel();
    await first.close();
    await second.close();
  });

  // R74: an UNMEASURED accuracy must never read as a perfect fix. Android's
  // `Location.hasAccuracy() == false` makes the plugin model substitute
  // `accuracy == 0.0`; mapping that through would open ر7 against a phantom
  // anchor — the exact failure ر7 exists to prevent.

  test('R74: a hasAccuracy == false fix maps to unmeasuredAccuracyM, never 0.0', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    ctl.add(pos(hasAccuracy: false, accuracy: 0.0));
    await _settle();

    expect(got.single.accuracyM, unmeasuredAccuracyM);
    expect(
      got.single.accuracyM,
      isNot(0.0),
      reason: '0.0 claims a perfect 1σ the platform never measured',
    );

    await src.stop();
    await ctl.close();
  });

  test('R74: two consecutive unmeasured-accuracy fixes never open ر7 and read as searching', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    // Injected monotonic counter, never the wall clock (project rule).
    final gate = FixQualityGate(nowNanos: () => 0);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    ctl.add(pos(hasAccuracy: false, accuracy: 0.0));
    await _settle();
    ctl.add(pos(hasAccuracy: false, accuracy: 0.0));
    await _settle();
    expect(got, hasLength(2));
    for (final fix in got) {
      gate.add(fix);
    }

    expect(
      gate.ready,
      isFalse,
      reason: 'two unmeasured fixes are not two good fixes; ر7 must stay shut',
    );
    expect(gate.quality, GpsQuality.searching);

    await src.stop();
    await ctl.close();
  });

  test('R74: an unmeasured fix breaks the consecutive-good streak, it does not count toward it', () async {
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    // Two gates, one per scenario: ر7 counts CONSECUTIVE fixes, so a shared
    // gate would carry the first scenario's streak into the second.
    final afterUnmeasured = FixQualityGate(nowNanos: () => 0);
    final midStreak = FixQualityGate(nowNanos: () => 0);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    // Scenario A — unmeasured, then one real 12 m fix: ر7 needs TWO
    // consecutive good fixes, so the good fix after the sentinel restarts the
    // streak at 1 and the gate stays shut.
    ctl.add(pos(hasAccuracy: false, accuracy: 0.0));
    await _settle();
    ctl.add(pos(accuracy: 12.0));
    await _settle();
    ctl.add(pos(accuracy: 12.0));
    await _settle();
    expect(afterUnmeasured.add(got[0]), isFalse);
    expect(afterUnmeasured.add(got[1]), isFalse,
        reason: 'the good fix restarts the streak at 1');
    expect(afterUnmeasured.add(got[2]), isTrue,
        reason: 'only the second consecutive good fix opens ر7');

    // Scenario B — good, sentinel, good: the sentinel must break the streak
    // exactly like a > 35 m fix does.
    ctl.add(pos(accuracy: 12.0));
    await _settle();
    ctl.add(pos(hasAccuracy: false, accuracy: 0.0));
    await _settle();
    ctl.add(pos(accuracy: 12.0));
    await _settle();
    expect(midStreak.add(got[3]), isFalse); // one good fix
    expect(midStreak.add(got[4]), isFalse); // sentinel breaks the streak
    expect(midStreak.add(got[5]), isFalse,
        reason: 'good(1) → sentinel(0) → good(1): never two consecutive');

    await src.stop();
    await ctl.close();
  });

  test('a platform stream error is forwarded to listeners and keeps the fix feed alive', () async {
    // onError: out.addError + cancelOnError: false (geolocator_fix_source
    // .dart) is the whole error contract: the controller cannot tell the user
    // about a signal gap it never learns about, and one error must not end a
    // recording by silently unsubscribing.
    final ctl = StreamController<gl.Position>();
    final src = source((_) => ctl.stream);
    final got = <RawFix>[];
    final errors = <Object>[];
    final sub = src.fixes.listen(
      got.add,
      onError: (Object e) => errors.add(e),
      cancelOnError: false,
    );

    await src.start();
    ctl.addError(Exception('GNSS provider died'));
    await _settle();
    expect(errors, hasLength(1), reason: 'the error must actually arrive');

    ctl.add(pos());
    await _settle();
    expect(got, hasLength(1),
        reason: 'a later fix must still flow — the subscription survived the error');

    await src.stop();
    await sub.cancel();
    await ctl.close();
  });

  test('M5: start() twice without stop() leaves exactly one live subscription', () async {
    // The double-start guard: a second start() must cancel the first plugin
    // subscription before taking a new one, or two sensors feed one controller
    // and every fix arrives doubled.
    final first = StreamController<gl.Position>();
    final second = StreamController<gl.Position>();
    final pluginStreams = [first.stream, second.stream];
    var calls = 0;
    final src = source((_) => pluginStreams[calls++]);
    final got = <RawFix>[];
    src.fixes.listen(got.add);

    await src.start();
    await src.start(); // no stop() in between
    expect(calls, 2, reason: 'the guard is not a refusal: the plugin is asked again');

    first.add(pos());
    await _settle();
    expect(got, isEmpty, reason: 'the first subscription was cancelled by the second start()');

    second.add(pos());
    await _settle();
    expect(got, hasLength(1), reason: 'fixes must not be doubled by a stale live subscription');

    await src.stop();
    await first.close();
    await second.close();
  });
}
